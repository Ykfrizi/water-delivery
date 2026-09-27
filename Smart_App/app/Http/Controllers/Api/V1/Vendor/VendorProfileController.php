<?php

namespace App\Http\Controllers\Api\V1\Vendor;

use App\Enums\VendorApprovalStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\ReviewResource;
use App\Http\Resources\VendorProfileResource;
use App\Models\Review;
use App\Models\VendorProfile;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\ValidationException;

class VendorProfileController extends Controller
{
    public function show(Request $request): VendorProfileResource
    {
        $profile = $this->resolveProfile($request)->load('deliveryZones');

        return new VendorProfileResource($profile);
    }

    public function reviews(Request $request): AnonymousResourceCollection
    {
        $profile = $this->resolveProfile($request);
        $perPage = min(max((int) $request->input('per_page', 30), 1), 50);

        $reviews = Review::query()
            ->where('vendor_profile_id', $profile->id)
            ->with('customer:id,name')
            ->orderByDesc('created_at')
            ->paginate($perPage);

        return ReviewResource::collection($reviews);
    }

    public function update(Request $request): VendorProfileResource
    {
        $profile = $this->resolveProfile($request);

        $validated = $request->validate([
            'business_name' => ['sometimes', 'string', 'max:255'],
            'description' => ['nullable', 'string'],
            'logo_url' => ['nullable', 'string', 'max:2048'],
            'phone' => ['nullable', 'string', 'max:50'],
            'city' => ['nullable', 'string', 'max:120'],
            'region' => ['nullable', 'string', 'max:120'],
            'country' => ['nullable', 'string', 'max:120'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'categories' => ['nullable', 'array'],
            'categories.*' => ['string', 'max:64'],
            'is_active' => ['sometimes', 'boolean'],
            'auto_approve_enabled' => ['sometimes', 'boolean'],
            'auto_approve_starts_at' => ['nullable', 'date'],
            'auto_approve_ends_at' => ['nullable', 'date', 'after_or_equal:auto_approve_starts_at'],
            'auto_approve_daily_start' => ['nullable', 'date_format:H:i'],
            'auto_approve_daily_end' => ['nullable', 'date_format:H:i'],
            'auto_approve_timezone' => ['nullable', 'timezone'],
        ]);

        if (array_key_exists('business_name', $validated)) {
            $profile->business_name = $validated['business_name'];
            $profile->slug = VendorProfile::uniqueSlugFrom($validated['business_name'], $profile->id);
        }

        if (array_key_exists('is_active', $validated) && $validated['is_active'] && $profile->approval_status !== VendorApprovalStatus::Approved) {
            throw ValidationException::withMessages([
                'is_active' => ['Your shop can only go live after admin approval.'],
            ]);
        }

        $hasDailyStart = array_key_exists('auto_approve_daily_start', $validated);
        $hasDailyEnd = array_key_exists('auto_approve_daily_end', $validated);
        $dailyStart = $hasDailyStart ? $validated['auto_approve_daily_start'] : $this->formatStoredTime($profile->auto_approve_daily_start);
        $dailyEnd = $hasDailyEnd ? $validated['auto_approve_daily_end'] : $this->formatStoredTime($profile->auto_approve_daily_end);

        if (($dailyStart === null) xor ($dailyEnd === null)) {
            throw ValidationException::withMessages([
                'auto_approve_daily_start' => ['Set both daily_start and daily_end, or clear both.'],
                'auto_approve_daily_end' => ['Set both daily_start and daily_end, or clear both.'],
            ]);
        }

        if (array_key_exists('auto_approve_daily_start', $validated)) {
            $validated['auto_approve_daily_start'] = $validated['auto_approve_daily_start'] !== null
                ? $validated['auto_approve_daily_start'].':00'
                : null;
        }

        if (array_key_exists('auto_approve_daily_end', $validated)) {
            $validated['auto_approve_daily_end'] = $validated['auto_approve_daily_end'] !== null
                ? $validated['auto_approve_daily_end'].':00'
                : null;
        }

        if (
            array_key_exists('auto_approve_enabled', $validated)
            && $validated['auto_approve_enabled']
            && $profile->approval_status !== VendorApprovalStatus::Approved
        ) {
            throw ValidationException::withMessages([
                'auto_approve_enabled' => ['Auto-approve is available only after admin approval.'],
            ]);
        }

        $profile->fill(collect($validated)->except('business_name')->all());
        $profile->save();

        $profile->load('deliveryZones');

        return new VendorProfileResource($profile);
    }

    /**
     * Quickly turn off automatic order approval.
     */
    public function stopAutoApprove(Request $request): VendorProfileResource
    {
        $profile = $this->resolveProfile($request);
        $profile->auto_approve_enabled = false;
        $profile->save();

        $profile->load('deliveryZones');

        return new VendorProfileResource($profile);
    }

    private function resolveProfile(Request $request): VendorProfile
    {
        $profile = $request->user()->vendorProfile;

        if ($profile === null) {
            abort(403, 'Vendor profile is required. Register with your Ghana Card number.');
        }

        return $profile;
    }

    private function formatStoredTime(mixed $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        if ($value instanceof \DateTimeInterface) {
            return $value->format('H:i');
        }

        $raw = (string) $value;

        return preg_match('/^(\d{2}:\d{2})/', $raw, $m) ? $m[1] : null;
    }
}
