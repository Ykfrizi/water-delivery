<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('products', function (Blueprint $table) {
            $table->id();
            $table->foreignId('vendor_profile_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('slug');
            $table->text('description')->nullable();
            $table->string('sku')->nullable()->index();
            $table->decimal('price', 12, 2);
            $table->string('currency', 3)->default('GHS');
            $table->unsignedInteger('stock_quantity')->default(0);
            $table->boolean('is_available')->default(true)->index();
            $table->json('attributes')->nullable();
            $table->timestamps();

            $table->unique(['vendor_profile_id', 'slug']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('products');
    }
};
