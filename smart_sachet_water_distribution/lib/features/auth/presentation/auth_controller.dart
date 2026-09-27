import 'package:flutter/widgets.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/auth_repository.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;

  AuthSession? session;
  bool bootstrapComplete = false;
  bool busy = false;

  String? get token => session?.token;

  /// Session sign-in/out rebuilds [MaterialApp]; defer so the current frame
  /// (button handlers, dialogs) can finish before the navigator is discarded.
  void _notifyBoundaryChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }

  Future<void> bootstrap() async {
    busy = true;
    try {
      session = await _repository.restoreAnySession();
    } catch (e) {
      debugPrint('Auth bootstrap: $e');
      session = null;
    } finally {
      bootstrapComplete = true;
      busy = false;
      if (hasListeners) notifyListeners();
    }
  }

  Future<void> login({
    required UserRole role,
    required String email,
    required String password,
  }) async {
    busy = true;
    notifyListeners();
    try {
      session = await _repository.login(
        role: role,
        email: email,
        password: password,
      );
      busy = false;
      _notifyBoundaryChange();
    } catch (e) {
      busy = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> registerCustomer({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
  }) async {
    busy = true;
    notifyListeners();
    try {
      session = await _repository.registerCustomer(
        name: name,
        email: email,
        phone: phone,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
      busy = false;
      _notifyBoundaryChange();
    } catch (e) {
      busy = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> registerVendor({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String ghanaCardNumber,
    String? businessName,
  }) async {
    busy = true;
    notifyListeners();
    try {
      session = await _repository.registerVendor(
        name: name,
        email: email,
        password: password,
        passwordConfirmation: passwordConfirmation,
        ghanaCardNumber: ghanaCardNumber,
        businessName: businessName,
      );
      busy = false;
      _notifyBoundaryChange();
    } catch (e) {
      busy = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> completeVendorProfile({
    required String email,
    required String password,
    required String ghanaCardNumber,
    String? businessName,
  }) async {
    busy = true;
    notifyListeners();
    try {
      session = await _repository.completeVendorProfile(
        email: email,
        password: password,
        ghanaCardNumber: ghanaCardNumber,
        businessName: businessName,
      );
      busy = false;
      _notifyBoundaryChange();
    } catch (e) {
      busy = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Reloads vendor/customer/admin profile (used to refresh approval status).
  Future<void> refreshSession() async {
    final current = session;
    if (current == null) return;
    busy = true;
    notifyListeners();
    try {
      final restored = await _repository.restoreSession(current.role);
      if (restored != null) {
        session = restored;
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final s = session;
    if (s == null) return;
    busy = true;
    try {
      await _repository.logout(s);
    } finally {
      session = null;
      busy = false;
      // Do not notifyListeners() while signed-in screens still depend on
      // Theme/Provider — that causes `_dependents.isEmpty` assertion crashes.
      _notifyBoundaryChange();
    }
  }

  Future<void> forgotPassword({
    required UserRole role,
    required String email,
  }) {
    return _repository.forgotPassword(role: role, email: email);
  }

  Future<void> resetPassword({
    required UserRole role,
    required String email,
    required String token,
    required String password,
    required String passwordConfirmation,
  }) {
    return _repository.resetPassword(
      role: role,
      email: email,
      token: token,
      password: password,
      passwordConfirmation: passwordConfirmation,
    );
  }
}
