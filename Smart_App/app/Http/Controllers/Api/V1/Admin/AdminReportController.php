<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Enums\OrderPaymentStatus;
use App\Enums\OrderStatus;
use App\Enums\UserRole;
use App\Enums\VendorApprovalStatus;
use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\User;
use App\Models\VendorProfile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AdminReportController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date', 'after_or_equal:from'],
        ]);

        $from = $validated['from'] ?? null;
        $to = $validated['to'] ?? null;

        $orders = Order::query()
            ->paidSuccessful()
            ->when($from, fn ($q) => $q->whereDate('placed_at', '>=', $from))
            ->when($to, fn ($q) => $q->whereDate('placed_at', '<=', $to));

        $summary = (clone $orders)
            ->selectRaw('COUNT(*) as orders_count')
            ->selectRaw('COALESCE(SUM(subtotal), 0) as subtotal')
            ->selectRaw('COALESCE(SUM(delivery_fee), 0) as delivery_fees')
            ->selectRaw('COALESCE(SUM(total), 0) as revenue')
            ->selectRaw('COUNT(DISTINCT customer_id) as customers_with_orders')
            ->selectRaw('COUNT(DISTINCT vendor_profile_id) as vendors_with_orders')
            ->first();

        $paidRevenue = (clone $orders)
            ->where('payment_status', OrderPaymentStatus::Paid)
            ->sum('total');

        $byOrderStatus = (clone $orders)
            ->select('status', DB::raw('COUNT(*) as orders_count'), DB::raw('COALESCE(SUM(total), 0) as revenue'))
            ->groupBy('status')
            ->get()
            ->mapWithKeys(fn ($row) => [
                $row->status instanceof OrderStatus ? $row->status->value : (string) $row->status => [
                    'orders_count' => (int) $row->orders_count,
                    'revenue' => round((float) $row->revenue, 2),
                ],
            ]);

        $byPaymentStatus = (clone $orders)
            ->select('payment_status', DB::raw('COUNT(*) as orders_count'), DB::raw('COALESCE(SUM(total), 0) as revenue'))
            ->groupBy('payment_status')
            ->get()
            ->mapWithKeys(fn ($row) => [
                $row->payment_status instanceof OrderPaymentStatus
                    ? $row->payment_status->value
                    : (string) $row->payment_status => [
                        'orders_count' => (int) $row->orders_count,
                        'revenue' => round((float) $row->revenue, 2),
                    ],
            ]);

        $byVendor = (clone $orders)
            ->join('vendor_profiles', 'orders.vendor_profile_id', '=', 'vendor_profiles.id')
            ->select(
                'vendor_profiles.id as vendor_id',
                'vendor_profiles.slug',
                'vendor_profiles.business_name',
                DB::raw('COUNT(orders.id) as orders_count'),
                DB::raw('COALESCE(SUM(orders.total), 0) as revenue'),
            )
            ->groupBy('vendor_profiles.id', 'vendor_profiles.slug', 'vendor_profiles.business_name')
            ->orderByDesc('revenue')
            ->get()
            ->map(fn ($row) => [
                'vendor_id' => (int) $row->vendor_id,
                'slug' => $row->slug,
                'business_name' => $row->business_name,
                'orders_count' => (int) $row->orders_count,
                'revenue' => round((float) $row->revenue, 2),
            ])
            ->values();

        $byDay = (clone $orders)
            ->select(
                DB::raw('DATE(placed_at) as date'),
                DB::raw('COUNT(*) as orders_count'),
                DB::raw('COALESCE(SUM(total), 0) as revenue'),
            )
            ->groupBy(DB::raw('DATE(placed_at)'))
            ->orderBy('date')
            ->get()
            ->map(fn ($row) => [
                'date' => $row->date,
                'orders_count' => (int) $row->orders_count,
                'revenue' => round((float) $row->revenue, 2),
            ])
            ->values();

        $vendorsByApproval = VendorProfile::query()
            ->select('approval_status', DB::raw('COUNT(*) as count'))
            ->groupBy('approval_status')
            ->get()
            ->mapWithKeys(fn ($row) => [
                $row->approval_status instanceof VendorApprovalStatus
                    ? $row->approval_status->value
                    : (string) $row->approval_status => (int) $row->count,
            ]);

        $usersByRole = User::query()
            ->select('role', DB::raw('COUNT(*) as count'))
            ->groupBy('role')
            ->get()
            ->mapWithKeys(fn ($row) => [
                $row->role instanceof UserRole ? $row->role->value : (string) $row->role => (int) $row->count,
            ]);

        return response()->json([
            'period' => [
                'from' => $from,
                'to' => $to,
            ],
            'summary' => [
                'orders_count' => (int) ($summary->orders_count ?? 0),
                'subtotal' => round((float) ($summary->subtotal ?? 0), 2),
                'delivery_fees' => round((float) ($summary->delivery_fees ?? 0), 2),
                'revenue' => round((float) ($summary->revenue ?? 0), 2),
                'paid_revenue' => round((float) $paidRevenue, 2),
                'customers_with_orders' => (int) ($summary->customers_with_orders ?? 0),
                'vendors_with_orders' => (int) ($summary->vendors_with_orders ?? 0),
                'active_vendors' => VendorProfile::query()->where('is_active', true)->count(),
                'pending_vendor_approvals' => VendorProfile::query()
                    ->where('approval_status', VendorApprovalStatus::Pending)
                    ->count(),
            ],
            'breakdown' => [
                'by_order_status' => $this->fillEnumKeys($byOrderStatus, OrderStatus::cases()),
                'by_payment_status' => $this->fillEnumKeys($byPaymentStatus, OrderPaymentStatus::cases()),
                'by_vendor' => $byVendor,
                'by_day' => $byDay,
                'vendors_by_approval' => $this->fillEnumKeys($vendorsByApproval, VendorApprovalStatus::cases(), 0),
                'users_by_role' => $this->fillEnumKeys($usersByRole, UserRole::cases(), 0),
            ],
        ]);
    }

    /**
     * @param  \Illuminate\Support\Collection<string, mixed>|array<string, mixed>  $grouped
     * @param  array<\BackedEnum>  $cases
     * @return array<string, mixed>
     */
    private function fillEnumKeys($grouped, array $cases, mixed $empty = null): array
    {
        $result = [];

        foreach ($cases as $case) {
            $key = $case->value;
            if (isset($grouped[$key])) {
                $result[$key] = $grouped[$key];
            } elseif ($empty === 0) {
                $result[$key] = 0;
            } else {
                $result[$key] = [
                    'orders_count' => 0,
                    'revenue' => 0.0,
                ];
            }
        }

        return $result;
    }
}
