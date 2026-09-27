import 'package:smart_sachet_water_distribution/core/money/currency.dart';

enum VendorReportPeriod { today, week, month, all }

extension VendorReportPeriodX on VendorReportPeriod {
  String get label => switch (this) {
        VendorReportPeriod.today => 'Today',
        VendorReportPeriod.week => 'This week',
        VendorReportPeriod.month => 'This month',
        VendorReportPeriod.all => 'All time',
      };

  DateTime? get from {
    final now = DateTime.now();
    return switch (this) {
      VendorReportPeriod.today => DateTime(now.year, now.month, now.day),
      VendorReportPeriod.week => DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6)),
      VendorReportPeriod.month => DateTime(now.year, now.month, 1),
      VendorReportPeriod.all => null,
    };
  }

  String? get apiFrom {
    final d = from;
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

class VendorReportSlice {
  const VendorReportSlice({
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

class VendorPaystackPayment {
  const VendorPaystackPayment({
    required this.reference,
    required this.status,
    required this.amount,
    required this.at,
    required this.orderLabel,
  });

  final String reference;
  final String status;
  final num? amount;
  final DateTime? at;
  final String orderLabel;

  String get amountLabel => formatMoney(amount, currency: kAppCurrency);
}

/// Store operations report built from vendor orders, catalog, and zones.
class VendorOperationsReport {
  const VendorOperationsReport({
    required this.period,
    required this.generatedAt,
    required this.totalOrders,
    required this.pendingApprovals,
    required this.pipelineOrders,
    required this.deliveredOrders,
    required this.cancelledOrders,
    required this.outForDelivery,
    required this.estimatedRevenue,
    required this.productCount,
    required this.zoneCount,
    required this.ordersByStatus,
    required this.ordersByPayment,
    required this.ordersByDay,
    required this.paystackStatus,
    required this.paystackPaidCount,
    required this.paystackPaidAmount,
    required this.paystackPendingCount,
    required this.recentPaystack,
  });

  final VendorReportPeriod period;
  final DateTime generatedAt;
  final int totalOrders;
  final int pendingApprovals;
  final int pipelineOrders;
  final int deliveredOrders;
  final int cancelledOrders;
  final int outForDelivery;
  final num estimatedRevenue;
  final int productCount;
  final int zoneCount;
  final List<VendorReportSlice> ordersByStatus;
  final List<VendorReportSlice> ordersByPayment;
  final List<VendorReportSlice> ordersByDay;
  final List<VendorReportSlice> paystackStatus;
  final int paystackPaidCount;
  final num paystackPaidAmount;
  final int paystackPendingCount;
  final List<VendorPaystackPayment> recentPaystack;

  String get revenueLabel =>
      formatMoney(estimatedRevenue, currency: kAppCurrency);

  String get paystackPaidLabel =>
      formatMoney(paystackPaidAmount, currency: kAppCurrency);

  factory VendorOperationsReport.fromData({
    required List<Map<String, dynamic>> orders,
    required int productCount,
    required int zoneCount,
    VendorReportPeriod period = VendorReportPeriod.all,
    DateTime? now,
  }) {
    final generatedAt = now ?? DateTime.now();
    final scoped = orders.where((o) {
      if (!_inPeriod(o, period, generatedAt)) return false;
      if (_isCancelled(o)) return false;
      return _isPaid(o);
    }).toList();

    final statusCounts = <String, int>{};
    final statusAmounts = <String, num>{};
    final payCounts = <String, int>{};
    final payAmounts = <String, num>{};
    final dayCounts = <String, int>{};
    final dayAmounts = <String, num>{};
    final stackStatusCounts = <String, int>{};
    final stackStatusAmounts = <String, num>{};
    final recent = <VendorPaystackPayment>[];
    var pending = 0;
    var pipeline = 0;
    var delivered = 0;
    var cancelled = 0;
    var out = 0;
    num revenue = 0;
    var paystackPaidCount = 0;
    num paystackPaidAmount = 0;
    var paystackPendingCount = 0;

    for (final raw in scoped) {
      final status =
          (raw['status']?.toString() ?? 'unknown').toLowerCase().trim();
      final bucket = _statusBucket(status);
      statusCounts[bucket] = (statusCounts[bucket] ?? 0) + 1;

      final amount = _orderAmount(raw);
      if (amount != null) {
        statusAmounts[bucket] = (statusAmounts[bucket] ?? 0) + amount;
        if (bucket != 'Cancelled' && _isPaid(raw)) revenue += amount;
      }

      if (bucket == 'Needs approval') pending++;
      if (bucket == 'Preparing' || bucket == 'Out for delivery') pipeline++;
      if (bucket == 'Delivered') delivered++;
      if (bucket == 'Cancelled') cancelled++;
      if (bucket == 'Out for delivery') out++;

      final pay = _paymentMethodLabel(raw);
      payCounts[pay] = (payCounts[pay] ?? 0) + 1;
      if (amount != null) {
        payAmounts[pay] = (payAmounts[pay] ?? 0) + amount;
      }

      final placed = _orderDate(raw);
      final dayKey = placed == null ? 'No date' : _dayLabel(placed);
      dayCounts[dayKey] = (dayCounts[dayKey] ?? 0) + 1;
      if (amount != null) {
        dayAmounts[dayKey] = (dayAmounts[dayKey] ?? 0) + amount;
      }

      if (_isPaystack(raw)) {
        final pStatus = _paystackStatusLabel(raw);
        stackStatusCounts[pStatus] = (stackStatusCounts[pStatus] ?? 0) + 1;
        if (amount != null) {
          stackStatusAmounts[pStatus] =
              (stackStatusAmounts[pStatus] ?? 0) + amount;
        }
        if (pStatus == 'Paid') {
          paystackPaidCount++;
          paystackPaidAmount += amount ?? 0;
        } else if (pStatus != 'Failed') {
          paystackPendingCount++;
        }
        recent.add(
          VendorPaystackPayment(
            reference: _paystackReference(raw) ?? 'No reference',
            status: pStatus,
            amount: amount,
            at: _paidAt(raw) ?? placed,
            orderLabel: _orderLabel(raw),
          ),
        );
      }
    }

    recent.sort((a, b) {
      final at = a.at;
      final bt = b.at;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    List<VendorReportSlice> slices(
      Map<String, int> counts, {
      Map<String, num>? amounts,
    }) {
      final items = counts.entries
          .map(
            (e) => VendorReportSlice(
              label: e.key,
              count: e.value,
              amount: amounts?[e.key],
            ),
          )
          .toList()
        ..sort((a, b) => b.count.compareTo(a.count));
      return items;
    }

    final daySlices = dayCounts.entries
        .map(
          (e) => VendorReportSlice(
            label: e.key,
            count: e.value,
            amount: dayAmounts[e.key],
          ),
        )
        .toList()
      ..sort((a, b) {
        if (a.label == 'No date') return 1;
        if (b.label == 'No date') return -1;
        return b.label.compareTo(a.label);
      });

    return VendorOperationsReport(
      period: period,
      generatedAt: generatedAt,
      totalOrders: scoped.length,
      pendingApprovals: pending,
      pipelineOrders: pipeline,
      deliveredOrders: delivered,
      cancelledOrders: cancelled,
      outForDelivery: out,
      estimatedRevenue: revenue,
      productCount: productCount,
      zoneCount: zoneCount,
      ordersByStatus: slices(statusCounts, amounts: statusAmounts),
      ordersByPayment: slices(payCounts, amounts: payAmounts),
      ordersByDay: daySlices.take(14).toList(),
      paystackStatus: slices(stackStatusCounts, amounts: stackStatusAmounts),
      paystackPaidCount: paystackPaidCount,
      paystackPaidAmount: paystackPaidAmount,
      paystackPendingCount: paystackPendingCount,
      recentPaystack: recent.take(8).toList(),
    );
  }

  static bool _isCancelled(Map<String, dynamic> raw) {
    final status =
        (raw['status']?.toString() ?? '').toLowerCase().trim();
    return status == 'cancelled' ||
        status == 'canceled' ||
        status == 'rejected';
  }

  static bool _isPaid(Map<String, dynamic> raw) {
    final nested = _paymentMap(raw);
    final v = (raw['payment_status'] ?? nested?['status'])
        ?.toString()
        .toLowerCase()
        .trim();
    if (raw['paid_at'] != null || nested?['paid_at'] != null) return true;
    return v == 'paid' || v == 'success' || v == 'successful' || v == 'completed';
  }

  static bool _inPeriod(
    Map<String, dynamic> raw,
    VendorReportPeriod period,
    DateTime now,
  ) {
    if (period == VendorReportPeriod.all) return true;
    final at = _orderDate(raw);
    if (at == null) return false;
    final start = period.from!;
    return !at.isBefore(start) && !at.isAfter(now);
  }

  static String _statusBucket(String status) {
    if (status.isEmpty ||
        status == 'pending' ||
        status == 'awaiting_approval' ||
        status == 'awaiting_vendor' ||
        status == 'new') {
      return 'Needs approval';
    }
    if (status == 'processing' ||
        status == 'confirmed' ||
        status == 'accepted' ||
        status == 'approved' ||
        status == 'preparing') {
      return 'Preparing';
    }
    if (status == 'shipped' || status == 'out_for_delivery') {
      return 'Out for delivery';
    }
    if (status == 'delivered') return 'Delivered';
    if (status == 'cancelled' || status == 'canceled' || status == 'rejected') {
      return 'Cancelled';
    }
    return status[0].toUpperCase() + status.substring(1);
  }

  static Map<String, dynamic>? _paymentMap(Map<String, dynamic> raw) {
    final p = raw['payment'];
    return p is Map<String, dynamic> ? p : null;
  }

  static String _joinedPaymentText(Map<String, dynamic> raw) {
    final nested = _paymentMap(raw);
    return [
      raw['payment_method'],
      raw['payment_provider'],
      raw['paid_with'],
      raw['gateway'],
      nested?['method'],
      nested?['provider'],
      nested?['gateway'],
      nested?['channel'],
    ].where((e) => e != null).map((e) => e.toString().toLowerCase()).join(' ');
  }

  static bool _isPaystack(Map<String, dynamic> raw) {
    final text = _joinedPaymentText(raw);
    if (text.contains('paystack') ||
        text.contains('card') ||
        text.contains('online')) {
      return true;
    }
    return _paystackReference(raw) != null;
  }

  static String _paymentMethodLabel(Map<String, dynamic> raw) {
    final text = _joinedPaymentText(raw);
    if (text.contains('cash') ||
        text.contains('cod') ||
        text.contains('pod') ||
        text.contains('delivery')) {
      return 'Pay on delivery';
    }
    if (_isPaystack(raw)) return 'Paystack';
    if (text.trim().isEmpty) return 'Unspecified';
    final first = text.trim().split(RegExp(r'\s+')).first;
    return first[0].toUpperCase() + first.substring(1);
  }

  static String _paystackStatusLabel(Map<String, dynamic> raw) {
    final nested = _paymentMap(raw);
    final v = (raw['payment_status'] ??
            nested?['status'] ??
            nested?['payment_status'])
        ?.toString()
        .toLowerCase()
        .trim();
    if (raw['paid_at'] != null || nested?['paid_at'] != null) {
      if (v == null ||
          v.isEmpty ||
          v == 'paid' ||
          v == 'success' ||
          v == 'successful' ||
          v == 'completed') {
        return 'Paid';
      }
    }
    if (v == 'paid' ||
        v == 'success' ||
        v == 'successful' ||
        v == 'completed') {
      return 'Paid';
    }
    if (v == 'failed' || v == 'abandoned' || v == 'reversed') return 'Failed';
    if (v == null || v.isEmpty || v == 'pending' || v == 'initialized') {
      return 'Pending';
    }
    return v[0].toUpperCase() + v.substring(1);
  }

  static String? _paystackReference(Map<String, dynamic> raw) {
    final nested = _paymentMap(raw);
    for (final v in [
      raw['payment_reference'],
      raw['paystack_reference'],
      raw['reference'],
      raw['trxref'],
      nested?['reference'],
      nested?['payment_reference'],
      nested?['trxref'],
    ]) {
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  static DateTime? _paidAt(Map<String, dynamic> raw) {
    final nested = _paymentMap(raw);
    return _parseDate(raw['paid_at']) ??
        _parseDate(nested?['paid_at']) ??
        _parseDate(nested?['paid_on']);
  }

  static DateTime? _orderDate(Map<String, dynamic> raw) {
    return _parseDate(raw['created_at']) ??
        _parseDate(raw['placed_at']) ??
        _parseDate(raw['ordered_at']) ??
        _parseDate(raw['updated_at']);
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  static String _dayLabel(DateTime d) {
    final local = d.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String _orderLabel(Map<String, dynamic> raw) {
    return (raw['order_number'] ??
            raw['number'] ??
            raw['id'] ??
            'Order')
        .toString();
  }

  static num? _orderAmount(Map<String, dynamic> raw) {
    final nested = _paymentMap(raw);
    for (final key in const [
      'total',
      'grand_total',
      'amount',
      'order_total',
      'payable_amount',
      'amount_paid',
    ]) {
      final v = raw[key] ?? nested?[key];
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
      }
    }
    return null;
  }
}

String formatReportDateTime(DateTime d) {
  final local = d.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year} · $h:$m';
}
