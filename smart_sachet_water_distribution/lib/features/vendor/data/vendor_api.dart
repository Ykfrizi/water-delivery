import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';

String _seg(dynamic id) => apiPathSegment(id);

/// Authenticated vendor routes (handoff §3).
class VendorApi {
  VendorApi(this._dio);

  final Dio _dio;

  Options _auth(String token, {bool multipart = false}) => Options(
    headers: {'Authorization': 'Bearer $token'},
    // Longer timeouts when uploading product images.
    sendTimeout: multipart
        ? const Duration(minutes: 2)
        : const Duration(seconds: 30),
    receiveTimeout: multipart
        ? const Duration(minutes: 2)
        : const Duration(seconds: 60),
  );

  Future<Map<String, dynamic>> getProfile(String token) async {
    final r = await _dio.get<dynamic>('/vendor/profile', options: _auth(token));
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<List<Map<String, dynamic>>> listReviews(
    String token, {
    int perPage = 30,
  }) async {
    final r = await _dio.get<dynamic>(
      '/vendor/reviews',
      queryParameters: {'per_page': perPage},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data);
  }

  Future<Map<String, dynamic>> updateProfile(
    String token,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.put<dynamic>(
      '/vendor/profile',
      data: body,
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<List<Map<String, dynamic>>> listProducts(
    String token, {
    int perPage = 100,
  }) async {
    try {
      final r = await _dio.get<dynamic>(
        '/vendor/products',
        queryParameters: {'per_page': perPage},
        options: _auth(token),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      var rows = productsFromPayload(r.data);
      // Fallback: products embedded on vendor profile.
      if (rows.isEmpty) {
        try {
          final profile = await getProfile(token);
          rows = productsFromPayload(profile);
        } catch (_) {
          /* keep empty */
        }
      }
      return rows;
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<Map<String, dynamic>> createProduct(
    String token,
    Map<String, dynamic> body, {
    List<String> imagePaths = const [],
  }) async {
    try {
      final payload = await _productPayload(body, imagePaths: imagePaths);
      final r = await _dio.post<dynamic>(
        '/vendor/products',
        data: payload,
        options: _auth(token, multipart: payload is FormData),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<Map<String, dynamic>> updateProduct(
    String token,
    dynamic productId,
    Map<String, dynamic> body, {
    List<String> imagePaths = const [],
  }) async {
    try {
      final path = '/vendor/products/${_seg(productId)}';
      final payload = await _productPayload(body, imagePaths: imagePaths);
      final multipart = payload is FormData;

      // PHP/Laravel often cannot parse multipart bodies on PATCH/PUT — use
      // POST + _method spoofing when uploading images.
      if (multipart) {
        (payload).fields.add(const MapEntry('_method', 'PATCH'));
        final r = await _dio.post<dynamic>(
          path,
          data: payload,
          options: _auth(token, multipart: true),
        );
        if (!isSuccess(r)) throwApiResponse(r);
        return unwrapDataMap(r.data);
      }

      var r = await _dio.patch<dynamic>(
        path,
        data: payload,
        options: _auth(token),
      );
      if ((r.statusCode ?? 0) == 404 || (r.statusCode ?? 0) == 405) {
        r = await _dio.put<dynamic>(path, data: payload, options: _auth(token));
      }
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<Object> _productPayload(
    Map<String, dynamic> body, {
    List<String> imagePaths = const [],
  }) async {
    final paths = imagePaths.where((p) => p.trim().isNotEmpty).toList();
    if (paths.isEmpty) {
      return body;
    }

    final form = FormData();
    for (final e in body.entries) {
      _addFormField(form, e.key, e.value);
    }

    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      final name = path.split(RegExp(r'[\\/]')).last;
      final file = await MultipartFile.fromFile(
        path,
        filename: name.isEmpty ? 'image_$i.jpg' : name,
      );
      form.files.add(MapEntry('images[]', file));
      // Many Laravel apps also validate a singular `image` field.
      if (i == 0) {
        form.files.add(
          MapEntry(
            'image',
            await MultipartFile.fromFile(
              path,
              filename: name.isEmpty ? 'image.jpg' : name,
            ),
          ),
        );
      }
    }
    return form;
  }

  void _addFormField(FormData form, String key, dynamic value) {
    if (value == null) return;
    if (value is Iterable && value is! String) {
      var i = 0;
      for (final item in value) {
        if (item == null) continue;
        form.fields.add(MapEntry('$key[$i]', item.toString()));
        i++;
      }
      return;
    }
    form.fields.add(MapEntry(key, value.toString()));
  }

  Future<void> deleteProduct(String token, dynamic productId) async {
    try {
      final r = await _dio.delete<dynamic>(
        '/vendor/products/${_seg(productId)}',
        options: _auth(token),
      );
      if (!isSuccess(r) && (r.statusCode ?? 0) != 204) {
        throwApiResponse(r);
      }
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> listZones(String token) async {
    final r = await _dio.get<dynamic>(
      '/vendor/delivery-zones',
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data);
  }

  Future<Map<String, dynamic>> createZone(
    String token,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.post<dynamic>(
      '/vendor/delivery-zones',
      data: body,
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<Map<String, dynamic>> updateZone(
    String token,
    dynamic zoneId,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.patch<dynamic>(
      '/vendor/delivery-zones/${_seg(zoneId)}',
      data: body,
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<void> deleteZone(String token, dynamic zoneId) async {
    final r = await _dio.delete<dynamic>(
      '/vendor/delivery-zones/${_seg(zoneId)}',
      options: _auth(token),
    );
    if (!isSuccess(r) && (r.statusCode ?? 0) != 204) {
      throwApiResponse(r);
    }
  }

  Future<List<Map<String, dynamic>>> listOrders(
    String token, {
    String? status,
    String? from,
    String? to,
    int perPage = 40,
  }) async {
    final r = await _dio.get<dynamic>(
      '/vendor/orders',
      queryParameters: <String, dynamic>{
        'per_page': perPage,
        if (status != null && status.isNotEmpty) 'status': status,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data);
  }

  Future<Map<String, dynamic>> getOrder(
    String token,
    String orderNumber,
  ) async {
    final r = await _dio.get<dynamic>(
      '/vendor/orders/${_seg(orderNumber)}',
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<Map<String, dynamic>> patchOrder(
    String token,
    String orderNumber,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.patch<dynamic>(
      '/vendor/orders/${_seg(orderNumber)}',
      data: body,
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  /// Accept a pending order. Backend allows only `confirmed` (approve).
  Future<Map<String, dynamic>> approveOrder(String token, String orderNumber) {
    return patchOrder(token, orderNumber, {'status': 'confirmed'});
  }

  /// Decline a pending order. Backend allows only `cancelled` (reject).
  Future<Map<String, dynamic>> rejectOrder(
    String token,
    String orderNumber, {
    String? reason,
  }) {
    return patchOrder(token, orderNumber, {
      'status': 'cancelled',
      if (reason != null && reason.isNotEmpty) 'rejection_reason': reason,
    });
  }

  /// POST /vendor/location — live GPS for the operations map.
  Future<Map<String, dynamic>> updateLiveLocation(
    String token, {
    required double latitude,
    required double longitude,
  }) async {
    final r = await _dio.post<dynamic>(
      '/vendor/location',
      data: {
        'latitude': latitude,
        'longitude': longitude,
      },
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  /// Publish courier GPS while delivering (for customer live map).
  Future<Map<String, dynamic>> updateCourierLocation(
    String token,
    String orderNumber, {
    required double latitude,
    required double longitude,
  }) async {
    try {
      final r = await _dio.post<dynamic>(
        '/vendor/orders/${_seg(orderNumber)}/location',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'courier_latitude': latitude,
          'courier_longitude': longitude,
        },
        options: _auth(token),
      );
      if (isSuccess(r)) return unwrapDataMap(r.data);
    } catch (_) {}
    return patchOrder(token, orderNumber, {
      'courier_latitude': latitude,
      'courier_longitude': longitude,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// GET /vendor/wallet — Paystack earnings minus pending/paid withdrawals.
  Future<Map<String, dynamic>> getWallet(String token) async {
    final r = await _dio.get<dynamic>('/vendor/wallet', options: _auth(token));
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  /// GET /vendor/withdrawals
  Future<List<Map<String, dynamic>>> listWithdrawals(
    String token, {
    int perPage = 40,
  }) async {
    final r = await _dio.get<dynamic>(
      '/vendor/withdrawals',
      queryParameters: {'per_page': perPage},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data);
  }

  /// POST /vendor/withdrawals — bank or MoMo payout request.
  Future<Map<String, dynamic>> requestWithdrawal(
    String token, {
    required double amount,
    required String method,
    String? bankName,
    String? accountName,
    String? accountNumber,
    String? momoNetwork,
    String? momoNumber,
    String? momoName,
  }) async {
    final r = await _dio.post<dynamic>(
      '/vendor/withdrawals',
      data: {
        'amount': amount,
        'method': method,
        if (bankName != null && bankName.isNotEmpty) 'bank_name': bankName,
        if (accountName != null && accountName.isNotEmpty)
          'account_name': accountName,
        if (accountNumber != null && accountNumber.isNotEmpty)
          'account_number': accountNumber,
        if (momoNetwork != null && momoNetwork.isNotEmpty)
          'momo_network': momoNetwork,
        if (momoNumber != null && momoNumber.isNotEmpty)
          'momo_number': momoNumber,
        if (momoName != null && momoName.isNotEmpty) 'momo_name': momoName,
      },
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  /// Temporary public page a rider can open without the app.
  Future<Map<String, dynamic>> createDeliveryLink(
    String token,
    String orderNumber,
  ) async {
    final r = await _dio.post<dynamic>(
      '/vendor/orders/${_seg(orderNumber)}/delivery-link',
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }
}
