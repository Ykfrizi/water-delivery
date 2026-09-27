<?php

namespace App\Services;

use App\Models\DeliveryShareLink;
use App\Models\Order;
use App\Models\VendorProfile;

final class DeliveryShareLinkService
{
    public const TTL_HOURS = 24;

    public function issue(Order $order, VendorProfile $profile): DeliveryShareLink
    {
        $reusable = DeliveryShareLink::query()
            ->where('order_id', $order->id)
            ->where('vendor_profile_id', $profile->id)
            ->where('expires_at', '>', now()->addMinutes(30))
            ->latest('id')
            ->first();

        if ($reusable !== null) {
            return $reusable;
        }

        return DeliveryShareLink::query()->create([
            'order_id' => $order->id,
            'vendor_profile_id' => $profile->id,
            'token' => bin2hex(random_bytes(32)),
            'expires_at' => now()->addHours(self::TTL_HOURS),
        ]);
    }
}
