<?php

namespace Database\Seeders;

use App\Enums\VendorApprovalStatus;
use App\Models\DeliveryZone;
use App\Models\Product;
use App\Models\Review;
use App\Models\User;
use App\Models\VendorProfile;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    public function run(): void
    {
        $customer = User::factory()->customer()->create([
            'name' => 'Test Customer',
            'email' => 'customer@example.com',
        ]);

        $vendorUser = User::factory()->vendor()->create([
            'name' => 'Jane Vendor',
            'email' => 'vendor@example.com',
        ]);

        User::factory()->admin()->create([
            'name' => 'Test Admin',
            'email' => 'admin@example.com',
            'password' => 'password',
        ]);

        $profile = VendorProfile::createForUser(
            $vendorUser,
            'Fresh Market Co.',
            'GHA-123456789-0',
        );
        $profile->update([
            'description' => 'Neighborhood groceries and produce with scheduled delivery.',
            'phone' => '+233200000000',
            'city' => 'Accra',
            'region' => 'Greater Accra',
            'country' => 'GH',
            'latitude' => 5.603717,
            'longitude' => -0.186964,
            'categories' => ['groceries', 'produce', 'organic'],
            'approval_status' => VendorApprovalStatus::Approved,
            'is_active' => true,
        ]);

        DeliveryZone::query()->create([
            'vendor_profile_id' => $profile->id,
            'name' => 'Westlands',
            'latitude' => -1.267,
            'longitude' => 36.811,
            'radius_km' => 5,
            'note' => 'Same-day for orders before 4pm.',
        ]);

        DeliveryZone::query()->create([
            'vendor_profile_id' => $profile->id,
            'name' => 'CBD',
            'latitude' => -1.286389,
            'longitude' => 36.817223,
            'radius_km' => 3,
            'note' => null,
        ]);

        $profile->products()->createMany([
            [
                'name' => 'Brown bread loaf',
                'slug' => Str::slug('Brown bread loaf'),
                'description' => 'Whole wheat, baked daily.',
                'sku' => 'BRD-001',
                'price' => 120.00,
                'currency' => 'GHS',
                'stock_quantity' => 40,
                'is_available' => true,
                'attributes' => ['diet' => 'vegetarian'],
            ],
            [
                'name' => 'Fresh tomatoes 1kg',
                'slug' => Str::slug('Fresh tomatoes 1kg'),
                'description' => 'Vine ripened.',
                'sku' => 'VEG-TMT-01',
                'price' => 180.00,
                'currency' => 'GHS',
                'stock_quantity' => 100,
                'is_available' => true,
                'attributes' => ['type' => 'vegetable'],
            ],
        ]);

        Review::query()->create([
            'vendor_profile_id' => $profile->id,
            'customer_id' => $customer->id,
            'rating' => 5,
            'comment' => 'Fast delivery and fair prices.',
        ]);
    }
}
