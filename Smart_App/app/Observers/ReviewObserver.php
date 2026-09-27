<?php

namespace App\Observers;

use App\Models\Review;
use App\Models\VendorProfile;

class ReviewObserver
{
    public function saved(Review $review): void
    {
        $this->syncVendorRating($review->vendor_profile_id);
    }

    public function deleted(Review $review): void
    {
        $this->syncVendorRating($review->vendor_profile_id);
    }

    private function syncVendorRating(int $vendorProfileId): void
    {
        $vendorProfile = VendorProfile::query()->find($vendorProfileId);
        if ($vendorProfile === null) {
            return;
        }

        $stats = Review::query()
            ->where('vendor_profile_id', $vendorProfileId)
            ->selectRaw('AVG(rating) as avg_rating, COUNT(*) as cnt')
            ->first();

        $vendorProfile->update([
            'average_rating' => round((float) ($stats->avg_rating ?? 0), 2),
            'ratings_count' => (int) ($stats->cnt ?? 0),
        ]);
    }
}
