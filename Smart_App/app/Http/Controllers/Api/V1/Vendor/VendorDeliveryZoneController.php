<?php

namespace App\Http\Controllers\Api\V1\Vendor;

use App\Http\Controllers\Controller;
use App\Http\Resources\DeliveryZoneResource;
use App\Models\DeliveryZone;
use App\Models\VendorProfile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class VendorDeliveryZoneController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $profile = $this->resolveProfile($request);

        return DeliveryZoneResource::collection(
            $profile->deliveryZones()->orderBy('name')->get()
        );
    }

    public function store(Request $request): JsonResponse
    {
        $profile = $this->resolveProfile($request);

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'radius_km' => ['required', 'numeric', 'min:0.1', 'max:5000'],
            'note' => ['nullable', 'string', 'max:1000'],
        ]);

        $zone = $profile->deliveryZones()->create($validated);

        return (new DeliveryZoneResource($zone))
            ->response()
            ->setStatusCode(201);
    }

    public function show(Request $request, DeliveryZone $deliveryZone): DeliveryZoneResource
    {
        $this->authorizeZone($request, $deliveryZone);

        return new DeliveryZoneResource($deliveryZone);
    }

    public function update(Request $request, DeliveryZone $deliveryZone): DeliveryZoneResource
    {
        $this->authorizeZone($request, $deliveryZone);

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'latitude' => ['sometimes', 'numeric', 'between:-90,90'],
            'longitude' => ['sometimes', 'numeric', 'between:-180,180'],
            'radius_km' => ['sometimes', 'numeric', 'min:0.1', 'max:5000'],
            'note' => ['nullable', 'string', 'max:1000'],
        ]);

        $deliveryZone->update($validated);

        return new DeliveryZoneResource($deliveryZone->fresh());
    }

    public function destroy(Request $request, DeliveryZone $deliveryZone): JsonResponse
    {
        $this->authorizeZone($request, $deliveryZone);
        $deliveryZone->delete();

        return response()->json(['message' => 'Delivery zone deleted']);
    }

    private function authorizeZone(Request $request, DeliveryZone $deliveryZone): void
    {
        $profileId = $this->resolveProfile($request)->id;
        if ((int) $deliveryZone->vendor_profile_id !== $profileId) {
            abort(404);
        }
    }

    private function resolveProfile(Request $request): VendorProfile
    {
        $profile = $request->user()->vendorProfile;

        if ($profile === null) {
            abort(403, 'Vendor profile is required. Register with your Ghana Card number.');
        }

        return $profile;
    }
}
