<?php

namespace App\Notifications;

use App\Models\VendorWithdrawal;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class VendorWithdrawalUpdatedNotification extends Notification
{
    use Queueable;

    public function __construct(
        public readonly VendorWithdrawal $withdrawal,
        public readonly string $event,
    ) {}

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        $amount = number_format((float) $this->withdrawal->amount, 2).' '.$this->withdrawal->currency;
        $business = $this->withdrawal->vendorProfile?->business_name ?? 'your shop';

        [$title, $body] = match ($this->event) {
            'requested' => [
                'Withdrawal requested',
                $business.' requested '.$amount.' to '.$this->withdrawal->destinationLabel().'.',
            ],
            'paid' => [
                'Withdrawal paid',
                $amount.' has been sent to '.$this->withdrawal->destinationLabel().'.',
            ],
            'rejected' => [
                'Withdrawal not paid',
                $amount.' was not paid. '.($this->withdrawal->admin_notes ?: 'Contact admin for details.'),
            ],
            default => ['Withdrawal update', $amount],
        };

        return [
            'category' => 'vendor_withdrawal',
            'event' => $this->event,
            'title' => $title,
            'body' => $body,
            'withdrawal_id' => $this->withdrawal->id,
            'amount' => (float) $this->withdrawal->amount,
            'currency' => $this->withdrawal->currency,
            'status' => $this->withdrawal->status->value,
            'destination' => $this->withdrawal->destinationLabel(),
        ];
    }
}
