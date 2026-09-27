import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';

class AdminVouchersApi {
  AdminVouchersApi(this._dio);

  final Dio _dio;

  Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<List<Map<String, dynamic>>> list(String token) async {
    final r = await _dio.get<dynamic>(
      '/admin/vouchers',
      queryParameters: {'per_page': 50},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data);
  }

  Future<Map<String, dynamic>> create(
    String token, {
    required String code,
    required String type,
    required double value,
    int? maxUses,
    DateTime? expiresAt,
  }) async {
    final r = await _dio.post<dynamic>(
      '/admin/vouchers',
      data: {
        'code': code,
        'type': type,
        'value': value,
        'max_uses': ?maxUses,
        if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
        'is_active': true,
      },
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<Map<String, dynamic>> setActive(
    String token,
    dynamic id, {
    required bool active,
  }) async {
    final r = await _dio.patch<dynamic>(
      '/admin/vouchers/${apiPathSegment(id)}',
      data: {'is_active': active},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<void> delete(String token, dynamic id) async {
    final r = await _dio.delete<dynamic>(
      '/admin/vouchers/${apiPathSegment(id)}',
      options: _auth(token),
    );
    if (!isSuccess(r) && (r.statusCode ?? 0) != 204) {
      throwApiResponse(r);
    }
  }
}
