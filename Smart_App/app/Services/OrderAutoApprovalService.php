<?php

namespace App\Services;

use App\Enums\OrderPaymentStatus;
use App\Enums\OrderStatus;
use App\Models\Order;
use App\Notifications\OrderStatusChangedNotification;

final class OrderAutoApprovalService
{
    /**
     * Auto-confirm a paid pending order when the vendor's schedule is active.
     */
    public static function maybeAutoConfirm(Order $order): bool
    {
        $order->loadMissing(['vendorProfile', 'customer']);

        if ($order->payment_status !== OrderPaymentStatus::Paid) {
            return false;
        }

        $vendor = $order->vendorProfile;
        if ($vendor === null || ! $vendor->isAutoApprovingOrders()) {
            return false;
        }

        if ($order->status !== OrderStatus::Pending) {
            return false;
        }

        $previous = $order->status;
        $order->status = OrderStatus::Confirmed;
        $order->save();

        if ($order->customer !== null) {
            $order->customer->notify(
                new OrderStatusChangedNotification($order, $previous, 'auto')
            );
        }

        return true;
    }
}
