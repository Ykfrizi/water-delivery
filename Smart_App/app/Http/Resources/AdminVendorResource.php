<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\VendorProfile */
class AdminVendorResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'slug' => $this->slug,
            'business_name' => $this->business_name,
            'description' => $this->description,
            'phone' => $this->phone,
            'ghana_card_number' => $this->ghana_card_number,
            'location' => [
                'city' => $this->city,
                'region' => $this->region,
                'country' => $this->country,
                'latitude' => $this->user?->last_latitude ?? $this->latitude,
                'longitude' => $this->user?->last_longitude ?? $this->longitude,
            ],
            'latitude' => $this->user?->last_latitude ?? $this->latitude,
            'longitude' => $this->user?->last_longitude ?? $this->longitude,
            'categories' => $this->categories ?? [],
            'approval_status' => $this->approval_status->value,
            'approval_notes' => $this->approval_notes,
            'reviewed_at' => $this->reviewed_at?->toIso8601String(),
            'is_active' => $this->is_active,
            'average_rating' => (float) $this->average_rating,
            'ratings_count' => $this->ratings_count,
            'created_at' => $this->created_at?->toIso8601String(),
            'owner' => $this->whenLoaded('user', fn () => [
                'id' => $this->user->id,
                'name' => $this->user->name,
                'email' => $this->user->email,
            ]),
            'reviewed_by_admin' => $this->whenLoaded('reviewedBy', fn () => $this->reviewedBy ? [
                'id' => $this->reviewedBy->id,
                'name' => $this->reviewedBy->name,
                'email' => $this->reviewedBy->email,
            ] : null),
        ];
    }
}
