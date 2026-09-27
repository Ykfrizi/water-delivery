import 'dart:async';

import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/auth_api.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/token_storage.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/auth_user.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';

class AuthSession {
  const AuthSession({required this.role, required this.token, required this.user});

  final UserRole role;
  final String token;
  final AuthUser user;
}

class AuthRepository {
  AuthRepository({
    required AuthApi api,
    required TokenStorage storage,
  })  : _api = api,
        _storage = storage;

  final AuthApi _api;
  final TokenStorage _storage;

  /// Returns null if there is no token, session is invalid (401), or the network fails.
  Future<AuthSession?> restoreSession(UserRole role) async {
    final token = await _storage.read(role);
    if (token == null || token.isEmpty) return null;
    try {
      final user = await _api
          .session(role: role, token: token)
          .timeout(const Duration(seconds: 8));
      return AuthSession(role: role, token: token, user: user);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _storage.clear(role);
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Restores the first valid session found (typical: at most one persona logged in).
  Future<AuthSession?> restoreAnySession() async {
    for (final role in UserRole.values) {
      final s = await restoreSession(role);
      if (s != null) return s;
    }
    return null;
  }

  Future<AuthSession> login({
    required UserRole role,
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    try {
      return await _signInAs(
        role: role,
        email: trimmedEmail,
        password: password,
      );
    } on TimeoutException {
      throw _unreachableServer();
    } on DioException catch (e) {
      throwFromDio(e);
    } on ApiException catch (e) {
      if (role == UserRole.admin || !_isCredentialFailure(e)) {
        rethrow;
      }
      try {
        return await _signInAs(
          role: UserRole.admin,
          email: trimmedEmail,
          password: password,
        );
      } on TimeoutException {
        throw _unreachableServer();
      } on DioException catch (e2) {
        throwFromDio(e2);
      } on ApiException {
        throw e;
      }
    }
  }

  Future<AuthSession> _signInAs({
    required UserRole role,
    required String email,
    required String password,
  }) async {
    final body = await _api
        .login(
          role: role,
          email: email,
          password: password,
        )
        .timeout(const Duration(seconds: 12));
    final token = extractBearerToken(body);
    if (token == null || token.isEmpty) {
      throw ApiException(
        message: 'Login succeeded but no token was returned.',
        statusCode: null,
      );
    }
    await _storage.write(role, token);
    final user = await _api
        .session(role: role, token: token)
        .timeout(const Duration(seconds: 12));
    return AuthSession(role: role, token: token, user: user);
  }

  static bool _isCredentialFailure(ApiException e) {
    return e.statusCode == 401 || e.statusCode == 422;
  }

  static ApiException _unreachableServer() {
    return ApiException(
      message:
          'Cannot reach the server. Check Wi‑Fi and that the API is running.',
      statusCode: null,
    );
  }

  Future<AuthSession> registerCustomer({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final body = await _api.registerCustomer(
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
      final token = extractBearerToken(body);
      if (token == null || token.isEmpty) {
        throw ApiException(
          message: 'Registration succeeded but no token was returned.',
          statusCode: null,
        );
      }
      const role = UserRole.customer;
      await _storage.write(role, token);
      final user = await _api.session(role: role, token: token);
      return AuthSession(role: role, token: token, user: user);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<AuthSession> registerVendor({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String ghanaCardNumber,
    String? businessName,
  }) async {
    try {
      final body = await _api.registerVendor(
        name: name.trim(),
        email: email.trim(),
        password: password,
        passwordConfirmation: passwordConfirmation,
        ghanaCardNumber: AuthValidators.normalizeGhanaCard(ghanaCardNumber),
        businessName: businessName,
      );
      final token = extractBearerToken(body);
      if (token == null || token.isEmpty) {
        throw ApiException(
          message: 'Registration succeeded but no token was returned.',
          statusCode: null,
        );
      }
      const role = UserRole.vendor;
      await _storage.write(role, token);
      var user = await _api.session(role: role, token: token);
      // New vendors default to pending until admin approves.
      if (user.approvalStatus == 'unknown') {
        user = AuthUser(
          id: user.id,
          name: user.name,
          email: user.email,
          extra: {
            ...user.extra,
            'approval_status': 'pending',
            'ghana_card_number':
                AuthValidators.normalizeGhanaCard(ghanaCardNumber),
          },
        );
      }
      return AuthSession(role: role, token: token, user: user);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<AuthSession> completeVendorProfile({
    required String email,
    required String password,
    required String ghanaCardNumber,
    String? businessName,
  }) async {
    try {
      final card = AuthValidators.normalizeGhanaCard(ghanaCardNumber);
      final body = await _api.completeVendorProfile(
        email: email.trim(),
        password: password,
        ghanaCardNumber: card,
        businessName: businessName,
      );
      final token = extractBearerToken(body);
      if (token == null || token.isEmpty) {
        throw ApiException(
          message: 'Profile saved but no token was returned.',
          statusCode: null,
        );
      }
      const role = UserRole.vendor;
      await _storage.write(role, token);
      var user = await _api.session(role: role, token: token);
      if (user.approvalStatus == 'unknown') {
        user = AuthUser(
          id: user.id,
          name: user.name,
          email: user.email,
          extra: {
            ...user.extra,
            'approval_status': 'pending',
            'ghana_card_number': card,
          },
        );
      }
      return AuthSession(role: role, token: token, user: user);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<void> logout(AuthSession session) async {
    try {
      await _api.logout(role: session.role, token: session.token);
    } on DioException catch (_) {
      // Still clear local token if network fails
    } finally {
      await _storage.clear(session.role);
    }
  }

  Future<void> forgotPassword({
    required UserRole role,
    required String email,
  }) async {
    try {
      await _api.forgotPassword(role: role, email: email);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<void> resetPassword({
    required UserRole role,
    required String email,
    required String token,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      await _api.resetPassword(
        role: role,
        email: email,
        token: token,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }
}
