import 'package:flutter/foundation.dart';

/// Google Maps configuration.
///
/// On **Android/iOS**, the Maps SDK reads the key from native config
/// (`android/local.properties` → manifest, or iOS `AppDelegate` / Info.plist).
///
/// Optional for all platforms (required for **web**):
/// `flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key_here`
class MapsConfig {
  MapsConfig._();

  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  /// HTTP Directions API key (same Google Cloud key with Directions enabled).
  /// Prefer `--dart-define=GOOGLE_MAPS_API_KEY=...` so Dart can call the REST API.
  static String get directionsApiKey => googleMapsApiKey;

  /// Whether the map widget should render.
  ///
  /// Mobile uses the native API key; Dart-define is only required on web.
  static bool get isConfigured {
    if (googleMapsApiKey.isNotEmpty) return true;
    if (kIsWeb) return false;
    // Android / iOS: key comes from the platform manifest / plist.
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
