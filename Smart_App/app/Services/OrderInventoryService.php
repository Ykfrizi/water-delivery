<?php

namespace App\Services;

use App\Enums\OrderStatus;
use App\Models\Order;
use App\Models\Product;
use Illuminate\Support\Facades\DB;

final class OrderInventoryService
{
    /**
     * Return quantities to catalog when an order moves to cancelled.
     */
    public static function releaseStockForCancellation(Order $order, OrderStatus $statusBefore): void
    {
        if ($statusBefore === OrderStatus::Cancelled
            || $statusBefore === OrderStatus::Completed
            || $statusBefore === OrderStatus::Delivered) {
            return;
        }

        $order->loadMissing('orderItems');

        DB::transaction(function () use ($order): void {
            $productIds = $order->orderItems->pluck('product_id')->sort()->values()->all();

            if ($productIds !== []) {
                Product::query()
                    ->whereIn('id', $productIds)
                    ->orderBy('id')
                    ->lockForUpdate()
                    ->get();
            }

            foreach ($order->orderItems as $item) {
                Product::query()
                    ->whereKey($item->product_id)
                    ->increment('stock_quantity', $item->quantity);
            }
        });
    }
}
