<?php

namespace App\Notifications;

use App\Enums\OrderStatus;
use App\Models\Order;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class OrderStatusChangedNotification extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Order $order,
        public readonly OrderStatus $previousStatus,
        public readonly string $changedBy,
    ) {}

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        $this->order->loadMissing('vendorProfile:id,business_name,slug');

        $status = $this->order->status->value;

        $title = match ($this->order->status) {
            OrderStatus::Confirmed => 'Order confirmed',
            OrderStatus::Processing => 'Order is being processed',
            OrderStatus::OutForDelivery => 'Order is out for delivery',
            OrderStatus::Delivered => 'Order delivered',
            OrderStatus::Completed => 'Order completed',
            OrderStatus::Cancelled => 'Order cancelled',
            default => 'Order updated',
        };

        $source = match ($this->changedBy) {
            'auto' => 'automatically',
            'vendor' => 'by the vendor',
            'admin' => 'by an admin',
            'customer' => 'by the customer',
            default => '',
        };

        $body = 'Order '.$this->order->order_number.' is now '.$status
            .' (was '.$this->previousStatus->value.')'
            .($source !== '' ? ' '.$source : '')
            .'.';

        return [
            'category' => 'order_status_changed',
            'title' => $title,
            'body' => $body,
            'order_number' => $this->order->order_number,
            'order_status' => $status,
            'previous_status' => $this->previousStatus->value,
            'changed_by' => $this->changedBy,
            'total' => (float) $this->order->total,
            'currency' => $this->order->currency,
            'vendor_slug' => $this->order->vendorProfile?->slug,
            'business_name' => $this->order->vendorProfile?->business_name,
        ];
    }
}
