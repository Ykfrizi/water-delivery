import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/app.dart';
import 'package:smart_sachet_water_distribution/core/location/live_location_reporter.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/core/notifications/order_status_watcher.dart';
import 'package:smart_sachet_water_distribution/core/notifications/push_notification_service.dart';
import 'package:smart_sachet_water_distribution/core/notifications/vendor_auto_approve_watcher.dart';
import 'package:smart_sachet_water_distribution/core/notifications/vendor_new_order_watcher.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/auth_api.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/auth_repository.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/token_storage.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/cart_controller.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_auto_approve_store.dart';

void _initGoogleMapsLite() {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final impl = GoogleMapsFlutterPlatform.instance;
    if (impl is GoogleMapsFlutterAndroid) {
      impl.useAndroidViewSurface = true;
    }
  } catch (e) {
    debugPrint('Maps init skipped: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  final dio = createDio();
  final repo = AuthRepository(api: AuthApi(dio), storage: TokenStorage());
  final auth = AuthController(repo);
  final cart = CartController(dio, auth);
  final autoApprove = VendorAutoApproveStore(dio);

  runApp(
    MultiProvider(
      providers: [
        Provider<Dio>.value(value: dio),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<CartController>.value(value: cart),
        ChangeNotifierProvider<VendorAutoApproveStore>.value(
          value: autoApprove,
        ),
      ],
      child: const SmartSachetApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(auth.bootstrap());
    try {
      OrderStatusWatcher(auth: auth, dio: dio).start();
      VendorNewOrderWatcher(auth: auth, dio: dio).start();
      LiveLocationReporter(auth: auth, dio: dio).start();
      VendorAutoApproveWatcher(
        auth: auth,
        dio: dio,
        store: autoApprove,
      ).start();
    } catch (e) {
      debugPrint('Watchers skipped: $e');
    }
    _initGoogleMapsLite();
    unawaited(() async {
      try {
        await PushNotificationService.instance.init();
      } catch (e) {
        debugPrint('Push init skipped: $e');
      }
    }());
  });
}
