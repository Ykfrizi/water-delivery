import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/core/pagination/paginated_result.dart';

/// Authenticated customer routes (handoff §2).
class CustomerApi {
  CustomerApi(this._dio);

  final Dio _dio;

  Options _auth(String token, {Duration? receiveTimeout}) => Options(
    headers: {'Authorization': 'Bearer $token'},
    receiveTimeout: receiveTimeout,
    sendTimeout: receiveTimeout,
  );

  Future<Map<String, dynamic>> getCart(String token) async {
    try {
      final r = await _dio.get<dynamic>(
        '/customer/cart',
        options: _auth(token),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<Map<String, dynamic>> addCartItem(
    String token, {
    required int productId,
    required int quantity,
  }) async {
    try {
      final r = await _dio.post<dynamic>(
        '/customer/cart/items',
        data: {'product_id': productId, 'quantity': quantity},
        options: _auth(token),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<Map<String, dynamic>> updateCartItem(
    String token,
    int cartItemId, {
    required int quantity,
  }) async {
    try {
      final r = await _dio.patch<dynamic>(
        '/customer/cart/items/$cartItemId',
        data: {'quantity': quantity},
        options: _auth(token),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<void> removeCartItem(String token, int cartItemId) async {
    try {
      final r = await _dio.delete<dynamic>(
        '/customer/cart/items/$cartItemId',
        options: _auth(token),
      );
      if (!isSuccess(r) && (r.statusCode ?? 0) != 204) {
        throwApiResponse(r);
      }
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<void> clearCart(String token) async {
    try {
      final r = await _dio.delete<dynamic>(
        '/customer/cart',
        options: _auth(token),
      );
      if (!isSuccess(r) && (r.statusCode ?? 0) != 204) {
        throwApiResponse(r);
      }
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<Map<String, dynamic>> checkout(
    String token, {
    String? notes,
    String? phone,
    Map<String, dynamic>? shippingAddress,
    double? latitude,
    double? longitude,
    String paymentMethod = 'paystack',
    String? voucherCode,
    String? callbackUrl,
    num? deliveryFee,
    num? serviceFee,
    double? vendorCommissionRate,
    double? adminDeliveryShareRate,
    double? riderDeliveryShareRate,
  }) async {
    final enrichedAddress = shippingAddress == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(shippingAddress);
    if (latitude != null) enrichedAddress['latitude'] = latitude;
    if (longitude != null) enrichedAddress['longitude'] = longitude;
    final trimmedPhone = phone?.trim();
    if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
      enrichedAddress['phone'] = trimmedPhone;
    }

    final method = paymentMethod.trim().toLowerCase();
    final isCod =
        method == 'cash_on_delivery' ||
        method == 'pay_on_delivery' ||
        method == 'cod' ||
        method == 'pod';

    final body = <String, dynamic>{
      if (kPaymentCurrency.isNotEmpty) 'currency': kPaymentCurrency,
      'payment_method': isCod ? 'cash_on_delivery' : 'paystack',
      if (isCod) ...{
        'payment_provider': 'cash_on_delivery',
        'pay_on_delivery': true,
      },
      if (!isCod) 'payment_provider': 'paystack',
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (trimmedPhone != null && trimmedPhone.isNotEmpty)
        'phone': trimmedPhone,
      if (voucherCode != null && voucherCode.trim().isNotEmpty)
        'voucher_code': voucherCode.trim(),
      if (deliveryFee != null) 'delivery_fee': deliveryFee,
      if (serviceFee != null) 'service_fee': serviceFee,
      if (vendorCommissionRate != null)
        'vendor_commission_rate': vendorCommissionRate,
      if (adminDeliveryShareRate != null)
        'admin_delivery_share_rate': adminDeliveryShareRate,
      if (riderDeliveryShareRate != null)
        'rider_delivery_share_rate': riderDeliveryShareRate,
      if (enrichedAddress.isNotEmpty) 'shipping_address': enrichedAddress,
      'latitude': ?latitude,
      'longitude': ?longitude,
      if (latitude != null && longitude != null)
        'customer_location': {'latitude': latitude, 'longitude': longitude},
      if (!isCod && callbackUrl != null && callbackUrl.isNotEmpty) ...{
        'callback_url': callbackUrl,
        'callbackUrl': callbackUrl,
      },
    };
    try {
      final r = await _dio.post<dynamic>(
        '/customer/checkout',
        data: body,
        options: _auth(token, receiveTimeout: const Duration(seconds: 45)),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  /// POST /customer/payments/paystack/initialize
  ///
  /// Backend validates `order_numbers` as a required array (one checkout can
  /// create multiple vendor orders paid in a single Paystack session).
  Future<Map<String, dynamic>> initializePaystackPayment(
    String token, {
    required List<String> orderNumbers,
    String? callbackUrl,
  }) async {
    final numbers = orderNumbers
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    try {
      final r = await _dio.post<dynamic>(
        '/customer/payments/paystack/initialize',
        data: {
          'order_numbers': numbers,
          // Keep singular for older API builds that still expect it.
          if (numbers.length == 1) 'order_number': numbers.first,
          // Only send when explicitly configured — Paystack rejects currencies
          // that are not enabled on the merchant account.
          if (kPaymentCurrency.isNotEmpty) 'currency': kPaymentCurrency,
          // HTTPS return URL intercepted by the in-app checkout WebView.
          if (callbackUrl != null && callbackUrl.isNotEmpty) ...{
            'callback_url': callbackUrl,
            'callbackUrl': callbackUrl,
          },
        },
        options: _auth(token, receiveTimeout: const Duration(seconds: 45)),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  /// POST or GET /customer/payments/paystack/verify
  Future<Map<String, dynamic>> verifyPaystackPayment(
    String token, {
    required List<String> orderNumbers,
    String? reference,
  }) async {
    final numbers = orderNumbers
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    try {
      final r = await _dio.post<dynamic>(
        '/customer/payments/paystack/verify',
        data: {
          'order_numbers': numbers,
          if (numbers.length == 1) 'order_number': numbers.first,
          if (reference != null && reference.isNotEmpty) 'reference': reference,
        },
        options: _auth(token, receiveTimeout: const Duration(seconds: 45)),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> listOrders(
    String token, {
    int perPage = 30,
    int page = 1,
  }) async {
    final r = await _dio.get<dynamic>(
      '/customer/orders',
      queryParameters: {'per_page': perPage, 'page': page},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return decodeDataList(r.data);
  }

  /// Paginated orders with Laravel meta when present.
  Future<PaginatedResult<Map<String, dynamic>>> listOrdersPage(
    String token, {
    int perPage = 20,
    int page = 1,
  }) async {
    final r = await _dio.get<dynamic>(
      '/customer/orders',
      queryParameters: {'per_page': perPage, 'page': page},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return parsePaginatedMaps(
      r.data,
      page: page,
      perPage: perPage,
      decodeList: decodeDataList,
    );
  }

  Future<Map<String, dynamic>> getOrder(
    String token,
    String orderNumber,
  ) async {
    final r = await _dio.get<dynamic>(
      '/customer/orders/$orderNumber',
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  /// GET /customer/orders/{order}/tracking — courier GPS when available.
  Future<Map<String, dynamic>> getOrderTracking(
    String token,
    String orderNumber,
  ) async {
    final r = await _dio.get<dynamic>(
      '/customer/orders/$orderNumber/tracking',
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<Map<String, dynamic>> cancelOrder(
    String token,
    String orderNumber,
  ) async {
    final r = await _dio.patch<dynamic>(
      '/customer/orders/$orderNumber',
      data: {'status': 'cancelled'},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  /// Register for push notifications (optional backend endpoint).
  Future<void> registerDeviceToken(
    String token, {
    required String deviceToken,
    String platform = 'android',
  }) async {
    try {
      await _dio.post<dynamic>(
        '/customer/device-tokens',
        data: {
          'token': deviceToken,
          'device_token': deviceToken,
          'platform': platform,
        },
        options: _auth(token),
      );
    } catch (_) {}
  }

  /// POST /customer/vendors/{vendor}/reviews — [vendor] is slug (handoff).
  Future<Map<String, dynamic>> submitVendorReview(
    String token,
    String vendorSlug, {
    required int rating,
    String? comment,
  }) async {
    final r = await _dio.post<dynamic>(
      '/customer/vendors/$vendorSlug/reviews',
      data: {
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  /// POST /customer/location — live GPS for admin/vendor maps.
  Future<Map<String, dynamic>> updateLiveLocation(
    String token, {
    required double latitude,
    required double longitude,
  }) async {
    final r = await _dio.post<dynamic>(
      '/customer/location',
      data: {'latitude': latitude, 'longitude': longitude},
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  Future<Map<String, dynamic>> previewVoucher(
    String token, {
    required String code,
    num? subtotal,
  }) async {
    try {
      final r = await _dio.get<dynamic>(
        '/customer/vouchers/preview',
        queryParameters: {'code': code.trim(), 'subtotal': ?subtotal},
        options: _auth(token),
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<Map<String, dynamic>> getMe(String token) async {
    final r = await _dio.get<dynamic>('/customer/me', options: _auth(token));
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }

  /// PATCH /customer/me — adjust path/body if your Laravel routes differ.
  Future<Map<String, dynamic>> updateMe(
    String token,
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.patch<dynamic>(
      '/customer/me',
      data: body,
      options: _auth(token),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return unwrapDataMap(r.data);
  }
}
