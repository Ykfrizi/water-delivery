<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\OrderPaymentStatus;
use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Product;
use App\Models\Voucher;
use App\Notifications\CustomerPurchasedNotification;
use App\Services\Paystack\PaystackPaymentInitializer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CustomerCheckoutController extends Controller
{
    public function __construct(
        private readonly PaystackPaymentInitializer $paystackInitializer,
    ) {}

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'notes' => ['nullable', 'string', 'max:2000'],
            'shipping_address' => ['nullable', 'array'],
            'shipping_address.line1' => ['nullable', 'string', 'max:255'],
            'shipping_address.line2' => ['nullable', 'string', 'max:255'],
            'shipping_address.city' => ['nullable', 'string', 'max:120'],
            'shipping_address.region' => ['nullable', 'string', 'max:120'],
            'shipping_address.country' => ['nullable', 'string', 'max:120'],
            'shipping_address.postal_code' => ['nullable', 'string', 'max:32'],
            'shipping_address.latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'shipping_address.longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'customer_location' => ['nullable', 'array'],
            'customer_location.latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'customer_location.longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'callback_url' => ['nullable', 'string', 'max:2048'],
            'phone' => ['nullable', 'string', 'max:30'],
            'shipping_address.phone' => ['nullable', 'string', 'max:30'],
            'voucher_code' => ['nullable', 'string', 'max:40'],
            'payment_method' => ['nullable', 'string', 'max:40'],
            'payment_provider' => ['nullable', 'string', 'max:40'],
            'pay_on_delivery' => ['sometimes', 'boolean'],
        ]);

        $user = $request->user();
        $userId = $user->id;

        $shipping = $validated['shipping_address'] ?? [];
        $phone = trim((string) ($validated['phone']
            ?? ($shipping['phone'] ?? null)
            ?? $user->phone
            ?? ''));
        if ($phone === '') {
            throw ValidationException::withMessages([
                'phone' => ['Enter your phone number so the vendor can call you after payment.'],
            ]);
        }
        $shipping['phone'] = $phone;
        $user->forceFill(['phone' => $phone])->save();
        $lat = $validated['latitude']
            ?? ($validated['customer_location']['latitude'] ?? null)
            ?? ($shipping['latitude'] ?? null);
        $lng = $validated['longitude']
            ?? ($validated['customer_location']['longitude'] ?? null)
            ?? ($shipping['longitude'] ?? null);
        if (is_numeric($lat) && is_numeric($lng)) {
            $shipping['latitude'] = (float) $lat;
            $shipping['longitude'] = (float) $lng;
            $user->forceFill([
                'last_latitude' => $lat,
                'last_longitude' => $lng,
                'last_located_at' => now(),
            ])->save();
        }
        $validated['shipping_address'] = $shipping === [] ? null : $shipping;

        $rawMethod = strtolower(trim((string) (
            $validated['payment_method']
            ?? $validated['payment_provider']
            ?? 'paystack'
        )));
        $payOnDelivery = filter_var($validated['pay_on_delivery'] ?? false, FILTER_VALIDATE_BOOLEAN)
            || in_array($rawMethod, ['cash_on_delivery', 'pay_on_delivery', 'cod', 'pod'], true);
        $paymentMethod = $payOnDelivery ? 'cash_on_delivery' : 'paystack';

        $orders = DB::transaction(function () use ($userId, $validated, $paymentMethod) {
            $cart = Cart::query()
                ->where('user_id', $userId)
                ->lockForUpdate()
                ->first();

            if ($cart === null) {
                throw ValidationException::withMessages([
                    'cart' => ['Your cart is empty.'],
                ]);
            }

            $itemRows = CartItem::query()
                ->where('cart_id', $cart->id)
                ->orderBy('product_id')
                ->get();

            if ($itemRows->isEmpty()) {
                throw ValidationException::withMessages([
                    'cart' => ['Your cart is empty.'],
                ]);
            }

            $productIds = $itemRows->pluck('product_id')->sort()->values()->all();

            Product::query()
                ->whereIn('id', $productIds)
                ->orderBy('id')
                ->lockForUpdate()
                ->get();

            $items = CartItem::query()
                ->where('cart_id', $cart->id)
                ->with(['product.vendorProfile'])
                ->get();

            foreach ($items as $line) {
                $product = $line->product;
                if (! $product->is_available) {
                    throw ValidationException::withMessages([
                        'cart' => ["Product \"{$product->name}\" is no longer available."],
                    ]);
                }

                if (! $product->vendorProfile->isPubliclyListed()) {
                    throw ValidationException::withMessages([
                        'cart' => ['A vendor in your cart is not accepting orders.'],
                    ]);
                }

                if ($line->quantity > $product->stock_quantity) {
                    throw ValidationException::withMessages([
                        'cart' => ["Not enough stock for \"{$product->name}\"."],
                    ]);
                }
            }

            $currencies = $items->pluck('product.currency')->unique();
            if ($currencies->count() > 1) {
                throw ValidationException::withMessages([
                    'cart' => ['All items must use the same currency to pay with Paystack.'],
                ]);
            }

            $grouped = $items->groupBy(fn ($line) => $line->product->vendor_profile_id);

            $buckets = [];
            $grandSubtotal = 0.0;
            foreach ($grouped as $vendorProfileId => $lines) {
                $currency = (string) $lines->pluck('product.currency')->first();
                $subtotal = round($lines->sum(function ($line) {
                    return (float) $line->product->price * $line->quantity;
                }), 2);
                $grandSubtotal = round($grandSubtotal + $subtotal, 2);
                $buckets[] = [
                    'vendor_profile_id' => (int) $vendorProfileId,
                    'lines' => $lines,
                    'currency' => $currency,
                    'subtotal' => $subtotal,
                ];
            }

            $voucher = null;
            $remainingDiscount = 0.0;
            $code = Voucher::normalizeCode((string) ($validated['voucher_code'] ?? ''));
            if ($code !== '') {
                $voucher = Voucher::query()->where('code', $code)->lockForUpdate()->first();
                if ($voucher === null) {
                    throw ValidationException::withMessages([
                        'voucher_code' => ['Voucher not found.'],
                    ]);
                }
                $voucher->assertRedeemable();
                $remainingDiscount = $voucher->discountAmount($grandSubtotal);
            }

            $created = [];
            $bucketCount = count($buckets);

            foreach ($buckets as $index => $bucket) {
                $subtotal = $bucket['subtotal'];
                $share = 0.0;
                if ($voucher !== null && $grandSubtotal > 0) {
                    if ($index === $bucketCount - 1) {
                        $share = $remainingDiscount;
                    } else {
                        $share = round($remainingDiscount * ($subtotal / $grandSubtotal), 2);
                        $remainingDiscount = round($remainingDiscount - $share, 2);
                    }
                }
                $share = min($share, $subtotal);
                $total = round(max(0.01, $subtotal - $share), 2);

                $order = Order::query()->create([
                    'customer_id' => $userId,
                    'vendor_profile_id' => $bucket['vendor_profile_id'],
                    'status' => OrderStatus::Pending,
                    'payment_status' => OrderPaymentStatus::Unpaid,
                    'payment_method' => $paymentMethod,
                    'subtotal' => $subtotal,
                    'delivery_fee' => 0,
                    'discount_amount' => $share,
                    'voucher_id' => $voucher?->id,
                    'voucher_code' => $voucher?->code,
                    'total' => $total,
                    'currency' => $bucket['currency'],
                    'notes' => $validated['notes'] ?? null,
                    'shipping_address' => $validated['shipping_address'] ?? null,
                ]);

                foreach ($bucket['lines'] as $line) {
                    $product = $line->product;
                    $unitPrice = (float) $product->price;
                    $lineTotal = round($unitPrice * $line->quantity, 2);

                    OrderItem::query()->create([
                        'order_id' => $order->id,
                        'product_id' => $product->id,
                        'product_name' => $product->name,
                        'quantity' => $line->quantity,
                        'unit_price' => $unitPrice,
                        'line_total' => $lineTotal,
                    ]);

                    $product->decrement('stock_quantity', $line->quantity);
                }

                $created[] = $order->fresh(['orderItems', 'vendorProfile.user']);
            }

            if ($voucher !== null) {
                $voucher->increment('used_count');
            }

            CartItem::query()->where('cart_id', $cart->id)->delete();

            return $created;
        });

        if ($paymentMethod === 'cash_on_delivery') {
            foreach ($orders as $order) {
                $vendorUser = $order->vendorProfile?->user;
                if ($vendorUser !== null) {
                    $vendorUser->notify(new CustomerPurchasedNotification($order));
                }
            }

            return response()->json([
                'message' => 'Order placed. Pay the vendor when your delivery arrives.',
                'authorization_url' => null,
                'payment' => null,
                'pay_on_delivery' => true,
                'orders' => collect($orders)
                    ->map(fn (Order $order) => (new OrderResource($order))->toArray(request()))
                    ->values()
                    ->all(),
            ], 201);
        }

        // Vendor is notified only after Paystack confirms payment.

        // Paystack call is outside the DB transaction so stock/orders stay committed.
        try {
            $payment = $this->paystackInitializer->initialize(
                $user,
                $orders,
                $validated['callback_url'] ?? null,
            );
        } catch (ValidationException $e) {
            return response()->json([
                'message' => 'Order placed, but Paystack payment could not be started. Retry payment with the order numbers.',
                'authorization_url' => null,
                'payment' => null,
                'orders' => collect($orders)
                    ->map(fn (Order $order) => (new OrderResource($order))->toArray(request()))
                    ->values()
                    ->all(),
                'errors' => $e->errors(),
            ], 201);
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'Order placed, but Paystack took too long. Open the order and tap Pay with Paystack.',
                'authorization_url' => null,
                'payment' => null,
                'orders' => collect($orders)
                    ->map(fn (Order $order) => (new OrderResource($order))->toArray(request()))
                    ->values()
                    ->all(),
                'errors' => ['paystack' => [$e->getMessage()]],
            ], 201);
        }

        return response()->json([
            'message' => 'Order placed successfully. Redirect the customer to Paystack to complete payment.',
            'authorization_url' => $payment['authorization_url'],
            'payment' => [
                'authorization_url' => $payment['authorization_url'],
                'access_code' => $payment['access_code'],
                'reference' => $payment['reference'],
                'public_key' => $payment['public_key'],
                'amount_minor' => $payment['amount_minor'],
                'currency' => $payment['currency'],
            ],
            'orders' => collect($orders)
                ->map(fn (Order $order) => (new OrderResource($order))->toArray(request()))
                ->values()
                ->all(),
        ], 201);
    }
}
