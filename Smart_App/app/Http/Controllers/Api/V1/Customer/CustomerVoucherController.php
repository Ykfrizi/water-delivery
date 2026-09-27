<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use App\Models\Voucher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class CustomerVoucherController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'code' => ['required', 'string', 'max:40'],
            'subtotal' => ['nullable', 'numeric', 'min:0'],
        ]);

        $code = Voucher::normalizeCode($validated['code']);
        $voucher = Voucher::query()->where('code', $code)->first();
        if ($voucher === null) {
            throw ValidationException::withMessages([
                'voucher_code' => ['Voucher not found.'],
            ]);
        }

        $voucher->assertRedeemable();
        $subtotal = round((float) ($validated['subtotal'] ?? 0), 2);
        $discount = $subtotal > 0 ? $voucher->discountAmount($subtotal) : null;

        return response()->json([
            'data' => [
                'code' => $voucher->code,
                'type' => $voucher->type,
                'value' => (float) $voucher->value,
                'discount_amount' => $discount,
            ],
        ]);
    }
}
