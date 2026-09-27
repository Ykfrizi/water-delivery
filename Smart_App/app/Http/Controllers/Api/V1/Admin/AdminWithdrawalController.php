<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Enums\WithdrawalStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\VendorWithdrawalResource;
use App\Models\VendorWithdrawal;
use App\Notifications\VendorWithdrawalUpdatedNotification;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\ValidationException;

class AdminWithdrawalController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $perPage = min(max((int) $request->input('per_page', 30), 1), 100);

        $query = VendorWithdrawal::query()
            ->with('vendorProfile:id,slug,business_name')
            ->orderByDesc('created_at');

        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }

        return VendorWithdrawalResource::collection($query->paginate($perPage));
    }

    public function complete(Request $request, VendorWithdrawal $withdrawal): VendorWithdrawalResource
    {
        if ($withdrawal->status !== WithdrawalStatus::Pending) {
            throw ValidationException::withMessages([
                'status' => ['Only pending withdrawals can be marked as paid.'],
            ]);
        }

        $validated = $request->validate([
            'admin_notes' => ['nullable', 'string', 'max:2000'],
        ]);

        $withdrawal->forceFill([
            'status' => WithdrawalStatus::Paid,
            'admin_notes' => $validated['admin_notes'] ?? $withdrawal->admin_notes,
            'processed_by' => $request->user()->id,
            'processed_at' => now(),
        ])->save();

        $withdrawal->load('vendorProfile.user');
        $withdrawal->vendorProfile?->user?->notify(
            new VendorWithdrawalUpdatedNotification($withdrawal, 'paid')
        );

        return new VendorWithdrawalResource($withdrawal);
    }

    public function reject(Request $request, VendorWithdrawal $withdrawal): VendorWithdrawalResource
    {
        if ($withdrawal->status !== WithdrawalStatus::Pending) {
            throw ValidationException::withMessages([
                'status' => ['Only pending withdrawals can be rejected.'],
            ]);
        }

        $validated = $request->validate([
            'admin_notes' => ['nullable', 'string', 'max:2000'],
        ]);

        $withdrawal->forceFill([
            'status' => WithdrawalStatus::Rejected,
            'admin_notes' => $validated['admin_notes'] ?? $withdrawal->admin_notes,
            'processed_by' => $request->user()->id,
            'processed_at' => now(),
        ])->save();

        $withdrawal->load('vendorProfile.user');
        $withdrawal->vendorProfile?->user?->notify(
            new VendorWithdrawalUpdatedNotification($withdrawal, 'rejected')
        );

        return new VendorWithdrawalResource($withdrawal);
    }
}
