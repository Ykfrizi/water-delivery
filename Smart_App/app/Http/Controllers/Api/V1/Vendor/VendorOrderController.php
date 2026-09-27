<?php

namespace App\Http\Controllers\Api\V1\Vendor;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use App\Models\VendorProfile;
use App\Notifications\OrderStatusChangedNotification;
use App\Services\DeliveryShareLinkService;
use App\Services\OrderInventoryService;
use App\Services\OrderStatusTransition;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\ValidationException;

class VendorOrderController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $profile = $this->vendorProfileOrAbort($request);

        $perPage = min(max((int) $request->input('per_page', 15), 1), 50);

        $query = Order::query()
            ->where('vendor_profile_id', $profile->id)
            ->paidForVendor()
            ->with(['customer:id,name,email,phone,last_latitude,last_longitude,last_located_at', 'orderItems'])
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

        return OrderResource::collection($query->paginate($perPage));
    }

    public function show(Request $request, Order $order): OrderResource
    {
        $profile = $this->vendorProfileOrAbort($request);
        $this->assertOwnsOrder($profile, $order);
        $this->assertPaidForVendor($order);

        $order->load(['customer:id,name,email,phone,last_latitude,last_longitude,last_located_at', 'orderItems', 'vendorProfile:id,slug,business_name,latitude,longitude']);

        return new OrderResource($order);
    }

    public function update(Request $request, Order $order): OrderResource
    {
        $profile = $this->vendorProfileOrAbort($request);
        $this->assertOwnsOrder($profile, $order);
        $this->assertPaidForVendor($order);

        $validated = $request->validate([
            'status' => ['required', 'string'],
        ]);

        $rawStatus = strtolower(trim((string) $validated['status']));
        $next = OrderStatus::fromInput($validated['status']);

        $isPendingApproval = $order->status === OrderStatus::Pending
            && in_array($rawStatus, ['confirmed', 'approve', 'approved', 'accept', 'accepted', 'cancelled', 'canceled', 'reject', 'rejected', 'decline', 'declined'], true);

        if (! $isPendingApproval && in_array($rawStatus, OrderStatus::hiddenFromVendorPicker(), true)) {
            throw ValidationException::withMessages([
                'status' => ['confirmed, preparing, and shipped are not available. Use processing, out_for_delivery, delivered, or cancelled.'],
            ]);
        }

        if ($next === null) {
            throw ValidationException::withMessages([
                'status' => $order->status === OrderStatus::Pending
                    ? ['The selected status is invalid. Approve with confirmed, or reject with cancelled.']
                    : ['The selected status is invalid. Use processing, out_for_delivery, delivered, or cancelled.'],
            ]);
        }

        return $this->applyStatusChange($order, $next);
    }

    public function approve(Request $request, Order $order): OrderResource
    {
        $profile = $this->vendorProfileOrAbort($request);
        $this->assertOwnsOrder($profile, $order);
        $this->assertPaidForVendor($order);

        return $this->applyStatusChange($order, OrderStatus::Confirmed);
    }

    public function reject(Request $request, Order $order): OrderResource
    {
        $profile = $this->vendorProfileOrAbort($request);
        $this->assertOwnsOrder($profile, $order);
        $this->assertPaidForVendor($order);

        return $this->applyStatusChange($order, OrderStatus::Cancelled);
    }

    public function updateLocation(Request $request, Order $order): OrderResource
    {
        $profile = $this->vendorProfileOrAbort($request);
        $this->assertOwnsOrder($profile, $order);
        $this->assertPaidForVendor($order);

        $validated = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $order->forceFill([
            'courier_latitude' => $validated['latitude'],
            'courier_longitude' => $validated['longitude'],
            'courier_located_at' => now(),
        ])->save();

        $user = $request->user();
        $user->forceFill([
            'last_latitude' => $validated['latitude'],
            'last_longitude' => $validated['longitude'],
            'last_located_at' => now(),
        ])->save();
        $profile->forceFill([
            'latitude' => $validated['latitude'],
            'longitude' => $validated['longitude'],
        ])->save();

        $order->load(['customer:id,name,email,phone,last_latitude,last_longitude,last_located_at', 'orderItems', 'vendorProfile:id,slug,business_name,latitude,longitude']);

        return new OrderResource($order);
    }

    public function createDeliveryLink(Request $request, Order $order): JsonResponse
    {
        $profile = $this->vendorProfileOrAbort($request);
        $this->assertOwnsOrder($profile, $order);
        $this->assertPaidForVendor($order);

        $link = app(DeliveryShareLinkService::class)->issue($order, $profile);

        return response()->json([
            'data' => [
                'url' => $link->publicUrl($request),
                'token' => $link->token,
                'expires_at' => $link->expires_at?->toIso8601String(),
                'expires_in_hours' => DeliveryShareLinkService::TTL_HOURS,
            ],
        ]);
    }

    private function applyStatusChange(Order $order, OrderStatus $next): OrderResource
    {
        if (! OrderStatusTransition::vendorMayMove($order->status, $next)) {
            throw ValidationException::withMessages([
                'status' => ['This status change is not allowed for your shop.'],
            ]);
        }

        $previous = $order->status;
        $order->status = $next;
        $order->save();

        if ($next === OrderStatus::Cancelled && $previous !== OrderStatus::Cancelled) {
            OrderInventoryService::releaseStockForCancellation($order->fresh(['orderItems']), $previous);
        }

        $order->load(['customer:id,name,email,phone,last_latitude,last_longitude,last_located_at', 'orderItems', 'vendorProfile:id,slug,business_name,latitude,longitude']);

        if ($previous !== $next && $order->customer !== null) {
            $order->customer->notify(new OrderStatusChangedNotification($order, $previous, 'vendor'));
        }

        return new OrderResource($order);
    }

    private function vendorProfileOrAbort(Request $request): VendorProfile
    {
        $profile = $request->user()->vendorProfile;
        if ($profile === null) {
            abort(403, 'Vendor profile is required.');
        }

        return $profile;
    }

    private function assertOwnsOrder(VendorProfile $profile, Order $order): void
    {
        if ((int) $order->vendor_profile_id !== (int) $profile->id) {
            abort(404);
        }
    }

    private function assertPaidForVendor(Order $order): void
    {
        if (! $order->isVisibleToVendor()) {
            abort(404);
        }
    }
}
