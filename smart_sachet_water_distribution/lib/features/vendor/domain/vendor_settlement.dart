import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/cart_line.dart';

class VendorSettlement {
  const VendorSettlement({
    required this.from,
    required this.to,
    required this.cashOrders,
    required this.cashSales,
    required this.prepaidOrders,
    required this.prepaidSales,
  });

  final DateTime from;
  final DateTime to;
  final int cashOrders;
  final num cashSales;
  final int prepaidOrders;
  final num prepaidSales;

  num get grossSales => cashSales + prepaidSales;
  num get commissionDue => vendorCommissionFor(grossSales);
  num get prepaidCommissionOffset => vendorCommissionFor(prepaidSales);
  num get cashCommissionDue => commissionDue - prepaidCommissionOffset;

  String get grossSalesLabel => formatMoney(grossSales);
  String get commissionDueLabel => formatMoney(commissionDue);
  String get cashCommissionDueLabel => formatMoney(cashCommissionDue);

  factory VendorSettlement.fromOrders(
    List<Map<String, dynamic>> orders, {
    DateTime? now,
  }) {
    final end = now ?? DateTime.now();
    final start = DateTime(end.year, end.month, end.day)
        .subtract(Duration(days: end.weekday - 1));
    var cashOrders = 0;
    num cashSales = 0;
    var prepaidOrders = 0;
    num prepaidSales = 0;

    for (final order in orders) {
      if (_cancelled(order) || !_paid(order)) continue;
      final amount = _amount(order);
      if (amount == null) continue;
      if (_isCash(order)) {
        cashOrders++;
        cashSales += amount;
      } else {
        prepaidOrders++;
        prepaidSales += amount;
      }
    }

    return VendorSettlement(
      from: start,
      to: end,
      cashOrders: cashOrders,
      cashSales: cashSales,
      prepaidOrders: prepaidOrders,
      prepaidSales: prepaidSales,
    );
  }

  static bool _cancelled(Map<String, dynamic> order) {
    final status = order['status']?.toString().toLowerCase().trim();
    return status == 'cancelled' || status == 'canceled' || status == 'rejected';
  }

  static bool _paid(Map<String, dynamic> order) {
    final payment = order['payment'];
    final nested = payment is Map ? payment : null;
    final status = (order['payment_status'] ?? nested?['status'])
        ?.toString()
        .toLowerCase()
        .trim();
    final method = (order['payment_method'] ?? nested?['method'])
        ?.toString()
        .toLowerCase()
        .trim();
    if (_isCashValue(method)) return true;
    return order['paid_at'] != null ||
        nested?['paid_at'] != null ||
        status == 'paid' ||
        status == 'success' ||
        status == 'successful' ||
        status == 'completed';
  }

  static bool _isCash(Map<String, dynamic> order) {
    final payment = order['payment'];
    final nested = payment is Map ? payment : null;
    final method = (order['payment_method'] ?? nested?['method'])
        ?.toString()
        .toLowerCase()
        .trim();
    return _isCashValue(method);
  }

  static bool _isCashValue(String? method) =>
      method == 'cash_on_delivery' ||
      method == 'cash' ||
      method == 'cod' ||
      method == 'pay_on_delivery' ||
      method == 'pod';

  static num? _amount(Map<String, dynamic> order) {
    final raw = order['total'] ??
        order['grand_total'] ??
        order['amount'] ??
        order['total_amount'];
    if (raw is num) return raw;
    return num.tryParse(raw?.toString() ?? '');
  }
}
