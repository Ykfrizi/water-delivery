<?php

namespace App\Services;

use App\Enums\OrderStatus;

final class OrderStatusTransition
{
    public static function customerMayMove(OrderStatus $from, OrderStatus $to): bool
    {
        if ($from === $to) {
            return true;
        }

        return $from === OrderStatus::Pending && $to === OrderStatus::Cancelled;
    }

    public static function vendorMayMove(OrderStatus $from, OrderStatus $to): bool
    {
        if ($from === $to) {
            return true;
        }

        return match ($from) {
            OrderStatus::Pending => in_array($to, [OrderStatus::Confirmed, OrderStatus::Cancelled], true),
            OrderStatus::Confirmed => in_array($to, [
                OrderStatus::Processing,
                OrderStatus::OutForDelivery,
                OrderStatus::Delivered,
                OrderStatus::Completed,
                OrderStatus::Cancelled,
            ], true),
            OrderStatus::Processing => in_array($to, [
                OrderStatus::OutForDelivery,
                OrderStatus::Delivered,
                OrderStatus::Completed,
                OrderStatus::Cancelled,
            ], true),
            OrderStatus::OutForDelivery => in_array($to, [
                OrderStatus::Delivered,
                OrderStatus::Completed,
                OrderStatus::Cancelled,
            ], true),
            default => false,
        };
    }

    /**
     * Statuses the vendor picker may show (excludes confirmed, preparing, shipped).
     *
     * @return list<string>
     */
    public static function vendorPickerStatuses(OrderStatus $from): array
    {
        $hidden = OrderStatus::hiddenFromVendorPicker();

        $candidates = [
            OrderStatus::Processing,
            OrderStatus::OutForDelivery,
            OrderStatus::Delivered,
            OrderStatus::Cancelled,
        ];

        $allowed = [];
        foreach ($candidates as $status) {
            if (in_array($status->value, $hidden, true)) {
                continue;
            }

            if (self::vendorMayMove($from, $status)) {
                $allowed[] = $status->value;
            }
        }

        return $allowed;
    }

    public static function adminMayMove(OrderStatus $from, OrderStatus $to): bool
    {
        if ($from === $to) {
            return true;
        }

        if (in_array($from, [OrderStatus::Completed, OrderStatus::Delivered, OrderStatus::Cancelled], true)) {
            return false;
        }

        return match ($to) {
            OrderStatus::Pending => false,
            OrderStatus::Confirmed,
            OrderStatus::Processing,
            OrderStatus::OutForDelivery,
            OrderStatus::Delivered,
            OrderStatus::Completed,
            OrderStatus::Cancelled => true,
        };
    }
}
