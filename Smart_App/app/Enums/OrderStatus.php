<?php

namespace App\Enums;

enum OrderStatus: string
{
    case Pending = 'pending';
    case Confirmed = 'confirmed';
    case Processing = 'processing';
    case OutForDelivery = 'out_for_delivery';
    case Delivered = 'delivered';
    case Completed = 'completed';
    case Cancelled = 'cancelled';

    /**
     * Values the vendor status picker must not offer.
     *
     * @return list<string>
     */
    public static function hiddenFromVendorPicker(): array
    {
        return ['confirmed', 'preparing', 'shipped'];
    }

    /**
     * Accept API values plus vendor-app aliases.
     */
    public static function fromInput(mixed $value): ?self
    {
        if ($value instanceof self) {
            return $value;
        }

        $raw = strtolower(trim((string) $value));

        return match ($raw) {
            'pending' => self::Pending,
            'confirmed', 'approve', 'approved', 'accept', 'accepted' => self::Confirmed,
            'processing' => self::Processing,
            'out_for_delivery' => self::OutForDelivery,
            'delivered' => self::Delivered,
            'completed', 'complete', 'done', 'fulfilled' => self::Completed,
            'cancelled', 'canceled', 'reject', 'rejected', 'decline', 'declined' => self::Cancelled,
            default => null,
        };
    }
}
