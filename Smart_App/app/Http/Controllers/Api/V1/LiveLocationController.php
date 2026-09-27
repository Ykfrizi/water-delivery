<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class LiveLocationController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $user = $request->user();
        $user->forceFill([
            'last_latitude' => $validated['latitude'],
            'last_longitude' => $validated['longitude'],
            'last_located_at' => now(),
        ])->save();

        $profile = $user->vendorProfile;
        if ($profile !== null) {
            $profile->forceFill([
                'latitude' => $validated['latitude'],
                'longitude' => $validated['longitude'],
            ])->save();
        }

        return response()->json([
            'data' => [
                'latitude' => (float) $validated['latitude'],
                'longitude' => (float) $validated['longitude'],
                'updated_at' => $user->last_located_at?->toIso8601String(),
            ],
        ]);
    }
}
