import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';

class AdminMoneyApi {
  AdminMoneyApi(this._dio);

  final Dio _dio;

  Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<List<Map<String, dynamic>>> listPayments(
    String token, {
    int perPage = 50,
  }) async {
    final r = await _dio.get<dynamic>(
      '/admin/payments',
      queryParameters: {'per_page': perPage},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data);
  }

  Future<List<Map<String, dynamic>>> listWithdrawals(
    String token, {
    String? status,
    int perPage = 50,
  }) async {
    final r = await _dio.get<dynamic>(
      '/admin/withdrawals',
      queryParameters: {
        'per_page': perPage,
        if (status != null && status.isNotEmpty) 'status': status,
      },
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data);
  }

  Future<Map<String, dynamic>> completeWithdrawal(
    String token,
    dynamic id, {
    String? notes,
  }) async {
    final r = await _dio.post<dynamic>(
      '/admin/withdrawals/${apiPathSegment(id)}/complete',
      data: {
        if (notes != null && notes.trim().isNotEmpty) 'admin_notes': notes.trim(),
      },
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<Map<String, dynamic>> rejectWithdrawal(
    String token,
    dynamic id, {
    String? notes,
  }) async {
    final r = await _dio.post<dynamic>(
      '/admin/withdrawals/${apiPathSegment(id)}/reject',
      data: {
        if (notes != null && notes.trim().isNotEmpty) 'admin_notes': notes.trim(),
      },
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }
}
