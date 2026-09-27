<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Product */
class ProductResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $this->resource->loadMissing('images');

        return [
            'id' => $this->id,
            'name' => $this->name,
            'slug' => $this->slug,
            'description' => $this->description,
            'image_url' => $this->primaryImageUrl(),
            'images' => ProductImageResource::collection($this->images),
            'sku' => $this->sku,
            'price' => (float) $this->price,
            'currency' => $this->currency,
            'stock_quantity' => $this->stock_quantity,
            'is_available' => $this->is_available,
            'attributes' => $this->attributes ?? [],
        ];
    }
}
