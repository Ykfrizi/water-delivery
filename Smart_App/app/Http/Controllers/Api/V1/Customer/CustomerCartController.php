<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use App\Http\Resources\CartResource;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Product;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class CustomerCartController extends Controller
{
    public function show(Request $request): CartResource
    {
        return new CartResource($this->hydrateCart($request->user()->id));
    }

    public function addItem(Request $request): CartResource
    {
        $validated = $request->validate([
            'product_id' => ['required', 'integer', 'exists:products,id'],
            'quantity' => ['required', 'integer', 'min:1'],
        ]);

        $product = Product::query()
            ->with('vendorProfile')
            ->findOrFail($validated['product_id']);

        $this->assertProductBuyable($product);

        $cart = $this->hydrateCart($request->user()->id);

        $line = $cart->items->firstWhere('product_id', $product->id);
        $newQty = ($line?->quantity ?? 0) + $validated['quantity'];

        if ($newQty > $product->stock_quantity) {
            throw ValidationException::withMessages([
                'quantity' => ['Not enough stock for this product.'],
            ]);
        }

        if ($line !== null) {
            $line->quantity = $newQty;
            $line->save();
        } else {
            $cart->items()->create([
                'product_id' => $product->id,
                'quantity' => $validated['quantity'],
            ]);
        }

        return new CartResource($this->hydrateCart($request->user()->id));
    }

    public function updateItem(Request $request, CartItem $cart_item): CartResource
    {
        $this->authorizeCartItem($request, $cart_item);

        $validated = $request->validate([
            'quantity' => ['required', 'integer', 'min:1'],
        ]);

        $product = Product::query()->with('vendorProfile')->findOrFail($cart_item->product_id);
        $this->assertProductBuyable($product);

        if ($validated['quantity'] > $product->stock_quantity) {
            throw ValidationException::withMessages([
                'quantity' => ['Not enough stock for this product.'],
            ]);
        }

        $cart_item->quantity = $validated['quantity'];
        $cart_item->save();

        return new CartResource($this->hydrateCart($request->user()->id));
    }

    public function removeItem(Request $request, CartItem $cart_item): CartResource
    {
        $this->authorizeCartItem($request, $cart_item);
        $cart_item->delete();

        return new CartResource($this->hydrateCart($request->user()->id));
    }

    public function clear(Request $request): CartResource
    {
        $cart = $this->resolveCart($request->user()->id);
        $cart->items()->delete();

        return new CartResource($this->hydrateCart($request->user()->id));
    }

    private function resolveCart(int $userId): Cart
    {
        return Cart::query()->firstOrCreate(['user_id' => $userId]);
    }

    private function hydrateCart(int $userId): Cart
    {
        $cart = $this->resolveCart($userId);
        $cart->load(['items.product.vendorProfile', 'items.product.images']);

        $orphans = $cart->items->filter(
            fn (CartItem $item) => $item->product === null || $item->product->vendorProfile === null
        );
        if ($orphans->isNotEmpty()) {
            CartItem::query()->whereIn('id', $orphans->pluck('id'))->delete();
            $cart->unsetRelation('items');
            $cart->load(['items.product.vendorProfile', 'items.product.images']);
        }

        return $cart;
    }

    private function authorizeCartItem(Request $request, CartItem $cartItem): void
    {
        $cartItem->load('cart');
        if ((int) $cartItem->cart->user_id !== (int) $request->user()->id) {
            abort(404);
        }
    }

    private function assertProductBuyable(Product $product): void
    {
        if (! $product->is_available) {
            throw ValidationException::withMessages([
                'product_id' => ['This product is not available.'],
            ]);
        }

        if ($product->vendorProfile === null || ! $product->vendorProfile->isPubliclyListed()) {
            throw ValidationException::withMessages([
                'product_id' => ['This vendor is not accepting orders.'],
            ]);
        }
    }
}
