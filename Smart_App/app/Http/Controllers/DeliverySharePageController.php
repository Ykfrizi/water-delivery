<?php

namespace App\Http\Controllers;

use App\Models\DeliveryShareLink;
use Illuminate\Contracts\View\View;
use Illuminate\Http\Response;

class DeliverySharePageController extends Controller
{
    public function show(string $token): View|Response
    {
        $link = DeliveryShareLink::query()
            ->where('token', $token)
            ->with([
                'order.customer:id,name,phone,last_latitude,last_longitude',
                'order.orderItems',
                'order.vendorProfile:id,business_name',
            ])
            ->first();

        if ($link === null || $link->isExpired() || $link->order === null) {
            return response()->view('delivery.unavailable', [
                'expired' => $link !== null && $link->isExpired(),
            ], 404);
        }

        $order = $link->order;
        $shipping = is_array($order->shipping_address) ? $order->shipping_address : [];
        $coords = $order->deliveryCoordinates();
        $address = $this->formatAddress($shipping);
        $phone = $order->customer?->phone
            ?? (isset($shipping['phone']) ? (string) $shipping['phone'] : null)
            ?? (isset($shipping['mobile']) ? (string) $shipping['mobile'] : null);
        $name = $order->customer?->name
            ?? (isset($shipping['name']) ? (string) $shipping['name'] : null)
            ?? (isset($shipping['recipient']) ? (string) $shipping['recipient'] : null)
            ?? 'Customer';

        $mapsUrl = null;
        if ($coords !== null) {
            $mapsUrl = 'https://www.google.com/maps/dir/?api=1&destination='
                .rawurlencode($coords[0].','.$coords[1]);
        } elseif ($address !== '') {
            $mapsUrl = 'https://www.google.com/maps/search/?api=1&query='.rawurlencode($address);
        }

        return view('delivery.share', [
            'order' => $order,
            'customerName' => $name,
            'customerPhone' => $phone ? trim((string) $phone) : null,
            'address' => $address,
            'latitude' => $coords[0] ?? null,
            'longitude' => $coords[1] ?? null,
            'mapsUrl' => $mapsUrl,
            'expiresAt' => $link->expires_at,
            'shopName' => $order->vendorProfile?->business_name ?? 'Water Delivery',
        ]);
    }

    /**
     * @param  array<string, mixed>  $shipping
     */
    private function formatAddress(array $shipping): string
    {
        $parts = [];
        foreach ([
            $shipping['line1'] ?? $shipping['address'] ?? $shipping['street'] ?? $shipping['address_line'] ?? null,
            $shipping['line2'] ?? null,
            $shipping['city'] ?? $shipping['town'] ?? null,
            $shipping['region'] ?? $shipping['state'] ?? null,
        ] as $part) {
            if (is_string($part) && trim($part) !== '') {
                $parts[] = trim($part);
            }
        }

        return implode(', ', $parts);
    }
}
