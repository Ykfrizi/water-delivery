<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\CartItem */
class CartItemResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $product = $this->product;
        if ($product === null) {
            return [
                'id' => $this->id,
                'quantity' => $this->quantity,
                'line_total' => 0,
                'currency' => 'GHS',
                'unavailable' => true,
                'product' => null,
            ];
        }

        $product->loadMissing(['vendorProfile', 'images']);
        $lineTotal = round((float) $product->price * $this->quantity, 2);

        return [
            'id' => $this->id,
            'quantity' => $this->quantity,
            'line_total' => $lineTotal,
            'currency' => $product->currency,
            'product' => [
                'id' => $product->id,
                'name' => $product->name,
                'slug' => $product->slug,
                'image_url' => $product->primaryImageUrl(),
                'images' => ProductImageResource::collection($product->images),
                'price' => (float) $product->price,
                'currency' => $product->currency,
                'stock_quantity' => $product->stock_quantity,
                'is_available' => $product->is_available,
                'vendor' => [
                    'slug' => $product->vendorProfile?->slug,
                    'business_name' => $product->vendorProfile?->business_name,
                ],
            ],
        ];
    }
}
