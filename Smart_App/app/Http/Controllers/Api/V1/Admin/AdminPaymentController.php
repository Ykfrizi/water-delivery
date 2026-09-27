<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\Payment;
use App\Services\Paystack\PaystackMoney;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AdminPaymentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $perPage = min(max((int) $request->input('per_page', 30), 1), 100);

        $paginator = Payment::query()
            ->where('status', Payment::STATUS_SUCCESS)
            ->with('customer:id,name,email')
            ->orderByDesc('paid_at')
            ->orderByDesc('id')
            ->paginate($perPage);

        $orderIds = [];
        foreach ($paginator->items() as $payment) {
            foreach ((array) ($payment->metadata['order_ids'] ?? []) as $id) {
                if (is_numeric($id)) {
                    $orderIds[] = (int) $id;
                }
            }
        }

        $orders = Order::query()
            ->with(['vendorProfile:id,slug,business_name', 'orderItems:id,order_id,product_name,quantity'])
            ->whereIn('id', array_unique($orderIds))
            ->get()
            ->keyBy('id');

        $rows = collect($paginator->items())->map(function (Payment $payment) use ($orders) {
            $ids = collect((array) ($payment->metadata['order_ids'] ?? []))
                ->map(fn ($id) => (int) $id)
                ->filter();
            $linked = $ids->map(fn ($id) => $orders->get($id))->filter();

            $companies = $linked
                ->map(fn (Order $order) => $order->vendorProfile?->business_name)
                ->filter()
                ->unique()
                ->values()
                ->all();

            $products = $linked
                ->flatMap(fn (Order $order) => $order->orderItems->pluck('product_name'))
                ->filter()
                ->unique()
                ->values()
                ->all();

            return [
                'id' => $payment->id,
                'reference' => $payment->reference,
                'paystack_reference' => $payment->paystack_reference,
                'amount' => PaystackMoney::toMajorUnits((int) $payment->amount, (string) $payment->currency),
                'amount_minor' => (int) $payment->amount,
                'currency' => $payment->currency,
                'status' => $payment->status,
                'paid_at' => $payment->paid_at?->toIso8601String(),
                'customer' => $payment->customer === null ? null : [
                    'id' => $payment->customer->id,
                    'name' => $payment->customer->name,
                    'email' => $payment->customer->email,
                ],
                'companies' => $companies,
                'products' => $products,
                'order_numbers' => $linked->pluck('order_number')->values()->all(),
            ];
        })->values();

        return response()->json([
            'data' => $rows,
            'meta' => [
                'current_page' => $paginator->currentPage(),
                'last_page' => $paginator->lastPage(),
                'per_page' => $paginator->perPage(),
                'total' => $paginator->total(),
            ],
        ]);
    }
}
