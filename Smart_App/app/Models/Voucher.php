<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Validation\ValidationException;

class Voucher extends Model
{
    protected $fillable = [
        'code',
        'type',
        'value',
        'max_uses',
        'used_count',
        'is_active',
        'expires_at',
    ];

    protected function casts(): array
    {
        return [
            'value' => 'decimal:2',
            'max_uses' => 'integer',
            'used_count' => 'integer',
            'is_active' => 'boolean',
            'expires_at' => 'datetime',
        ];
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class);
    }

    public static function normalizeCode(string $code): string
    {
        return strtoupper(trim($code));
    }

    public function discountAmount(float $subtotal): float
    {
        $subtotal = max(0, round($subtotal, 2));
        if ($subtotal <= 0) {
            return 0;
        }

        $off = $this->type === 'percent'
            ? round($subtotal * ((float) $this->value) / 100, 2)
            : round((float) $this->value, 2);

        return max(0, min($off, $subtotal));
    }

    public function assertRedeemable(): void
    {
        if (! $this->is_active) {
            throw ValidationException::withMessages([
                'voucher_code' => ['This voucher is no longer active.'],
            ]);
        }

        if ($this->expires_at !== null && $this->expires_at->isPast()) {
            throw ValidationException::withMessages([
                'voucher_code' => ['This voucher has expired.'],
            ]);
        }

        if ($this->max_uses !== null && $this->used_count >= $this->max_uses) {
            throw ValidationException::withMessages([
                'voucher_code' => ['This voucher has already been used up.'],
            ]);
        }
    }
}
