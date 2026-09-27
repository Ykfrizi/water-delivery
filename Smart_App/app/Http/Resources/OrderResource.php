<?php

namespace App\Http\Resources;

use App\Http\Resources\OrderItemResource;
use App\Services\OrderStatusTransition;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Order */
class OrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $coords = $this->deliveryCoordinates();

        return [
            'order_number' => $this->order_number,
            'status' => $this->status->value,
            'allowed_next_statuses' => OrderStatusTransition::vendorPickerStatuses($this->status),
            'subtotal' => (float) $this->subtotal,
            'delivery_fee' => (float) $this->delivery_fee,
            'discount_amount' => (float) $this->discount_amount,
            'voucher_code' => $this->voucher_code,
            'total' => (float) $this->total,
            'currency' => $this->currency,
            'payment_status' => $this->payment_status->value,
            'payment_method' => $this->payment_method,
            'pay_on_delivery' => $this->isPayOnDelivery(),
            'payment_label' => $this->isPayOnDelivery()
                ? 'Pay on delivery'
                : ($this->isPaid() ? 'Paid' : 'Unpaid'),
            'paid_at' => $this->paid_at?->toIso8601String(),
            'notes' => $this->notes,
            'customer_phone' => $this->customer?->phone
                ?? (is_array($this->shipping_address) ? ($this->shipping_address['phone'] ?? null) : null),
            'shipping_address' => $this->shipping_address,
            'latitude' => $coords[0] ?? null,
            'longitude' => $coords[1] ?? null,
            'customer_latitude' => $coords[0] ?? null,
            'customer_longitude' => $coords[1] ?? null,
            'courier_latitude' => $this->courier_latitude,
            'courier_longitude' => $this->courier_longitude,
            'placed_at' => $this->placed_at?->toIso8601String(),
            'customer' => $this->whenLoaded('customer', fn () => [
                'id' => $this->customer->id,
                'name' => $this->customer->name,
                'email' => $this->customer->email,
                'phone' => $this->customer->phone,
                'latitude' => $this->customer->last_latitude,
                'longitude' => $this->customer->last_longitude,
                'last_located_at' => $this->customer->last_located_at?->toIso8601String(),
            ]),
            'vendor' => $this->whenLoaded('vendorProfile', fn () => [
                'slug' => $this->vendorProfile->slug,
                'business_name' => $this->vendorProfile->business_name,
                'latitude' => $this->vendorProfile->latitude,
                'longitude' => $this->vendorProfile->longitude,
            ]),
            'items' => OrderItemResource::collection($this->whenLoaded('orderItems')),
        ];
    }
}
