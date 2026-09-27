import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_orders_api.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_vendors_api.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_operations_report.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_order_summary.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_vendor_summary.dart';

/// Loads an operations report for the admin dashboard.
class AdminReportsApi {
  AdminReportsApi(this._dio);

  final Dio _dio;

  Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  /// Prefer a dedicated backend report when available; otherwise aggregate.
  Future<AdminOperationsReport> loadReport(String token) async {
    try {
      final r = await _dio.get<dynamic>(
        '/admin/reports',
        options: _auth(token),
      );
      if (isSuccess(r) && r.data != null) {
        final parsed = _tryParseBackendReport(r.data);
        if (parsed != null) return parsed;
      }
    } catch (_) {
      /* fall through to aggregation */
    }

    final ordersApi = AdminOrdersApi(_dio);
    final vendorsApi = AdminVendorsApi(_dio);

    final results = await Future.wait([
      ordersApi.listOrders(token, perPage: 200),
      vendorsApi.listVendors(token, perPage: 200),
    ]);

    final orders = results[0] as List<AdminOrderSummary>;
    final vendors = results[1] as List<AdminVendorSummary>;

    return AdminOperationsReport.fromData(
      orders: orders,
      vendors: vendors,
    );
  }

  AdminOperationsReport? _tryParseBackendReport(dynamic body) {
    Map<String, dynamic>? root;
    if (body is Map) {
      final m = Map<String, dynamic>.from(body);
      final data = m['data'];
      root = data is Map ? Map<String, dynamic>.from(data) : m;
    }
    if (root == null) return null;

    // If backend already returns order/vendor lists, reuse aggregation.
    final ordersRaw = root['orders'];
    final vendorsRaw = root['vendors'];
    if (ordersRaw is List || vendorsRaw is List) {
      final orders = (ordersRaw is List)
          ? ordersRaw
              .whereType<Map>()
              .map((e) => AdminOrderSummary.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <AdminOrderSummary>[];
      final vendors = (vendorsRaw is List)
          ? vendorsRaw
              .whereType<Map>()
              .map((e) => AdminVendorSummary.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <AdminVendorSummary>[];
      if (orders.isNotEmpty || vendors.isNotEmpty) {
        return AdminOperationsReport.fromData(
          orders: orders,
          vendors: vendors,
          sourceNote: '',
        );
      }
    }
    return null;
  }
}
