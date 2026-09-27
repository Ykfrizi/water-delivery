<?php

namespace App\Models;

use App\Enums\OrderPaymentStatus;
use App\Enums\OrderStatus;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Order extends Model
{
    protected $fillable = [
        'order_number',
        'customer_id',
        'vendor_profile_id',
        'status',
        'subtotal',
        'delivery_fee',
        'total',
        'currency',
        'notes',
        'shipping_address',
        'courier_latitude',
        'courier_longitude',
        'courier_located_at',
        'placed_at',
        'payment_status',
        'payment_method',
        'paid_at',
        'voucher_id',
        'voucher_code',
        'discount_amount',
    ];

    protected function casts(): array
    {
        return [
            'status' => OrderStatus::class,
            'payment_status' => OrderPaymentStatus::class,
            'subtotal' => 'decimal:2',
            'delivery_fee' => 'decimal:2',
            'discount_amount' => 'decimal:2',
            'total' => 'decimal:2',
            'shipping_address' => 'array',
            'courier_latitude' => 'float',
            'courier_longitude' => 'float',
            'courier_located_at' => 'datetime',
            'placed_at' => 'datetime',
            'paid_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Order $order): void {
            if ($order->order_number === null || $order->order_number === '') {
                $order->order_number = self::generateUniqueOrderNumber();
            }

            $order->placed_at ??= now();
        });
    }

    public static function generateUniqueOrderNumber(): string
    {
        do {
            $number = 'SM-'.now()->format('Ymd').'-'.strtoupper(substr(bin2hex(random_bytes(4)), 0, 6));
        } while (self::query()->where('order_number', $number)->exists());

        return $number;
    }

    public function getRouteKeyName(): string
    {
        return 'order_number';
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    public function vendorProfile(): BelongsTo
    {
        return $this->belongsTo(VendorProfile::class);
    }

    /** Vendors see Paystack-paid orders and pay-on-delivery orders — not abandoned unpaid Paystack checkouts. */
    public function scopePaidForVendor($query)
    {
        return $query->where(function ($inner) {
            $inner->where('payment_status', OrderPaymentStatus::Paid)
                ->orWhere('payment_method', 'cash_on_delivery');
        });
    }

    public function isPaid(): bool
    {
        return $this->payment_status === OrderPaymentStatus::Paid;
    }

    public function isPayOnDelivery(): bool
    {
        return $this->payment_method === 'cash_on_delivery';
    }

    public function isVisibleToVendor(): bool
    {
        return $this->isPaid() || $this->isPayOnDelivery();
    }

    /**
     * Best-known customer delivery pin: live GPS first, then checkout address.
     *
     * @return array{0: float, 1: float}|null
     */
    public function deliveryCoordinates(): ?array
    {
        $customer = $this->relationLoaded('customer') ? $this->customer : $this->customer()->first();
        if ($customer?->last_latitude !== null && $customer?->last_longitude !== null) {
            return [(float) $customer->last_latitude, (float) $customer->last_longitude];
        }

        $shipping = $this->shipping_address;
        if (! is_array($shipping)) {
            return null;
        }

        $lat = $shipping['latitude'] ?? $shipping['lat'] ?? null;
        $lng = $shipping['longitude'] ?? $shipping['lng'] ?? $shipping['lon'] ?? null;
        if (! is_numeric($lat) || ! is_numeric($lng)) {
            return null;
        }

        return [(float) $lat, (float) $lng];
    }

    public function orderItems(): HasMany
    {
        return $this->hasMany(OrderItem::class);
    }

    public function deliveryShareLinks(): HasMany
    {
        return $this->hasMany(DeliveryShareLink::class);
    }
}
