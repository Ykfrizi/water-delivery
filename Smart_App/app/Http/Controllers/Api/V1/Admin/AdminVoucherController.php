<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Http\Resources\VoucherResource;
use App\Models\Voucher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

class AdminVoucherController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $perPage = min(max((int) $request->input('per_page', 30), 1), 100);

        return VoucherResource::collection(
            Voucher::query()->orderByDesc('id')->paginate($perPage)
        );
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $this->validated($request, creating: true);
        $validated['code'] = Voucher::normalizeCode($validated['code']);
        $validated['used_count'] = 0;
        $validated['is_active'] = $validated['is_active'] ?? true;

        $voucher = Voucher::query()->create($validated);

        return (new VoucherResource($voucher))
            ->response()
            ->setStatusCode(201);
    }

    public function update(Request $request, Voucher $voucher): VoucherResource
    {
        $validated = $this->validated($request, creating: false, exceptId: $voucher->id);
        if (isset($validated['code'])) {
            $validated['code'] = Voucher::normalizeCode($validated['code']);
        }

        $voucher->fill($validated)->save();

        return new VoucherResource($voucher);
    }

    public function destroy(Voucher $voucher): JsonResponse
    {
        $voucher->delete();

        return response()->json(['message' => 'Voucher deleted']);
    }

    private function validated(Request $request, bool $creating, ?int $exceptId = null): array
    {
        $unique = Rule::unique('vouchers', 'code');
        if ($exceptId !== null) {
            $unique = $unique->ignore($exceptId);
        }

        $codeRule = $creating ? ['required'] : ['sometimes'];
        $typeRule = $creating ? ['required'] : ['sometimes'];
        $valueRule = $creating ? ['required'] : ['sometimes'];

        return $request->validate([
            'code' => [...$codeRule, 'string', 'max:40', $unique],
            'type' => [...$typeRule, Rule::in(['percent', 'fixed'])],
            'value' => [
                ...$valueRule,
                'numeric',
                'min:0.01',
                Rule::when($request->input('type', 'fixed') === 'percent', ['max:100']),
            ],
            'max_uses' => ['nullable', 'integer', 'min:1'],
            'is_active' => ['sometimes', 'boolean'],
            'expires_at' => ['nullable', 'date'],
        ]);
    }
}
