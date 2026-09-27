/// API base for `{APP_URL}/api/v1` from the handoff.
///
/// Override at build time:
/// `flutter run --dart-define=API_BASE_URL=https://your-api.com/api/v1`
class ApiConfig {
  ApiConfig._();

  static const String _raw = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.254.78.250:8000/api/v1/',
  );

  static String get baseUrl {
    final value = _raw.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value.endsWith('/') ? value : '$value/';
    }
    return 'http://${value.endsWith('/') ? value : '$value/'}';
  }
}
