import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_order_summary.dart';

class AdminOrdersApi {
  AdminOrdersApi(this._dio);

  final Dio _dio;

  Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<List<AdminOrderSummary>> listOrders(
    String token, {
    String? status,
    String? from,
    String? to,
    String? vendorSlug,
    String? customerEmail,
    String? orderNumber,
    int perPage = 40,
  }) async {
    final q = <String, dynamic>{
      'per_page': perPage,
      if (status != null && status.isNotEmpty) 'status': status,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (vendorSlug != null && vendorSlug.isNotEmpty) 'vendor_slug': vendorSlug,
      if (customerEmail != null && customerEmail.isNotEmpty)
        'customer_email': customerEmail,
      if (orderNumber != null && orderNumber.isNotEmpty)
        'order_number': orderNumber,
    };
    final r = await _dio.get<dynamic>(
      '/admin/orders',
      queryParameters: q,
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    final rows = _decodeList(r.data);
    return rows.map(AdminOrderSummary.fromJson).toList();
  }

  Future<Map<String, dynamic>> getOrder(String token, String orderNumber) async {
    final r = await _dio.get<dynamic>(
      '/admin/orders/$orderNumber',
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return _unwrap(r.data);
  }

  Future<Map<String, dynamic>> patchOrder(
    String token,
    String orderNumber,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.patch<dynamic>(
      '/admin/orders/$orderNumber',
      data: body,
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    if (r.data == null) return {};
    return _unwrap(r.data);
  }

  /// Admin accepts a pending order into the fulfillment pipeline.
  Future<Map<String, dynamic>> approveOrder(
    String token,
    String orderNumber,
  ) {
    return patchOrder(token, orderNumber, {
      'status': 'processing',
      'admin_approved': true,
      'approved': true,
    });
  }

  /// Admin rejects / cancels a pending order.
  Future<Map<String, dynamic>> rejectOrder(
    String token,
    String orderNumber, {
    String? reason,
  }) {
    return patchOrder(token, orderNumber, {
      'status': 'cancelled',
      'admin_approved': false,
      'rejected': true,
      if (reason != null && reason.trim().isNotEmpty) 'notes': reason.trim(),
      if (reason != null && reason.trim().isNotEmpty)
        'cancellation_reason': reason.trim(),
    });
  }

  List<Map<String, dynamic>> _decodeList(dynamic body) {
    if (body is List) {
      return body.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (body is Map) {
      final m = Map<String, dynamic>.from(body);
      final data = m['data'];
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return [];
  }

  Map<String, dynamic> _unwrap(dynamic data) {
    if (data is Map<String, dynamic>) {
      final inner = data['data'];
      if (inner is Map) {
        return Map<String, dynamic>.from(inner);
      }
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }
}
