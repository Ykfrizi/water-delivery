<?php

namespace App\Http\Controllers\Api\V1\Marketplace;

use App\Http\Controllers\Controller;
use App\Http\Resources\ProductResource;
use App\Http\Resources\ReviewResource;
use App\Http\Resources\VendorProfileResource;
use App\Models\Product;
use App\Models\Review;
use App\Models\VendorProfile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class VendorDirectoryController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $perPage = min(max((int) $request->input('per_page', 15), 1), 50);
        $query = VendorProfile::query()->publiclyListed();

        if ($request->filled('q')) {
            $term = $request->string('q');
            $query->where(function ($q) use ($term) {
                $q->where('business_name', 'like', '%'.$term.'%')
                    ->orWhere('description', 'like', '%'.$term.'%');
            });
        }

        if ($request->filled('city')) {
            $query->where('city', $request->string('city'));
        }

        if ($request->filled('region')) {
            $query->where('region', $request->string('region'));
        }

        if ($request->filled('country')) {
            $query->where('country', $request->string('country'));
        }

        if ($request->filled('category')) {
            $tags = array_filter(array_map('trim', explode(',', (string) $request->string('category'))));
            foreach ($tags as $tag) {
                $query->whereJsonContains('categories', $tag);
            }
        }

        if ($request->filled('min_rating')) {
            $query->where('average_rating', '>=', (float) $request->input('min_rating'));
        }

        $lat = $request->filled('latitude') ? (float) $request->input('latitude') : null;
        $lng = $request->filled('longitude') ? (float) $request->input('longitude') : null;
        $radius = $request->filled('radius_km') ? (float) $request->input('radius_km') : null;
        $distanceExpr = $this->haversineDistanceExpression();

        if ($lat !== null && $lng !== null) {
            $query->whereNotNull('latitude')->whereNotNull('longitude');
            $query->selectRaw('vendor_profiles.*, '.$distanceExpr.' as distance_km', [$lat, $lng, $lat]);

            if ($radius !== null) {
                $query->whereRaw($distanceExpr.' <= ?', [$lat, $lng, $lat, $radius]);
            }
        }

        $sort = $request->string('sort', 'rating_desc')->toString();
        if ($lat !== null && $lng !== null && $sort === 'distance') {
            $query->orderByRaw($distanceExpr.' asc', [$lat, $lng, $lat]);
        } elseif ($sort === 'name') {
            $query->orderBy('business_name');
        } else {
            $query->orderByDesc('average_rating')->orderBy('business_name');
        }

        $vendors = $query->paginate($perPage);

        return VendorProfileResource::collection($vendors);
    }

    public function show(VendorProfile $vendor): VendorProfileResource
    {
        $this->ensurePublicVendor($vendor);

        $vendor->load('deliveryZones');

        return new VendorProfileResource($vendor);
    }

    public function products(Request $request, VendorProfile $vendor): AnonymousResourceCollection
    {
        $this->ensurePublicVendor($vendor);

        $perPage = min(max((int) $request->input('per_page', 20), 1), 100);
        $query = Product::query()
            ->with('images')
            ->where('vendor_profile_id', $vendor->id)
            ->where('is_available', true)
            ->orderBy('name');

        if ($request->filled('q')) {
            $term = $request->string('q');
            $query->where(function ($q) use ($term) {
                $q->where('name', 'like', '%'.$term.'%')
                    ->orWhere('description', 'like', '%'.$term.'%');
            });
        }

        if ($request->filled('min_price')) {
            $query->where('price', '>=', (float) $request->input('min_price'));
        }

        if ($request->filled('max_price')) {
            $query->where('price', '<=', (float) $request->input('max_price'));
        }

        if ($request->boolean('in_stock')) {
            $query->where('stock_quantity', '>', 0);
        }

        if ($request->filled('attr')) {
            $attrs = is_array($request->input('attr')) ? $request->input('attr') : [];
            foreach ($attrs as $key => $value) {
                if ($value === null || $value === '') {
                    continue;
                }
                $key = (string) $key;
                $query->where("attributes->{$key}", (string) $value);
            }
        }

        $products = $query->paginate($perPage);

        return ProductResource::collection($products);
    }

    public function reviews(Request $request, VendorProfile $vendor): AnonymousResourceCollection
    {
        $this->ensurePublicVendor($vendor);

        $perPage = min(max((int) $request->input('per_page', 15), 1), 50);
        $reviews = Review::query()
            ->where('vendor_profile_id', $vendor->id)
            ->with('customer:id,name')
            ->orderByDesc('created_at')
            ->paginate($perPage);

        return ReviewResource::collection($reviews);
    }

    private function ensurePublicVendor(VendorProfile $vendor): void
    {
        if (! $vendor->isPubliclyListed()) {
            abort(404);
        }
    }

    private function haversineDistanceExpression(): string
    {
        return '(6371 * acos(least(1, greatest(-1, cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + sin(radians(?)) * sin(radians(latitude))))))';
    }
}
