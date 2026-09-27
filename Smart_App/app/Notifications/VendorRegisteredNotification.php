<?php

namespace App\Notifications;

use App\Models\VendorProfile;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class VendorRegisteredNotification extends Notification
{
    use Queueable;

    public function __construct(
        public readonly VendorProfile $vendor,
    ) {}

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        $this->vendor->loadMissing('user:id,name,email');

        return [
            'category' => 'vendor_registered',
            'title' => 'New vendor pending approval',
            'body' => ($this->vendor->business_name ?? 'A vendor').' registered and awaits approval.',
            'vendor_id' => $this->vendor->id,
            'business_name' => $this->vendor->business_name,
            'slug' => $this->vendor->slug,
            'ghana_card_number' => $this->vendor->ghana_card_number,
            'user_email' => $this->vendor->user?->email,
        ];
    }
}
