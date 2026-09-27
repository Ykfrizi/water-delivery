<?php

namespace App\Notifications;

use App\Models\Order;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class OrderPaidNotification extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Order $order,
        public readonly string $audience = 'customer',
    ) {}

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        $this->order->loadMissing('vendorProfile:id,business_name,slug');

        $isVendor = $this->audience === 'vendor';

        return [
            'category' => 'order_paid',
            'title' => $isVendor ? 'Order payment received' : 'Payment successful',
            'body' => $isVendor
                ? 'Payment confirmed for order '.$this->order->order_number.'.'
                : 'Your payment for order '.$this->order->order_number.' was successful.',
            'order_number' => $this->order->order_number,
            'order_status' => $this->order->status->value,
            'payment_status' => 'paid',
            'total' => (float) $this->order->total,
            'currency' => $this->order->currency,
            'vendor_slug' => $this->order->vendorProfile?->slug,
            'business_name' => $this->order->vendorProfile?->business_name,
        ];
    }
}
