<?php

namespace App\Notifications;

use App\Models\Order;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * Sent to the vendor when a customer successfully pays for an order.
 */
class CustomerPurchasedNotification extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Order $order,
    ) {}

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        $this->order->loadMissing([
            'customer:id,name,email',
            'vendorProfile:id,business_name,slug',
            'orderItems',
        ]);

        $customerName = $this->order->customer?->name ?? 'A customer';
        $itemCount = $this->order->orderItems->sum('quantity');
        $total = number_format((float) $this->order->total, 2);
        $currency = $this->order->currency;
        $payOnDelivery = $this->order->isPayOnDelivery();

        return [
            'category' => 'customer_purchased',
            'title' => $payOnDelivery
                ? 'Pay on delivery order'
                : 'New purchase from your shop',
            'body' => $payOnDelivery
                ? "{$customerName} ordered pay on delivery — {$this->order->order_number} ({$itemCount} item(s), {$total} {$currency}). Collect payment when you deliver."
                : "{$customerName} bought from you — order {$this->order->order_number} ({$itemCount} item(s), {$total} {$currency}). Paid.",
            'order_number' => $this->order->order_number,
            'order_status' => $this->order->status->value,
            'payment_status' => $payOnDelivery ? 'pay_on_delivery' : 'paid',
            'payment_method' => $this->order->payment_method,
            'pay_on_delivery' => $payOnDelivery,
            'total' => (float) $this->order->total,
            'currency' => $currency,
            'item_count' => (int) $itemCount,
            'customer' => [
                'id' => $this->order->customer?->id,
                'name' => $this->order->customer?->name,
                'email' => $this->order->customer?->email,
            ],
            'vendor_slug' => $this->order->vendorProfile?->slug,
            'business_name' => $this->order->vendorProfile?->business_name,
        ];
    }
}
