<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use App\Models\User;
use App\Models\VendorProfile;
use App\Notifications\OrderStatusChangedNotification;
use App\Services\OrderInventoryService;
use App\Services\OrderStatusTransition;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\ValidationException;

class AdminOrderController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $perPage = min(max((int) $request->input('per_page', 20), 1), 100);

        $query = Order::query()
            ->with([
                'customer:id,name,email,phone,last_latitude,last_longitude,last_located_at',
                'vendorProfile:id,slug,business_name,latitude,longitude',
                'orderItems',
            ])
            ->orderByDesc('placed_at');

        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }

        if ($request->filled('from')) {
            $query->whereDate('placed_at', '>=', $request->date('from')->format('Y-m-d'));
        }

        if ($request->filled('to')) {
            $query->whereDate('placed_at', '<=', $request->date('to')->format('Y-m-d'));
        }

        if ($request->filled('vendor_slug')) {
            $vendorId = VendorProfile::query()
                ->where('slug', $request->string('vendor_slug'))
                ->value('id');
            if ($vendorId === null) {
                $query->whereRaw('1 = 0');
            } else {
                $query->where('vendor_profile_id', $vendorId);
            }
        }

        if ($request->filled('customer_email')) {
            $email = $request->string('customer_email');
            $customerIds = User::query()
                ->where('email', 'like', '%'.$email.'%')
                ->pluck('id');
            $query->whereIn('customer_id', $customerIds);
        }

        if ($request->filled('order_number')) {
            $query->where('order_number', 'like', '%'.$request->string('order_number').'%');
        }

        return OrderResource::collection($query->paginate($perPage));
    }

    public function show(Order $order): OrderResource
    {
        $order->load([
            'customer:id,name,email,phone,last_latitude,last_longitude,last_located_at',
            'vendorProfile:id,slug,business_name,latitude,longitude',
            'orderItems',
        ]);

        return new OrderResource($order);
    }

    public function update(Request $request, Order $order): OrderResource
    {
        $validated = $request->validate([
            'status' => ['required', 'string'],
        ]);

        $next = OrderStatus::fromInput($validated['status']);
        if ($next === null) {
            throw ValidationException::withMessages([
                'status' => ['The selected status is invalid. Use confirmed, cancelled, or completed.'],
            ]);
        }

        if (! OrderStatusTransition::adminMayMove($order->status, $next)) {
            throw ValidationException::withMessages([
                'status' => ['This status change is not allowed.'],
            ]);
        }

        $previous = $order->status;
        $order->status = $next;
        $order->save();

        if ($next === OrderStatus::Cancelled && $previous !== OrderStatus::Cancelled) {
            OrderInventoryService::releaseStockForCancellation($order->fresh(['orderItems']), $previous);
        }

        $order->load([
            'customer:id,name,email,phone,last_latitude,last_longitude,last_located_at',
            'vendorProfile:id,slug,business_name,user_id,latitude,longitude',
            'vendorProfile.user',
            'orderItems',
        ]);

        if ($previous !== $next) {
            if ($order->customer !== null) {
                $order->customer->notify(new OrderStatusChangedNotification($order, $previous, 'admin'));
            }

            $vendorUser = $order->vendorProfile?->user;
            if ($vendorUser !== null) {
                $vendorUser->notify(new OrderStatusChangedNotification($order, $previous, 'admin'));
            }
        }

        return new OrderResource($order);
    }
}
