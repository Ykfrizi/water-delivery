<?php

namespace App\Models;

use App\Enums\VendorApprovalStatus;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

class VendorProfile extends Model
{
    protected $fillable = [
        'user_id',
        'slug',
        'business_name',
        'description',
        'logo_url',
        'phone',
        'ghana_card_number',
        'city',
        'region',
        'country',
        'latitude',
        'longitude',
        'categories',
        'is_active',
        'auto_approve_enabled',
        'auto_approve_starts_at',
        'auto_approve_ends_at',
        'auto_approve_daily_start',
        'auto_approve_daily_end',
        'auto_approve_timezone',
        'approval_status',
        'approval_notes',
        'reviewed_at',
        'reviewed_by',
        'average_rating',
        'ratings_count',
    ];

    protected function casts(): array
    {
        return [
            'categories' => 'array',
            'is_active' => 'boolean',
            'auto_approve_enabled' => 'boolean',
            'auto_approve_starts_at' => 'datetime',
            'auto_approve_ends_at' => 'datetime',
            'approval_status' => VendorApprovalStatus::class,
            'reviewed_at' => 'datetime',
            'average_rating' => 'decimal:2',
            'latitude' => 'float',
            'longitude' => 'float',
        ];
    }

    public function getRouteKeyName(): string
    {
        return 'slug';
    }

    /**
     * Resolve by numeric id or slug (admin/marketplace routes).
     */
    public function resolveRouteBinding($value, $field = null)
    {
        $field ??= $this->getRouteKeyName();

        if ($field === 'id' || (is_numeric($value) && ctype_digit((string) $value))) {
            return static::query()->where('id', $value)->firstOrFail();
        }

        return static::query()->where($field, $value)->firstOrFail();
    }

    public static function uniqueSlugFrom(string $businessName, ?int $exceptProfileId = null): string
    {
        $base = Str::slug($businessName);
        if ($base === '') {
            $base = 'vendor';
        }

        $slug = $base;
        $i = 1;
        while (static::query()
            ->where('slug', $slug)
            ->when($exceptProfileId !== null, fn ($q) => $q->where('id', '!=', $exceptProfileId))
            ->exists()) {
            $slug = $base.'-'.$i++;
        }

        return $slug;
    }

    public static function createForUser(User $user, ?string $businessName = null, ?string $ghanaCardNumber = null): self
    {
        $name = $businessName ?? $user->name;

        return static::create([
            'user_id' => $user->id,
            'slug' => static::uniqueSlugFrom($name),
            'business_name' => $name,
            'ghana_card_number' => $ghanaCardNumber !== null
                ? strtoupper(trim($ghanaCardNumber))
                : null,
            'approval_status' => VendorApprovalStatus::Pending,
            'is_active' => false,
        ]);
    }

    public function isApproved(): bool
    {
        return $this->approval_status === VendorApprovalStatus::Approved;
    }

    public function isPubliclyListed(): bool
    {
        return $this->approval_status === VendorApprovalStatus::Approved && $this->is_active;
    }

    /**
     * Whether new paid orders should be auto-confirmed right now.
     * Uses date range (A) and/or daily time window (B), plus the enabled switch.
     */
    public function isAutoApprovingOrders(?\DateTimeInterface $at = null): bool
    {
        if (! $this->auto_approve_enabled) {
            return false;
        }

        $timezone = $this->auto_approve_timezone ?: 'Africa/Accra';
        $moment = \Illuminate\Support\Carbon::parse($at ?? now())->timezone($timezone);

        if ($this->auto_approve_starts_at !== null) {
            $starts = $this->auto_approve_starts_at->copy()->timezone($timezone);
            if ($moment->lt($starts)) {
                return false;
            }
        }

        if ($this->auto_approve_ends_at !== null) {
            $ends = $this->auto_approve_ends_at->copy()->timezone($timezone);
            if ($moment->gt($ends)) {
                return false;
            }
        }

        $dailyStart = $this->normalizeTimeValue($this->auto_approve_daily_start);
        $dailyEnd = $this->normalizeTimeValue($this->auto_approve_daily_end);

        if ($dailyStart !== null && $dailyEnd !== null) {
            $current = $moment->format('H:i:s');

            if ($dailyStart <= $dailyEnd) {
                // Same-day window, e.g. 09:00–17:00
                if ($current < $dailyStart || $current > $dailyEnd) {
                    return false;
                }
            } else {
                // Overnight window, e.g. 22:00–06:00
                if ($current < $dailyStart && $current > $dailyEnd) {
                    return false;
                }
            }
        } elseif ($dailyStart !== null || $dailyEnd !== null) {
            // Incomplete daily window is ignored until both times are set.
            return false;
        }

        return true;
    }

    private function normalizeTimeValue(mixed $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        if ($value instanceof \DateTimeInterface) {
            return $value->format('H:i:s');
        }

        $raw = (string) $value;
        if (preg_match('/^\d{2}:\d{2}$/', $raw)) {
            return $raw.':00';
        }

        if (preg_match('/^\d{2}:\d{2}:\d{2}$/', $raw)) {
            return $raw;
        }

        try {
            return \Illuminate\Support\Carbon::parse($raw)->format('H:i:s');
        } catch (\Throwable) {
            return null;
        }
    }

    public function scopePubliclyListed(Builder $query): Builder
    {
        return $query
            ->where('approval_status', VendorApprovalStatus::Approved)
            ->where('is_active', true);
    }

    public function reviewedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function deliveryZones(): HasMany
    {
        return $this->hasMany(DeliveryZone::class);
    }

    public function products(): HasMany
    {
        return $this->hasMany(Product::class);
    }

    public function reviews(): HasMany
    {
        return $this->hasMany(Review::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class);
    }

    public function withdrawals(): HasMany
    {
        return $this->hasMany(VendorWithdrawal::class);
    }
}
