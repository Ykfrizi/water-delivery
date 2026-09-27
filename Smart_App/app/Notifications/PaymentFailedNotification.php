<?php

namespace App\Notifications;

use App\Models\Payment;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class PaymentFailedNotification extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Payment $payment,
    ) {}

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        $orderNumbers = $this->payment->metadata['order_numbers'] ?? [];

        return [
            'category' => 'payment_failed',
            'title' => 'Payment failed',
            'body' => 'Payment '.$this->payment->reference.' could not be completed.'
                .(is_array($orderNumbers) && $orderNumbers !== []
                    ? ' Orders: '.implode(', ', $orderNumbers).'.'
                    : ''),
            'reference' => $this->payment->reference,
            'order_numbers' => is_array($orderNumbers) ? $orderNumbers : [],
            'currency' => $this->payment->currency,
        ];
    }
}
