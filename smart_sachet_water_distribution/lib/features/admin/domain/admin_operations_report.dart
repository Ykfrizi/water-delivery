import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_order_summary.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_vendor_summary.dart';

/// One slice in a report breakdown chart/list.
class ReportBreakdownItem {
  const ReportBreakdownItem({
    required this.label,
    required this.count,
    this.amount,
  });

  final String label;
  final int count;
  final num? amount;

  double shareOf(int total) => total <= 0 ? 0 : count / total;

  String get amountLabel =>
      amount == null ? '' : formatMoney(amount, currency: kAppCurrency);
}

/// Aggregated admin operations report with clear breakdowns.
class AdminOperationsReport {
  const AdminOperationsReport({
    required this.totalOrders,
    required this.pendingApprovals,
    required this.cancelledOrders,
    required this.deliveredOrders,
    required this.estimatedRevenue,
    required this.totalVendors,
    required this.approvedVendors,
    required this.pendingVendors,
    required this.rejectedVendors,
    required this.ordersByStatus,
    required this.ordersByVendor,
    required this.vendorsByStatus,
    this.sourceNote = '',
  });

  final int totalOrders;
  final int pendingApprovals;
  final int cancelledOrders;
  final int deliveredOrders;
  final num estimatedRevenue;
  final int totalVendors;
  final int approvedVendors;
  final int pendingVendors;
  final int rejectedVendors;
  final List<ReportBreakdownItem> ordersByStatus;
  final List<ReportBreakdownItem> ordersByVendor;
  final List<ReportBreakdownItem> vendorsByStatus;
  final String sourceNote;

  String get revenueLabel =>
      formatMoney(estimatedRevenue, currency: kAppCurrency);

  factory AdminOperationsReport.fromData({
    required List<AdminOrderSummary> orders,
    required List<AdminVendorSummary> vendors,
    String? sourceNote,
  }) {
    final statusCounts = <String, int>{};
    final statusAmounts = <String, num>{};
    final vendorCounts = <String, int>{};
    final vendorAmounts = <String, num>{};
    var pending = 0;
    var cancelled = 0;
    var delivered = 0;
    num revenue = 0;

    var counted = 0;
    for (final o in orders) {
      if (!_isPaid(o.raw)) continue;
      final status = (o.status ?? 'unknown').toLowerCase().trim();
      final label = _statusBucket(status);
      if (label == 'Cancelled') continue;
      counted++;
      statusCounts[label] = (statusCounts[label] ?? 0) + 1;

      final amount = _orderAmount(o.raw);
      if (amount != null) {
        statusAmounts[label] = (statusAmounts[label] ?? 0) + amount;
        if (label != 'Cancelled') {
          revenue += amount;
        }
      }

      if (o.needsApproval) pending++;
      if (label == 'Cancelled') cancelled++;
      if (label == 'Delivered') delivered++;

      final vendor = o.vendorSlug?.trim().isNotEmpty == true
          ? o.vendorSlug!.trim()
          : 'Unassigned';
      vendorCounts[vendor] = (vendorCounts[vendor] ?? 0) + 1;
      if (amount != null) {
        vendorAmounts[vendor] = (vendorAmounts[vendor] ?? 0) + amount;
      }
    }

    var approvedV = 0;
    var pendingV = 0;
    var rejectedV = 0;
    for (final v in vendors) {
      if (v.isApproved) {
        approvedV++;
      } else if (v.isRejected) {
        rejectedV++;
      } else {
        pendingV++;
      }
    }

    List<ReportBreakdownItem> toBreakdown(
      Map<String, int> counts, {
      Map<String, num>? amounts,
    }) {
      final items = counts.entries
          .map(
            (e) => ReportBreakdownItem(
              label: e.key,
              count: e.value,
              amount: amounts?[e.key],
            ),
          )
          .toList()
        ..sort((a, b) => b.count.compareTo(a.count));
      return items;
    }

    return AdminOperationsReport(
      totalOrders: counted,
      pendingApprovals: pending,
      cancelledOrders: cancelled,
      deliveredOrders: delivered,
      estimatedRevenue: revenue,
      totalVendors: vendors.length,
      approvedVendors: approvedV,
      pendingVendors: pendingV,
      rejectedVendors: rejectedV,
      ordersByStatus: toBreakdown(statusCounts, amounts: statusAmounts),
      ordersByVendor: toBreakdown(vendorCounts, amounts: vendorAmounts),
      vendorsByStatus: [
        ReportBreakdownItem(label: 'Approved', count: approvedV),
        ReportBreakdownItem(label: 'Pending', count: pendingV),
        ReportBreakdownItem(label: 'Rejected', count: rejectedV),
      ],
      sourceNote: sourceNote ?? '',
    );
  }

  static bool _isPaid(Map<String, dynamic> raw) {
    final v = raw['payment_status']?.toString().toLowerCase().trim();
    if (raw['paid_at'] != null) return true;
    return v == 'paid' || v == 'success' || v == 'successful';
  }

  static String _statusBucket(String status) {
    if (status.isEmpty ||
        status == 'pending' ||
        status == 'awaiting_approval' ||
        status == 'awaiting_admin' ||
        status == 'new') {
      return 'Needs approval';
    }
    if (status == 'processing' ||
        status == 'confirmed' ||
        status == 'preparing') {
      return 'Processing';
    }
    if (status == 'shipped' || status == 'out_for_delivery') {
      return 'Shipped';
    }
    if (status == 'delivered') return 'Delivered';
    if (status == 'cancelled' || status == 'rejected') return 'Cancelled';
    return status[0].toUpperCase() + status.substring(1);
  }

  static num? _orderAmount(Map<String, dynamic> raw) {
    for (final key in const [
      'total',
      'grand_total',
      'amount',
      'order_total',
      'payable_amount',
    ]) {
      final v = raw[key];
      if (v is num) return v;
      if (v != null) {
        final parsed = num.tryParse(v.toString());
        if (parsed != null) return parsed;
      }
    }

    final totals = raw['totals_by_currency'] ?? raw['totals'];
    if (totals is Map) {
      for (final value in totals.values) {
        if (value is num) return value;
        final parsed = num.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
        if (value is Map) {
          final nested = value['amount'] ?? value['total'] ?? value['value'];
          if (nested is num) return nested;
          final nestedParsed = num.tryParse(nested?.toString() ?? '');
          if (nestedParsed != null) return nestedParsed;
        }
      }
    }

    final items = raw['items'] ?? raw['order_items'] ?? raw['lines'];
    if (items is List) {
      num sum = 0;
      var any = false;
      for (final item in items) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final lineTotal = row['total'] ??
            row['line_total'] ??
            row['amount'] ??
            ((row['price'] is num && row['quantity'] is num)
                ? (row['price'] as num) * (row['quantity'] as num)
                : row['price'] ?? row['unit_price']);
        if (lineTotal is num) {
          sum += lineTotal;
          any = true;
        } else {
          final parsed = num.tryParse(lineTotal?.toString() ?? '');
          if (parsed != null) {
            sum += parsed;
            any = true;
          }
        }
      }
      if (any) return sum;
    }
    return null;
  }
}
