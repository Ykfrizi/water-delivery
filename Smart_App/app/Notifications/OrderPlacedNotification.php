<?php

namespace App\Notifications;

use App\Models\Order;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class OrderPlacedNotification extends Notification
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
        $this->order->loadMissing('vendorProfile:id,business_name,slug');

        return [
            'category' => 'order_placed',
            'title' => 'New order received',
            'body' => 'Order '.$this->order->order_number.' was placed for '
                .number_format((float) $this->order->total, 2).' '.$this->order->currency.'.',
            'order_number' => $this->order->order_number,
            'order_status' => $this->order->status->value,
            'payment_status' => $this->order->payment_status instanceof \BackedEnum
                ? $this->order->payment_status->value
                : (string) $this->order->payment_status,
            'total' => (float) $this->order->total,
            'currency' => $this->order->currency,
            'vendor_slug' => $this->order->vendorProfile?->slug,
        ];
    }
}
