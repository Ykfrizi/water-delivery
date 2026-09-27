<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\Payment;
use App\Services\Paystack\PaystackClient;
use App\Services\Paystack\PaystackPaymentInitializer;
use App\Services\Paystack\PaystackPaymentProcessor;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class PaystackPaymentController extends Controller
{
    public function __construct(
        private readonly PaystackClient $client,
        private readonly PaystackPaymentProcessor $processor,
        private readonly PaystackPaymentInitializer $initializer,
    ) {}

    public function initialize(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'order_numbers' => ['required', 'array', 'min:1'],
            'order_numbers.*' => ['string'],
            'callback_url' => ['nullable', 'string', 'max:2048'],
        ]);

        if (count($validated['order_numbers']) !== count(array_unique($validated['order_numbers']))) {
            throw ValidationException::withMessages([
                'order_numbers' => ['Duplicate order numbers are not allowed.'],
            ]);
        }

        $user = $request->user();
        $uniqueNumbers = array_unique($validated['order_numbers']);

        $orders = Order::query()
            ->whereIn('order_number', $uniqueNumbers)
            ->where('customer_id', $user->id)
            ->get();

        if ($orders->count() !== count($uniqueNumbers)) {
            throw ValidationException::withMessages([
                'order_numbers' => ['One or more orders were not found on your account.'],
            ]);
        }

        $result = $this->initializer->initialize(
            $user,
            $orders,
            $validated['callback_url'] ?? null,
        );

        return response()->json([
            'authorization_url' => $result['authorization_url'],
            'access_code' => $result['access_code'],
            'reference' => $result['reference'],
            'public_key' => $result['public_key'],
            'amount_minor' => $result['amount_minor'],
            'currency' => $result['currency'],
        ]);
    }

    public function verify(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'reference' => ['nullable', 'string'],
            'trxref' => ['nullable', 'string'],
            'order_number' => ['nullable', 'string'],
            'order_numbers' => ['nullable', 'array'],
            'order_numbers.*' => ['string'],
        ]);

        $user = $request->user();
        $reference = trim((string) ($validated['reference'] ?? $validated['trxref'] ?? ''));
        $orderNumbers = collect($validated['order_numbers'] ?? [])
            ->push($validated['order_number'] ?? '')
            ->map(fn ($n) => trim((string) $n))
            ->filter()
            ->unique()
            ->values();

        $payment = $this->findPaymentToVerify($user->id, $reference, $orderNumbers);
        if ($payment === null) {
            throw ValidationException::withMessages([
                'reference' => ['No Paystack payment was found for this order.'],
            ]);
        }

        $verifyRef = $payment->paystack_reference ?: $payment->reference;
        $response = $this->client->verify($verifyRef);

        if (! $response->successful()) {
            throw ValidationException::withMessages([
                'reference' => [$response->json('message') ?? 'Verification failed.'],
            ]);
        }

        $data = $response->json('data') ?? [];
        if (($data['status'] ?? null) !== 'success') {
            throw ValidationException::withMessages([
                'reference' => ['Paystack has not confirmed this payment yet. If you were charged, wait a moment and try Confirm payment again.'],
            ]);
        }

        $this->processor->confirmPayment($payment->fresh(), $data);

        $payment->refresh();

        $orderIds = $payment->metadata['order_ids'] ?? [];

        $orders = Order::query()
            ->whereIn('id', is_array($orderIds) ? $orderIds : [])
            ->where('customer_id', $user->id)
            ->with(['vendorProfile:id,slug,business_name', 'orderItems'])
            ->get();

        return response()->json([
            'payment' => [
                'reference' => $payment->reference,
                'status' => $payment->status,
                'paid_at' => $payment->paid_at?->toIso8601String(),
            ],
            'orders' => $orders->map(fn (Order $order) => [
                'order_number' => $order->order_number,
                'payment_status' => $order->payment_status instanceof \BackedEnum
                    ? $order->payment_status->value
                    : $order->payment_status,
                'paid_at' => $order->paid_at?->toIso8601String(),
                'status' => $order->status->value,
                'total' => (float) $order->total,
                'currency' => $order->currency,
            ]),
        ]);
    }

    /**
     * @param  \Illuminate\Support\Collection<int, string>  $orderNumbers
     */
    private function findPaymentToVerify(int $customerId, string $reference, $orderNumbers): ?Payment
    {
        $query = Payment::query()->where('customer_id', $customerId);

        if ($reference !== '') {
            return (clone $query)
                ->where(function ($q) use ($reference) {
                    $q->where('reference', $reference)
                        ->orWhere('paystack_reference', $reference);
                })
                ->latest('id')
                ->first();
        }

        if ($orderNumbers->isEmpty()) {
            return null;
        }

        $orderIds = Order::query()
            ->where('customer_id', $customerId)
            ->whereIn('order_number', $orderNumbers)
            ->pluck('id');

        return $query
            ->latest('id')
            ->get()
            ->first(function (Payment $payment) use ($orderIds, $orderNumbers) {
                $meta = is_array($payment->metadata) ? $payment->metadata : [];
                $ids = collect($meta['order_ids'] ?? [])->map(fn ($id) => (int) $id);
                $nums = collect($meta['order_numbers'] ?? [])->map(fn ($n) => (string) $n);

                return $ids->intersect($orderIds->map(fn ($id) => (int) $id))->isNotEmpty()
                    || $nums->intersect($orderNumbers)->isNotEmpty();
            });
    }
}
