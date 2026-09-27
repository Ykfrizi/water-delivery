<?php

namespace App\Http\Controllers\Api\V1\Vendor;

use App\Http\Controllers\Controller;
use App\Http\Resources\ProductResource;
use App\Models\CartItem;
use App\Models\OrderItem;
use App\Models\Product;
use App\Models\ProductImage;
use App\Models\VendorProfile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class VendorProductController extends Controller
{
    private const MAX_IMAGES_PER_PRODUCT = 10;

    public function index(Request $request): AnonymousResourceCollection
    {
        $profile = $this->resolveProfile($request);
        $perPage = min(max((int) $request->input('per_page', 20), 1), 100);

        return ProductResource::collection(
            $profile->products()->with('images')->orderBy('name')->paginate($perPage)
        );
    }

    public function store(Request $request): JsonResponse
    {
        $profile = $this->resolveProfile($request);

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'description' => ['nullable', 'string'],
            'images' => ['nullable', 'array', 'max:'.self::MAX_IMAGES_PER_PRODUCT],
            'images.*' => ['image', 'max:5120'],
            'sku' => ['nullable', 'string', 'max:100'],
            'price' => ['required', 'numeric', 'min:0'],
            'currency' => ['nullable', 'string', 'size:3'],
            'stock_quantity' => ['nullable', 'integer', 'min:0'],
            'is_available' => ['sometimes', 'boolean'],
            'attributes' => ['nullable', 'array'],
        ]);

        $slug = $this->uniqueProductSlug($profile->id, Str::slug($validated['name']));

        $product = $profile->products()->create([
            'name' => $validated['name'],
            'slug' => $slug,
            'description' => $validated['description'] ?? null,
            'sku' => $validated['sku'] ?? null,
            'price' => $validated['price'],
            'currency' => strtoupper($validated['currency'] ?? (string) config('paystack.currency', 'GHS')),
            'stock_quantity' => $validated['stock_quantity'] ?? 0,
            'is_available' => $validated['is_available'] ?? true,
            'attributes' => $validated['attributes'] ?? [],
        ]);

        $this->storeUploadedImages($product, $request->file('images', []));

        return (new ProductResource($product->load('images')))
            ->response()
            ->setStatusCode(201);
    }

    public function show(Request $request, Product $product): ProductResource
    {
        $this->authorizeProduct($request, $product);

        return new ProductResource($product->load('images'));
    }

    public function update(Request $request, Product $product): ProductResource
    {
        $this->authorizeProduct($request, $product);
        $product->load('images');

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'description' => ['nullable', 'string'],
            'images' => ['nullable', 'array'],
            'images.*' => ['image', 'max:5120'],
            'remove_image_ids' => ['nullable', 'array'],
            'remove_image_ids.*' => ['integer'],
            'sku' => ['nullable', 'string', 'max:100'],
            'price' => ['sometimes', 'numeric', 'min:0'],
            'currency' => ['nullable', 'string', 'size:3'],
            'stock_quantity' => ['nullable', 'integer', 'min:0'],
            'is_available' => ['sometimes', 'boolean'],
            'attributes' => ['nullable', 'array'],
        ]);

        if (isset($validated['name'])) {
            $validated['slug'] = $this->uniqueProductSlug(
                $product->vendor_profile_id,
                Str::slug($validated['name']),
                $product->id
            );
        }

        if (isset($validated['currency'])) {
            $validated['currency'] = strtoupper($validated['currency']);
        }

        $removeIds = $validated['remove_image_ids'] ?? [];
        $newFiles = $request->file('images', []) ?? [];
        if (! is_array($newFiles)) {
            $newFiles = [$newFiles];
        }
        $newFiles = array_values(array_filter($newFiles));

        $remainingCount = $product->images->whereNotIn('id', $removeIds)->count();
        if ($remainingCount + count($newFiles) > self::MAX_IMAGES_PER_PRODUCT) {
            abort(422, 'A product can have at most '.self::MAX_IMAGES_PER_PRODUCT.' images.');
        }

        if ($removeIds !== []) {
            $this->deleteProductImages($product, $removeIds);
        }

        unset($validated['images'], $validated['remove_image_ids']);

        $product->update($validated);

        $this->storeUploadedImages($product->fresh(), $newFiles);

        return new ProductResource($product->fresh()->load('images'));
    }

    public function destroy(Request $request, Product $product): JsonResponse
    {
        $this->authorizeProduct($request, $product);

        DB::transaction(function () use ($product) {
            $product->load('images');
            $this->deleteProductImages($product, $product->images->pluck('id')->all());

            CartItem::query()->where('product_id', $product->id)->delete();
            OrderItem::query()->where('product_id', $product->id)->update(['product_id' => null]);

            $product->delete();
        });

        return response()->json(['message' => 'Product deleted']);
    }

    /**
     * @param  array<int, UploadedFile|null>  $files
     */
    private function storeUploadedImages(Product $product, array $files): void
    {
        $files = array_values(array_filter($files));
        if ($files === []) {
            return;
        }

        $sortOrder = (int) ($product->images()->max('sort_order') ?? -1);

        foreach ($files as $file) {
            if (! $file instanceof UploadedFile) {
                continue;
            }

            $path = $file->store('products/'.$product->id, 'public');
            $sortOrder++;

            $product->images()->create([
                'path' => $path,
                'sort_order' => $sortOrder,
            ]);
        }
    }

    /**
     * @param  array<int, int|string>  $imageIds
     */
    private function deleteProductImages(Product $product, array $imageIds): void
    {
        if ($imageIds === []) {
            return;
        }

        $images = ProductImage::query()
            ->where('product_id', $product->id)
            ->whereIn('id', $imageIds)
            ->get();

        foreach ($images as $image) {
            if (Storage::disk('public')->exists($image->path)) {
                Storage::disk('public')->delete($image->path);
            }
            $image->delete();
        }
    }

    private function authorizeProduct(Request $request, Product $product): void
    {
        $profileId = $this->resolveProfile($request)->id;
        if ((int) $product->vendor_profile_id !== $profileId) {
            abort(404);
        }
    }

    private function resolveProfile(Request $request): VendorProfile
    {
        $profile = $request->user()->vendorProfile;

        if ($profile === null) {
            abort(403, 'Vendor profile is required. Register with your Ghana Card number.');
        }

        return $profile;
    }

    private function uniqueProductSlug(int $vendorProfileId, string $baseSlug, ?int $ignoreProductId = null): string
    {
        if ($baseSlug === '') {
            $baseSlug = 'product';
        }

        $slug = $baseSlug;
        $i = 1;
        while (Product::query()
            ->where('vendor_profile_id', $vendorProfileId)
            ->where('slug', $slug)
            ->when($ignoreProductId, fn ($q) => $q->where('id', '!=', $ignoreProductId))
            ->exists()) {
            $slug = $baseSlug.'-'.$i++;
        }

        return $slug;
    }
}
