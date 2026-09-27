<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Enums\UserRole;
use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\User;
use App\Models\VendorProfile;
use Illuminate\Http\JsonResponse;

class AdminMapController extends Controller
{
    public function show(): JsonResponse
    {
        $vendors = VendorProfile::query()
            ->with('user:id,name,email,last_latitude,last_longitude,last_located_at')
            ->get()
            ->map(function (VendorProfile $profile) {
                $user = $profile->user;
                $lat = $user?->last_latitude ?? $profile->latitude;
                $lng = $user?->last_longitude ?? $profile->longitude;
                if ($lat === null || $lng === null) {
                    return null;
                }

                return [
                    'id' => $profile->id,
                    'slug' => $profile->slug,
                    'name' => $profile->business_name,
                    'business_name' => $profile->business_name,
                    'latitude' => (float) $lat,
                    'longitude' => (float) $lng,
                    'live' => $user?->last_located_at !== null,
                    'updated_at' => $user?->last_located_at?->toIso8601String(),
                ];
            })
            ->filter()
            ->values();

        $seenCustomers = [];
        $customers = [];

        $liveCustomers = User::query()
            ->where('role', UserRole::Customer)
            ->whereNotNull('last_latitude')
            ->whereNotNull('last_longitude')
            ->get(['id', 'name', 'email', 'last_latitude', 'last_longitude', 'last_located_at']);

        foreach ($liveCustomers as $user) {
            $seenCustomers[$user->id] = true;
            $customers[] = [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'latitude' => (float) $user->last_latitude,
                'longitude' => (float) $user->last_longitude,
                'live' => true,
                'updated_at' => $user->last_located_at?->toIso8601String(),
            ];
        }

        $orders = Order::query()
            ->with('customer:id,name,email,phone,last_latitude,last_longitude,last_located_at')
            ->orderByDesc('placed_at')
            ->limit(200)
            ->get();

        foreach ($orders as $order) {
            $coords = $order->deliveryCoordinates();
            if ($coords === null) {
                continue;
            }
            $customerId = (int) $order->customer_id;
            if (isset($seenCustomers[$customerId])) {
                continue;
            }
            $seenCustomers[$customerId] = true;
            $customers[] = [
                'id' => $customerId,
                'name' => $order->customer?->name,
                'order_number' => $order->order_number,
                'latitude' => $coords[0],
                'longitude' => $coords[1],
                'live' => false,
            ];
        }

        return response()->json([
            'data' => [
                'vendors' => $vendors,
                'customers' => $customers,
            ],
        ]);
    }
}
