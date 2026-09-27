<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Cart */
class CartResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $items = $this->items
            ->filter(fn ($item) => $item->product !== null)
            ->values();

        $totalsByCurrency = $items
            ->groupBy(fn ($item) => $item->product->currency ?? 'GHS')
            ->map(function ($group, $currency) {
                $subtotal = round($group->sum(function ($item) {
                    return (float) $item->product->price * $item->quantity;
                }), 2);

                return [
                    'currency' => $currency,
                    'subtotal' => $subtotal,
                ];
            })
            ->values()
            ->all();

        return [
            'id' => $this->id,
            'items' => CartItemResource::collection($items),
            'totals_by_currency' => $totalsByCurrency,
            'item_count' => $items->sum('quantity'),
        ];
    }
}
