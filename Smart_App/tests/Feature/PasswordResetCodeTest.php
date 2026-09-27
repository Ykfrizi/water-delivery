<?php

namespace Tests\Feature;

use App\Models\User;
use App\Notifications\PasswordResetCodeNotification;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class PasswordResetCodeTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('email')->unique();
            $table->string('role')->default('customer');
            $table->string('phone')->nullable();
            $table->timestamp('email_verified_at')->nullable();
            $table->string('password');
            $table->rememberToken();
            $table->timestamps();
        });

        Schema::create('password_reset_tokens', function (Blueprint $table) {
            $table->string('email')->primary();
            $table->string('token');
            $table->timestamp('created_at')->nullable();
        });

        Schema::create('personal_access_tokens', function (Blueprint $table) {
            $table->id();
            $table->morphs('tokenable');
            $table->text('name');
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();
        });
    }

    public function test_customer_can_request_and_use_an_email_reset_code(): void
    {
        Notification::fake();

        $user = User::factory()->customer()->create([
            'email' => 'customer@example.com',
            'password' => 'password',
        ]);

        $this->postJson('/api/v1/customer/auth/forgot-password', [
            'email' => 'customer@example.com',
        ])->assertOk();

        $code = '';
        Notification::assertSentTo(
            $user,
            PasswordResetCodeNotification::class,
            function (PasswordResetCodeNotification $notification) use (&$code): bool {
                $code = $notification->code;

                return strlen($notification->code) === 6;
            },
        );

        $this->postJson('/api/v1/customer/auth/reset-password', [
            'email' => 'customer@example.com',
            'token' => $code,
            'password' => 'new-password',
            'password_confirmation' => 'new-password',
        ])->assertOk();

        $this->assertTrue(Hash::check('new-password', $user->fresh()->password));
    }

    public function test_unknown_email_does_not_send_mail(): void
    {
        Notification::fake();

        $this->postJson('/api/v1/customer/auth/forgot-password', [
            'email' => 'nobody@example.com',
        ])->assertOk();

        Notification::assertNothingSent();
    }

    public function test_vendor_email_does_not_reset_through_customer_endpoint(): void
    {
        Notification::fake();

        User::factory()->vendor()->create([
            'email' => 'vendor@example.com',
        ]);

        $this->postJson('/api/v1/customer/auth/forgot-password', [
            'email' => 'vendor@example.com',
        ])->assertOk();

        Notification::assertNothingSent();
    }

    public function test_invalid_code_is_rejected(): void
    {
        Notification::fake();

        $user = User::factory()->customer()->create([
            'email' => 'customer@example.com',
        ]);

        $this->postJson('/api/v1/customer/auth/forgot-password', [
            'email' => 'customer@example.com',
        ])->assertOk();

        $sentCode = '000000';
        Notification::assertSentTo(
            $user,
            PasswordResetCodeNotification::class,
            function (PasswordResetCodeNotification $notification) use (&$sentCode): bool {
                $sentCode = $notification->code;

                return true;
            },
        );

        $wrong = $sentCode === '000000' ? '111111' : '000000';

        $this->postJson('/api/v1/customer/auth/reset-password', [
            'email' => 'customer@example.com',
            'token' => $wrong,
            'password' => 'new-password',
            'password_confirmation' => 'new-password',
        ])->assertStatus(422);
    }
}
