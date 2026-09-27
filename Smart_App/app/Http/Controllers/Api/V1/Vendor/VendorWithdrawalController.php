<?php

namespace App\Http\Controllers\Api\V1\Vendor;

use App\Enums\PayoutMethod;
use App\Enums\UserRole;
use App\Enums\WithdrawalStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\VendorWithdrawalResource;
use App\Models\User;
use App\Models\VendorProfile;
use App\Models\VendorWithdrawal;
use App\Notifications\VendorWithdrawalUpdatedNotification;
use App\Services\VendorWalletService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class VendorWithdrawalController extends Controller
{
    public function __construct(
        private readonly VendorWalletService $wallet,
    ) {}

    public function wallet(Request $request): JsonResponse
    {
        $profile = $this->vendorProfileOrAbort($request);

        return response()->json([
            'data' => $this->wallet->snapshot($profile),
        ]);
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        $profile = $this->vendorProfileOrAbort($request);

        $rows = VendorWithdrawal::query()
            ->where('vendor_profile_id', $profile->id)
            ->orderByDesc('created_at')
            ->paginate(min(max((int) $request->input('per_page', 20), 1), 50));

        return VendorWithdrawalResource::collection($rows);
    }

    public function store(Request $request): VendorWithdrawalResource
    {
        $profile = $this->vendorProfileOrAbort($request);

        $validated = $request->validate([
            'amount' => ['required', 'numeric', 'min:1'],
            'method' => ['required', Rule::enum(PayoutMethod::class)],
            'bank_name' => ['nullable', 'string', 'max:120'],
            'account_name' => ['nullable', 'string', 'max:120'],
            'account_number' => ['nullable', 'string', 'max:32'],
            'momo_network' => ['nullable', 'string', 'max:40'],
            'momo_number' => ['nullable', 'string', 'max:20'],
            'momo_name' => ['nullable', 'string', 'max:120'],
        ]);

        $method = $validated['method'] instanceof PayoutMethod
            ? $validated['method']
            : PayoutMethod::from((string) $validated['method']);

        if ($method === PayoutMethod::Bank) {
            $request->validate([
                'bank_name' => ['required', 'string', 'max:120'],
                'account_name' => ['required', 'string', 'max:120'],
                'account_number' => ['required', 'string', 'max:32'],
            ]);
        } else {
            $request->validate([
                'momo_network' => ['required', 'string', 'max:40'],
                'momo_number' => ['required', 'string', 'max:20'],
                'momo_name' => ['required', 'string', 'max:120'],
            ]);
        }

        $amount = round((float) $validated['amount'], 2);

        $withdrawal = DB::transaction(function () use ($profile, $validated, $method, $amount) {
            VendorProfile::query()->whereKey($profile->id)->lockForUpdate()->first();
            VendorWithdrawal::query()
                ->where('vendor_profile_id', $profile->id)
                ->lockForUpdate()
                ->get();

            $snapshot = $this->wallet->snapshot($profile->fresh());
            if ($amount - $snapshot['available'] > 0.009) {
                throw ValidationException::withMessages([
                    'amount' => [
                        'You requested '.number_format($amount, 2).' '.$snapshot['currency']
                        .' but your available balance is '.number_format($snapshot['available'], 2).' '.$snapshot['currency']
                        .'. You cannot withdraw more than Paystack-paid orders in your account.',
                    ],
                ]);
            }

            return VendorWithdrawal::query()->create([
                'vendor_profile_id' => $profile->id,
                'amount' => $amount,
                'currency' => $snapshot['currency'],
                'method' => $method,
                'status' => WithdrawalStatus::Pending,
                'bank_name' => $validated['bank_name'] ?? null,
                'account_name' => $validated['account_name'] ?? null,
                'account_number' => $validated['account_number'] ?? null,
                'momo_network' => $validated['momo_network'] ?? null,
                'momo_number' => $validated['momo_number'] ?? null,
                'momo_name' => $validated['momo_name'] ?? null,
            ]);
        });

        $withdrawal->load('vendorProfile:id,slug,business_name,user_id');

        User::query()
            ->where('role', UserRole::Admin)
            ->get()
            ->each(fn (User $admin) => $admin->notify(
                new VendorWithdrawalUpdatedNotification($withdrawal, 'requested')
            ));

        return new VendorWithdrawalResource($withdrawal);
    }

    private function vendorProfileOrAbort(Request $request): VendorProfile
    {
        $profile = $request->user()->vendorProfile;
        if ($profile === null) {
            abort(403, 'Vendor profile is required.');
        }

        return $profile;
    }
}
