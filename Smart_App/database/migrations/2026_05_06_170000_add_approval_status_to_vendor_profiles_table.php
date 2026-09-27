<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('vendor_profiles', function (Blueprint $table) {
            $table->string('approval_status')->default('pending')->after('is_active')->index();
            $table->text('approval_notes')->nullable()->after('approval_status');
            $table->timestamp('reviewed_at')->nullable()->after('approval_notes');
            $table->foreignId('reviewed_by')->nullable()->after('reviewed_at')->constrained('users')->nullOnDelete();
        });

        DB::table('vendor_profiles')->update(['approval_status' => 'approved']);
    }

    public function down(): void
    {
        Schema::table('vendor_profiles', function (Blueprint $table) {
            $table->dropConstrainedForeignId('reviewed_by');
            $table->dropColumn(['approval_status', 'approval_notes', 'reviewed_at']);
        });
    }
};
