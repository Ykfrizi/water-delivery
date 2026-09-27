<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->string('payment_method', 32)->nullable()->after('payment_status');
        });

        // This checkout was pay-on-delivery but was stored as unpaid Paystack.
        DB::table('orders')
            ->where('order_number', 'SM-20260824-E6937B')
            ->update(['payment_method' => 'cash_on_delivery']);
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn('payment_method');
        });
    }
};
