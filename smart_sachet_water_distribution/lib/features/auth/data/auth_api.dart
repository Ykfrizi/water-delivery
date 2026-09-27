import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/auth_user.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';

class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> login({
    required UserRole role,
    required String email,
    required String password,
  }) async {
    final path = switch (role) {
      UserRole.customer => '/customer/auth/login',
      UserRole.vendor => '/vendor/auth/login',
      UserRole.admin => '/admin/auth/login',
    };
    final r = await _dio.post<dynamic>(path, data: {
      'email': email,
      'password': password,
    });
    if (!isSuccess(r)) throwApiResponse(r);
    return _asMap(r.data);
  }

  Future<Map<String, dynamic>> registerCustomer({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
  }) async {
    final r = await _dio.post<dynamic>(
      '/customer/auth/register',
      data: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'password_confirmation': passwordConfirmation,
      },
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return _asMap(r.data);
  }

  Future<Map<String, dynamic>> registerVendor({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String ghanaCardNumber,
    String? businessName,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
      'password_confirmation': passwordConfirmation,
      'ghana_card_number': ghanaCardNumber,
      'ghana_card': ghanaCardNumber,
    };
    final bn = businessName?.trim();
    if (bn != null && bn.isNotEmpty) {
      body['business_name'] = bn;
    }
    final r = await _dio.post<dynamic>('/vendor/auth/register', data: body);
    if (!isSuccess(r)) throwApiResponse(r);
    return _asMap(r.data);
  }

  Future<Map<String, dynamic>> completeVendorProfile({
    required String email,
    required String password,
    required String ghanaCardNumber,
    String? businessName,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'ghana_card_number': ghanaCardNumber,
    };
    final bn = businessName?.trim();
    if (bn != null && bn.isNotEmpty) {
      body['business_name'] = bn;
    }
    final r = await _dio.post<dynamic>(
      '/vendor/auth/complete-profile',
      data: body,
    );
    if (!isSuccess(r)) throwApiResponse(r);
    return _asMap(r.data);
  }

  Future<AuthUser> session({
    required UserRole role,
    required String token,
  }) async {
    final path = switch (role) {
      UserRole.customer => '/customer/me',
      UserRole.vendor => '/vendor/profile',
      UserRole.admin => '/admin/me',
    };
    final r = await _dio.get<dynamic>(
      path,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    if (!isSuccess(r)) throwApiResponse(r);
    final data = r.data;
    final map = _unwrapData(data);
    return AuthUser.fromJson(map);
  }

  Future<void> forgotPassword({
    required UserRole role,
    required String email,
  }) async {
    final path = switch (role) {
      UserRole.customer => '/customer/auth/forgot-password',
      UserRole.vendor => '/vendor/auth/forgot-password',
      UserRole.admin => '/admin/auth/forgot-password',
    };
    final smtpWait = Options(
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 20),
    );
    final r = await _dio.post<dynamic>(
      path,
      data: {'email': email},
      options: smtpWait,
    );
    if (!isSuccess(r)) throwApiResponse(r);
  }

  Future<void> resetPassword({
    required UserRole role,
    required String email,
    required String token,
    required String password,
    required String passwordConfirmation,
  }) async {
    final path = switch (role) {
      UserRole.customer => '/customer/auth/reset-password',
      UserRole.vendor => '/vendor/auth/reset-password',
      UserRole.admin => '/admin/auth/reset-password',
    };
    final r = await _dio.post<dynamic>(
      path,
      data: {
        'email': email,
        'token': token.replaceAll(RegExp(r'\D'), ''),
        'password': password,
        'password_confirmation': passwordConfirmation,
      },
    );
    if (!isSuccess(r)) throwApiResponse(r);
  }

  /// Registers a device for push (FCM / backend fan-out). Soft-fails if missing.
  Future<void> registerDeviceToken({
    required UserRole role,
    required String token,
    required String deviceToken,
    String platform = 'android',
  }) async {
    final path = switch (role) {
      UserRole.customer => '/customer/device-tokens',
      UserRole.vendor => '/vendor/device-tokens',
      UserRole.admin => '/admin/device-tokens',
    };
    try {
      await _dio.post<dynamic>(
        path,
        data: {
          'token': deviceToken,
          'device_token': deviceToken,
          'platform': platform,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {
      // Optional endpoint — ignore until backend ships push.
    }
  }

  Future<void> logout({
    required UserRole role,
    required String token,
  }) async {
    final path = switch (role) {
      UserRole.customer => '/customer/auth/logout',
      UserRole.vendor => '/vendor/auth/logout',
      UserRole.admin => '/admin/auth/logout',
    };
    final r = await _dio.post<dynamic>(
      path,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    if (!isSuccess(r) && (r.statusCode ?? 0) != 204) {
      throwApiResponse(r);
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Map<String, dynamic> _unwrapData(dynamic data) {
    final m = _asMap(data);
    final inner = m['data'];
    if (inner is Map) {
      return Map<String, dynamic>.from(inner);
    }
    return m;
  }
}

String? extractBearerToken(Map<String, dynamic> json) {
  final direct = json['token'];
  if (direct is String && direct.isNotEmpty) return direct;
  final inner = json['data'];
  if (inner is Map) {
    final t = inner['token'];
    if (t is String && t.isNotEmpty) return t;
  }
  final access = json['access_token'];
  if (access is String && access.isNotEmpty) return access;
  return null;
}
