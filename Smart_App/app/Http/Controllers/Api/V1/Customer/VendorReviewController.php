<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\ReviewResource;
use App\Models\Order;
use App\Models\Review;
use App\Models\VendorProfile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class VendorReviewController extends Controller
{
    public function store(Request $request, VendorProfile $vendor): JsonResponse
    {
        $this->ensureReviewableVendor($request, $vendor);

        $validated = $request->validate([
            'rating' => ['required', 'integer', 'min:1', 'max:5'],
            'comment' => ['nullable', 'string', 'max:2000'],
        ]);

        $review = Review::query()->updateOrCreate(
            [
                'customer_id' => $request->user()->id,
                'vendor_profile_id' => $vendor->id,
            ],
            [
                'rating' => $validated['rating'],
                'comment' => $validated['comment'] ?? null,
            ]
        );

        $review->load('customer:id,name');

        return (new ReviewResource($review))
            ->response()
            ->setStatusCode($review->wasRecentlyCreated ? 201 : 200);
    }

    private function ensureReviewableVendor(Request $request, VendorProfile $vendor): void
    {
        if (! $vendor->isPubliclyListed()) {
            abort(404);
        }

        $delivered = Order::query()
            ->where('customer_id', $request->user()->id)
            ->where('vendor_profile_id', $vendor->id)
            ->whereIn('status', [OrderStatus::Delivered, OrderStatus::Completed])
            ->exists();

        if (! $delivered) {
            throw ValidationException::withMessages([
                'rating' => [
                    'You can review this store after the vendor has marked your order as delivered.',
                ],
            ]);
        }
    }
}
