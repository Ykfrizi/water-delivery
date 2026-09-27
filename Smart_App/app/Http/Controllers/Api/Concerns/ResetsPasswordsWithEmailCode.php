<?php

namespace App\Http\Controllers\Api\Concerns;

use App\Enums\UserRole;
use App\Services\PasswordResetCodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rules\Password;

trait ResetsPasswordsWithEmailCode
{
    abstract protected function passwordResetRole(): UserRole;

    public function forgotPassword(Request $request, PasswordResetCodeService $resets): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'email'],
        ]);

        $resets->send($validated['email'], $this->passwordResetRole());

        return response()->json([
            'message' => 'If that email is registered, a 6-digit reset code was sent.',
        ]);
    }

    public function resetPassword(Request $request, PasswordResetCodeService $resets): JsonResponse
    {
        $request->merge([
            'token' => (string) ($request->input('token') ?? $request->input('code') ?? ''),
        ]);

        $validated = $request->validate([
            'email' => ['required', 'email'],
            'token' => ['required', 'string', 'max:32'],
            'password' => ['required', 'confirmed', Password::defaults()],
        ]);

        $resets->reset(
            $validated['email'],
            $validated['token'],
            $validated['password'],
            $this->passwordResetRole(),
        );

        return response()->json([
            'message' => 'Password updated. You can sign in now.',
        ]);
    }
}
