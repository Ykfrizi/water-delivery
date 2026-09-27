<?php

namespace App\Services\Paystack;

/**
 * Paystack expects amounts in the smallest currency unit (e.g. kobo for NGN).
 */
final class PaystackMoney
{
    /**
     * @return int Amount in minor units for Paystack initialize/verify comparison.
     */
    public static function toMinorUnits(float $majorAmount, string $currency): int
    {
        $currency = strtoupper($currency);

        return match ($currency) {
            'NGN', 'GHS', 'ZAR', 'KES', 'USD', 'EUR', 'GBP' => (int) round($majorAmount * 100),
            default => (int) round($majorAmount * 100),
        };
    }

    /**
     * Convert Paystack amount (minor units) back to major units for display / DB totals.
     */
    public static function toMajorUnits(int $minorUnits, string $currency): float
    {
        return round($minorUnits / 100, 2);
    }
}
