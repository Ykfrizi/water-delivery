<?php

namespace App\Http\Middleware;

use App\Enums\VendorApprovalStatus;
use App\Models\VendorProfile;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureVendorApproved
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        $profile = $user?->vendorProfile;

        if (! $profile instanceof VendorProfile) {
            abort(Response::HTTP_FORBIDDEN, 'Vendor profile is required.');
        }

        if ($profile->approval_status !== VendorApprovalStatus::Approved) {
            return response()->json([
                'message' => 'Your vendor account is awaiting admin approval. You cannot access the dashboard yet.',
                'approval_status' => $profile->approval_status->value,
                'approval_notes' => $profile->approval_notes,
            ], Response::HTTP_FORBIDDEN);
        }

        return $next($request);
    }
}
