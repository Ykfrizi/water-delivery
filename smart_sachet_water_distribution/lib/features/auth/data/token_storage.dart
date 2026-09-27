import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';

/// Separate keys per persona — wrong token on wrong route yields **403** (API rule).
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(UserRole role) => 'sanctum_token_${role.name}';

  Future<void> write(UserRole role, String token) async {
    await _storage.write(key: _key(role), value: token);
  }

  Future<String?> read(UserRole role) => _storage.read(key: _key(role));

  Future<void> clear(UserRole role) => _storage.delete(key: _key(role));

  Future<void> clearAll() async {
    for (final r in UserRole.values) {
      await clear(r);
    }
  }
}
