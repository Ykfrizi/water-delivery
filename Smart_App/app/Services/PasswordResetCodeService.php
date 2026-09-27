<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Models\User;
use App\Notifications\PasswordResetCodeNotification;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Throwable;

final class PasswordResetCodeService
{
    public const TTL_MINUTES = 15;

    public const THROTTLE_SECONDS = 60;

    public function send(string $email, UserRole $role): void
    {
        $email = Str::lower(trim($email));
        $throttleKey = 'password-reset-code:'.$role->value.':'.$email;

        if (Cache::has($throttleKey)) {
            throw ValidationException::withMessages([
                'email' => ['Please wait a minute before requesting another code.'],
            ]);
        }

        Cache::put($throttleKey, true, now()->addSeconds(self::THROTTLE_SECONDS));

        $user = User::query()
            ->where('email', $email)
            ->where('role', $role)
            ->first();

        if ($user === null) {
            return;
        }

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        DB::table('password_reset_tokens')->updateOrInsert(
            ['email' => $email],
            [
                'token' => Hash::make($code),
                'created_at' => now(),
            ],
        );

        try {
            $user->notify(new PasswordResetCodeNotification($code));
        } catch (Throwable $e) {
            report($e);
            Cache::forget($throttleKey);
            DB::table('password_reset_tokens')->where('email', $email)->delete();

            throw ValidationException::withMessages([
                'email' => ['We could not send the reset email. Try again in a moment.'],
            ]);
        }
    }

    public function reset(string $email, string $code, string $password, UserRole $role): void
    {
        $email = Str::lower(trim($email));
        $code = preg_replace('/\D+/', '', $code) ?? '';

        if (strlen($code) !== 6) {
            throw ValidationException::withMessages([
                'token' => ['Enter the 6-digit code from your email.'],
            ]);
        }

        $user = User::query()
            ->where('email', $email)
            ->where('role', $role)
            ->first();

        $row = DB::table('password_reset_tokens')->where('email', $email)->first();

        $valid = $user !== null
            && $row !== null
            && filled($row->token)
            && filled($row->created_at)
            && Carbon::parse($row->created_at)->addMinutes(self::TTL_MINUTES)->isFuture()
            && Hash::check($code, $row->token);

        if (! $valid) {
            throw ValidationException::withMessages([
                'token' => ['That reset code is invalid or has expired.'],
            ]);
        }

        $user->forceFill([
            'password' => $password,
        ])->save();

        DB::table('password_reset_tokens')->where('email', $email)->delete();
        $user->tokens()->delete();
    }
}
