<?php

namespace App\Services;

use App\Enums\OrderPaymentStatus;
use App\Enums\OrderStatus;
use App\Enums\WithdrawalStatus;
use App\Models\Order;
use App\Models\VendorProfile;
use App\Models\VendorWithdrawal;

final class VendorWalletService
{
    /**
     * Live earnings from Paystack-paid, non-cancelled orders minus withdrawals.
     *
     * @return array{
     *     currency: string,
     *     earned: float,
     *     pending_withdrawals: float,
     *     paid_withdrawals: float,
     *     available: float,
     *     paid_orders_count: int
     * }
     */
    public function snapshot(VendorProfile $profile): array
    {
        $paidQuery = Order::query()
            ->where('vendor_profile_id', $profile->id)
            ->where('payment_status', OrderPaymentStatus::Paid)
            ->where('status', '!=', OrderStatus::Cancelled);

        $earned = round((float) (clone $paidQuery)->sum('total'), 2);
        $paidOrdersCount = (clone $paidQuery)->count();

        $pending = round((float) VendorWithdrawal::query()
            ->where('vendor_profile_id', $profile->id)
            ->where('status', WithdrawalStatus::Pending)
            ->sum('amount'), 2);

        $paidOut = round((float) VendorWithdrawal::query()
            ->where('vendor_profile_id', $profile->id)
            ->where('status', WithdrawalStatus::Paid)
            ->sum('amount'), 2);

        $available = round(max(0, $earned - $pending - $paidOut), 2);

        return [
            'currency' => 'GHS',
            'earned' => $earned,
            'pending_withdrawals' => $pending,
            'paid_withdrawals' => $paidOut,
            'available' => $available,
            'paid_orders_count' => $paidOrdersCount,
        ];
    }
}
