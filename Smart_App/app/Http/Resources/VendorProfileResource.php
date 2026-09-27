<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\VendorProfile */
class VendorProfileResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'slug' => $this->slug,
            'business_name' => $this->business_name,
            'description' => $this->description,
            'logo_url' => $this->logo_url,
            'phone' => $this->phone,
            'ghana_card_number' => $this->ghana_card_number,
            'location' => [
                'city' => $this->city,
                'region' => $this->region,
                'country' => $this->country,
                'latitude' => $this->latitude,
                'longitude' => $this->longitude,
            ],
            'categories' => $this->categories ?? [],
            'approval_status' => $this->approval_status->value,
            'is_active' => $this->is_active,
            'auto_approve' => [
                'enabled' => (bool) $this->auto_approve_enabled,
                'active_now' => $this->isAutoApprovingOrders(),
                'starts_at' => $this->auto_approve_starts_at?->toIso8601String(),
                'ends_at' => $this->auto_approve_ends_at?->toIso8601String(),
                'daily_start' => $this->formatTimeOnly($this->auto_approve_daily_start),
                'daily_end' => $this->formatTimeOnly($this->auto_approve_daily_end),
                'timezone' => $this->auto_approve_timezone ?: 'Africa/Accra',
            ],
            'average_rating' => (float) $this->average_rating,
            'ratings_count' => $this->ratings_count,
            'distance_km' => $this->when(
                array_key_exists('distance_km', $this->getAttributes()),
                fn () => round((float) $this->distance_km, 2)
            ),
            'delivery_zones' => DeliveryZoneResource::collection($this->whenLoaded('deliveryZones')),
            'products' => ProductResource::collection($this->whenLoaded('products')),
        ];
    }

    private function formatTimeOnly(mixed $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        if ($value instanceof \DateTimeInterface) {
            return $value->format('H:i');
        }

        $raw = (string) $value;
        if (preg_match('/^(\d{2}:\d{2})(:\d{2})?$/', $raw, $matches)) {
            return $matches[1];
        }

        try {
            return \Illuminate\Support\Carbon::parse($raw)->format('H:i');
        } catch (\Throwable) {
            return null;
        }
    }
}
