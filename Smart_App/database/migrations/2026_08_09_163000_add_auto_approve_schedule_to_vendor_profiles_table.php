<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('vendor_profiles', function (Blueprint $table) {
            $table->boolean('auto_approve_enabled')->default(false)->after('is_active');
            $table->timestamp('auto_approve_starts_at')->nullable()->after('auto_approve_enabled');
            $table->timestamp('auto_approve_ends_at')->nullable()->after('auto_approve_starts_at');
            $table->time('auto_approve_daily_start')->nullable()->after('auto_approve_ends_at');
            $table->time('auto_approve_daily_end')->nullable()->after('auto_approve_daily_start');
            $table->string('auto_approve_timezone', 64)->default('Africa/Accra')->after('auto_approve_daily_end');
        });
    }

    public function down(): void
    {
        Schema::table('vendor_profiles', function (Blueprint $table) {
            $table->dropColumn([
                'auto_approve_enabled',
                'auto_approve_starts_at',
                'auto_approve_ends_at',
                'auto_approve_daily_start',
                'auto_approve_daily_end',
                'auto_approve_timezone',
            ]);
        });
    }
};
