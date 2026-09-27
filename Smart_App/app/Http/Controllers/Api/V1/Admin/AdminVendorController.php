<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Enums\VendorApprovalStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\AdminVendorResource;
use App\Models\VendorProfile;
use App\Notifications\VendorApprovalUpdatedNotification;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AdminVendorController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $perPage = min(max((int) $request->input('per_page', 20), 1), 100);

        $query = VendorProfile::query()
            ->with(['user:id,name,email,last_latitude,last_longitude,last_located_at', 'reviewedBy:id,name,email'])
            ->orderByDesc('created_at');

        if ($request->filled('approval_status')) {
            $query->where('approval_status', $request->string('approval_status'));
        }

        if ($request->filled('q')) {
            $term = $request->string('q');
            $query->where(function ($q) use ($term) {
                $q->where('business_name', 'like', '%'.$term.'%')
                    ->orWhere('slug', 'like', '%'.$term.'%')
                    ->orWhere('ghana_card_number', 'like', '%'.$term.'%')
                    ->orWhereHas('user', fn ($u) => $u->where('email', 'like', '%'.$term.'%'));
            });
        }

        return AdminVendorResource::collection($query->paginate($perPage));
    }

    public function show(VendorProfile $vendor): AdminVendorResource
    {
        $vendor->load(['user:id,name,email,last_latitude,last_longitude,last_located_at', 'reviewedBy:id,name,email']);

        return new AdminVendorResource($vendor);
    }

    public function update(Request $request, VendorProfile $vendor): AdminVendorResource
    {
        $validated = $request->validate([
            'approval_status' => ['required', Rule::enum(VendorApprovalStatus::class)],
            'approval_notes' => ['nullable', 'string', 'max:2000'],
        ]);

        $status = $validated['approval_status'] instanceof VendorApprovalStatus
            ? $validated['approval_status']
            : VendorApprovalStatus::from($validated['approval_status']);

        if ($status === VendorApprovalStatus::Pending && $vendor->approval_status !== VendorApprovalStatus::Pending) {
            throw ValidationException::withMessages([
                'approval_status' => ['Vendors cannot be moved back to pending.'],
            ]);
        }

        $vendor->approval_status = $status;
        $vendor->approval_notes = $validated['approval_notes'] ?? null;
        $vendor->reviewed_at = now();
        $vendor->reviewed_by = $request->user()->id;

        if ($status === VendorApprovalStatus::Approved) {
            $vendor->is_active = true;
        }

        if ($status === VendorApprovalStatus::Rejected) {
            $vendor->is_active = false;
        }

        $vendor->save();

        $vendor->load(['user:id,name,email', 'reviewedBy:id,name,email']);

        if (
            $vendor->user !== null
            && in_array($status, [VendorApprovalStatus::Approved, VendorApprovalStatus::Rejected], true)
        ) {
            $vendor->user->notify(new VendorApprovalUpdatedNotification($vendor));
        }

        return new AdminVendorResource($vendor);
    }
}
