<?php

namespace App\Notifications;

use App\Enums\VendorApprovalStatus;
use App\Models\VendorProfile;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class VendorApprovalUpdatedNotification extends Notification
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
        $status = $this->vendor->approval_status instanceof VendorApprovalStatus
            ? $this->vendor->approval_status
            : VendorApprovalStatus::from((string) $this->vendor->approval_status);

        $approved = $status === VendorApprovalStatus::Approved;

        return [
            'category' => 'vendor_approval',
            'title' => $approved ? 'Vendor account approved' : 'Vendor account rejected',
            'body' => $approved
                ? 'Your shop "'.$this->vendor->business_name.'" has been approved and can go live.'
                : 'Your shop "'.$this->vendor->business_name.'" was rejected.'
                    .($this->vendor->approval_notes ? ' Note: '.$this->vendor->approval_notes : ''),
            'approval_status' => $status->value,
            'business_name' => $this->vendor->business_name,
            'slug' => $this->vendor->slug,
            'approval_notes' => $this->vendor->approval_notes,
            'is_active' => (bool) $this->vendor->is_active,
        ];
    }
}
