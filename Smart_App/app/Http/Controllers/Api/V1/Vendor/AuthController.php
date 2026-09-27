<?php

namespace App\Http\Controllers\Api\V1\Vendor;

use App\Enums\UserRole;
use App\Enums\VendorApprovalStatus;
use App\Http\Controllers\Api\Concerns\AuthenticatesApiUsers;
use App\Http\Controllers\Api\Concerns\ResetsPasswordsWithEmailCode;
use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\VendorProfile;
use App\Notifications\VendorRegisteredNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    use AuthenticatesApiUsers;
    use ResetsPasswordsWithEmailCode;

    protected function passwordResetRole(): UserRole
    {
        return UserRole::Vendor;
    }

    /** Ghana Card format: GHA-XXXXXXXXX-X */
    private const GHANA_CARD_PATTERN = '/^GHA-\d{9}-\d$/i';

    public function register(Request $request): JsonResponse
    {
        if ($request->filled('ghana_card_number')) {
            $request->merge([
                'ghana_card_number' => strtoupper(trim((string) $request->input('ghana_card_number'))),
            ]);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'business_name' => ['nullable', 'string', 'max:255'],
            'ghana_card_number' => [
                'required',
                'string',
                'max:20',
                'regex:'.self::GHANA_CARD_PATTERN,
                'unique:vendor_profiles,ghana_card_number',
            ],
            'email' => ['required', 'string', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'confirmed', Password::defaults()],
        ], [
            'ghana_card_number.regex' => 'Ghana Card number must look like GHA-123456789-0.',
            'ghana_card_number.unique' => 'This Ghana Card number is already registered.',
        ]);

        $user = User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'password' => $validated['password'],
            'role' => UserRole::Vendor,
        ]);

        VendorProfile::createForUser(
            $user,
            $validated['business_name'] ?? null,
            $validated['ghana_card_number'],
        );

        $user->load('vendorProfile');

        $admins = User::query()->where('role', UserRole::Admin)->get();
        if ($admins->isNotEmpty() && $user->vendorProfile !== null) {
            Notification::send($admins, new VendorRegisteredNotification($user->vendorProfile));
        }

        return $this->tokenResponse($user)->setStatusCode(201);
    }

    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required'],
        ]);

        $user = User::where('email', $credentials['email'])->first();

        if (! $user || ! Hash::check($credentials['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => [trans('auth.failed')],
            ]);
        }

        if ($user->role !== UserRole::Vendor) {
            throw ValidationException::withMessages([
                'email' => [trans('auth.failed')],
            ]);
        }

        $user->load('vendorProfile');

        if ($this->vendorProfileNeedsGhanaCard($user)) {
            throw ValidationException::withMessages([
                'email' => ['Vendor profile is incomplete. Please register again with your Ghana Card number.'],
            ]);
        }

        return $this->tokenResponse($user);
    }

    /**
     * Finish an existing vendor account that has no Ghana Card / profile row.
     */
    public function completeProfile(Request $request): JsonResponse
    {
        if ($request->filled('ghana_card_number')) {
            $request->merge([
                'ghana_card_number' => strtoupper(trim((string) $request->input('ghana_card_number'))),
            ]);
        }

        $validated = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required'],
            'business_name' => ['nullable', 'string', 'max:255'],
            'ghana_card_number' => [
                'required',
                'string',
                'max:20',
                'regex:'.self::GHANA_CARD_PATTERN,
            ],
        ], [
            'ghana_card_number.regex' => 'Ghana Card number must look like GHA-123456789-0.',
        ]);

        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! Hash::check($validated['password'], $user->password) || $user->role !== UserRole::Vendor) {
            throw ValidationException::withMessages([
                'email' => [trans('auth.failed')],
            ]);
        }

        $user->load('vendorProfile');

        $taken = VendorProfile::query()
            ->where('ghana_card_number', $validated['ghana_card_number'])
            ->when(
                $user->vendorProfile !== null,
                fn ($q) => $q->where('id', '!=', $user->vendorProfile->id),
            )
            ->exists();

        if ($taken) {
            throw ValidationException::withMessages([
                'ghana_card_number' => ['This Ghana Card number is already registered.'],
            ]);
        }

        if ($user->vendorProfile === null) {
            VendorProfile::createForUser(
                $user,
                $validated['business_name'] ?? null,
                $validated['ghana_card_number'],
            );
        } else {
            $user->vendorProfile->update([
                'ghana_card_number' => $validated['ghana_card_number'],
                'business_name' => filled($validated['business_name'] ?? null)
                    ? $validated['business_name']
                    : $user->vendorProfile->business_name,
                'approval_status' => VendorApprovalStatus::Pending,
                'is_active' => false,
            ]);
        }

        $user->load('vendorProfile');

        $admins = User::query()->where('role', UserRole::Admin)->get();
        if ($admins->isNotEmpty() && $user->vendorProfile !== null) {
            Notification::send($admins, new VendorRegisteredNotification($user->vendorProfile));
        }

        return $this->tokenResponse($user);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        $user->load('vendorProfile');

        return response()->json([
            'user' => $this->formatUser($user),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Logged out']);
    }

    protected function formatUser(User $user): array
    {
        $payload = [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'role' => $user->role->value,
        ];

        $profile = $user->relationLoaded('vendorProfile')
            ? $user->vendorProfile
            : $user->vendorProfile()->first();

        if ($profile !== null) {
            $payload['vendor'] = [
                'slug' => $profile->slug,
                'business_name' => $profile->business_name,
                'ghana_card_number' => $profile->ghana_card_number,
                'approval_status' => $profile->approval_status->value,
                'approval_notes' => $profile->approval_notes,
                'is_active' => $profile->is_active,
                'dashboard_access' => $profile->isApproved(),
            ];
        }

        return $payload;
    }

    private function vendorProfileNeedsGhanaCard(User $user): bool
    {
        $profile = $user->vendorProfile;

        return $profile === null || blank($profile->ghana_card_number);
    }
}
