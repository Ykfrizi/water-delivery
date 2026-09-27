import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_vendor_summary.dart';

String _seg(dynamic id) => apiPathSegment(id);

/// Admin vendor approval — GET/PATCH /admin/vendors (handoff extension).
class AdminVendorsApi {
  AdminVendorsApi(this._dio);

  final Dio _dio;

  Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<List<AdminVendorSummary>> listVendors(
    String token, {
    String? approvalStatus,
    String? q,
    int perPage = 50,
  }) async {
    final qParams = <String, dynamic>{
      'per_page': perPage,
      if (approvalStatus != null && approvalStatus.isNotEmpty)
        'approval_status': approvalStatus,
      if (approvalStatus != null && approvalStatus.isNotEmpty)
        'status': approvalStatus,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    };

    final r = await _dio.get<dynamic>(
      '/admin/vendors',
      queryParameters: qParams,
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data).map(AdminVendorSummary.fromJson).toList();
  }

  Future<Map<String, dynamic>> getVendor(String token, String vendorSlug) async {
    final r = await _dio.get<dynamic>(
      '/admin/vendors/${_seg(vendorSlug)}',
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<Map<String, dynamic>> patchVendor(
    String token,
    String vendorSlug,
    Map<String, dynamic> body,
  ) async {
    final path = '/admin/vendors/${_seg(vendorSlug)}';
    var r = await _dio.patch<dynamic>(
      path,
      data: body,
      options: _auth(token),
    );
    if ((r.statusCode ?? 0) == 404 || (r.statusCode ?? 0) == 405) {
      r = await _dio.put<dynamic>(
        path,
        data: body,
        options: _auth(token),
      );
    }
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<Map<String, dynamic>> approveVendor(String token, String vendorSlug) {
    return patchVendor(token, vendorSlug, {
      'approval_status': 'approved',
      'status': 'approved',
      'is_approved': true,
      'is_active': 1,
      'active': 1,
    });
  }

  Future<Map<String, dynamic>> rejectVendor(String token, String vendorSlug) {
    return patchVendor(token, vendorSlug, {
      'approval_status': 'rejected',
      'status': 'rejected',
      'is_approved': false,
      'is_active': 0,
      'active': 0,
    });
  }
}
