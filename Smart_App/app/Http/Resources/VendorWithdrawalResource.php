<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\VendorWithdrawal */
class VendorWithdrawalResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'amount' => (float) $this->amount,
            'currency' => $this->currency,
            'method' => $this->method->value,
            'status' => $this->status->value,
            'bank_name' => $this->bank_name,
            'account_name' => $this->account_name,
            'account_number' => $this->account_number,
            'momo_network' => $this->momo_network,
            'momo_number' => $this->momo_number,
            'momo_name' => $this->momo_name,
            'destination' => $this->destinationLabel(),
            'admin_notes' => $this->admin_notes,
            'processed_at' => $this->processed_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            'vendor' => $this->whenLoaded('vendorProfile', fn () => [
                'id' => $this->vendorProfile->id,
                'slug' => $this->vendorProfile->slug,
                'business_name' => $this->vendorProfile->business_name,
            ]),
        ];
    }
}
