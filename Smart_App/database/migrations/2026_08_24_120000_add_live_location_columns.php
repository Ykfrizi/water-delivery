<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->decimal('last_latitude', 10, 7)->nullable()->after('role');
            $table->decimal('last_longitude', 10, 7)->nullable()->after('last_latitude');
            $table->timestamp('last_located_at')->nullable()->after('last_longitude');
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->decimal('courier_latitude', 10, 7)->nullable()->after('shipping_address');
            $table->decimal('courier_longitude', 10, 7)->nullable()->after('courier_latitude');
            $table->timestamp('courier_located_at')->nullable()->after('courier_longitude');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['last_latitude', 'last_longitude', 'last_located_at']);
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn(['courier_latitude', 'courier_longitude', 'courier_located_at']);
        });
    }
};
