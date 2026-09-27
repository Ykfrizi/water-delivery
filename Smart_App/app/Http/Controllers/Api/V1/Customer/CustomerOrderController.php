<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use App\Notifications\OrderStatusChangedNotification;
use App\Services\OrderInventoryService;
use App\Services\OrderStatusTransition;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class CustomerOrderController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $perPage = min(max((int) $request->input('per_page', 15), 1), 50);

        $orders = Order::query()
            ->where('customer_id', $request->user()->id)
            ->with(['vendorProfile:id,slug,business_name', 'orderItems'])
            ->orderByDesc('placed_at')
            ->paginate($perPage);

        return OrderResource::collection($orders);
    }

    public function show(Request $request, Order $order): OrderResource
    {
        if ((int) $order->customer_id !== (int) $request->user()->id) {
            abort(404);
        }

        $order->load(['vendorProfile:id,slug,business_name', 'orderItems']);

        return new OrderResource($order);
    }

    public function update(Request $request, Order $order): OrderResource
    {
        if ((int) $order->customer_id !== (int) $request->user()->id) {
            abort(404);
        }

        $request->validate([
            'status' => ['required', Rule::in([OrderStatus::Cancelled->value])],
        ]);

        $next = OrderStatus::Cancelled;

        if (! OrderStatusTransition::customerMayMove($order->status, $next)) {
            throw ValidationException::withMessages([
                'status' => ['Only pending orders can be cancelled.'],
            ]);
        }

        $previous = $order->status;
        $order->status = $next;
        $order->save();

        if ($next === OrderStatus::Cancelled && $previous !== OrderStatus::Cancelled) {
            OrderInventoryService::releaseStockForCancellation($order->fresh(['orderItems']), $previous);
        }

        $order->load(['vendorProfile:id,slug,business_name,user_id', 'vendorProfile.user', 'orderItems']);

        $vendorUser = $order->vendorProfile?->user;
        if ($vendorUser !== null && $previous !== $next) {
            $vendorUser->notify(new OrderStatusChangedNotification($order, $previous, 'customer'));
        }

        return new OrderResource($order);
    }
}
