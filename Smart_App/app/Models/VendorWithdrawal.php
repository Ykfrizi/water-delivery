<?php

namespace App\Models;

use App\Enums\PayoutMethod;
use App\Enums\WithdrawalStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VendorWithdrawal extends Model
{
    protected $fillable = [
        'vendor_profile_id',
        'amount',
        'currency',
        'method',
        'status',
        'bank_name',
        'account_name',
        'account_number',
        'momo_network',
        'momo_number',
        'momo_name',
        'admin_notes',
        'processed_by',
        'processed_at',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'method' => PayoutMethod::class,
            'status' => WithdrawalStatus::class,
            'processed_at' => 'datetime',
        ];
    }

    public function vendorProfile(): BelongsTo
    {
        return $this->belongsTo(VendorProfile::class);
    }

    public function processedByAdmin(): BelongsTo
    {
        return $this->belongsTo(User::class, 'processed_by');
    }

    public function destinationLabel(): string
    {
        if ($this->method === PayoutMethod::Bank) {
            return trim(($this->bank_name ?? 'Bank').' · '.($this->account_name ?? '').' · '.($this->account_number ?? ''));
        }

        return trim(($this->momo_network ?? 'Mobile money').' · '.($this->momo_name ?? '').' · '.($this->momo_number ?? ''));
    }
}
