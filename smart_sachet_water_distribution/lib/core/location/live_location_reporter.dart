import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';

/// Publishes customer and vendor GPS so admin/vendor maps can show live pins.
class LiveLocationReporter {
  LiveLocationReporter({
    required AuthController auth,
    required Dio dio,
    this.pollInterval = const Duration(seconds: 20),
  })  : _auth = auth,
        _customerApi = CustomerApi(dio),
        _vendorApi = VendorApi(dio);

  final AuthController _auth;
  final CustomerApi _customerApi;
  final VendorApi _vendorApi;
  final Duration pollInterval;
  final DeviceLocationService _location = const DeviceLocationService();

  Timer? _timer;
  bool _running = false;

  void start() {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  void dispose() {
    _auth.removeListener(_onAuth);
    _timer?.cancel();
  }

  void _onAuth() {
    _timer?.cancel();
    _timer = null;
    final session = _auth.session;
    if (session == null) return;
    if (session.role != UserRole.customer && session.role != UserRole.vendor) {
      return;
    }
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_running) return;
    final session = _auth.session;
    if (session == null) return;
    if (session.role != UserRole.customer && session.role != UserRole.vendor) {
      return;
    }
    _running = true;
    try {
      final pos = await _location.tryGetCurrentPosition();
      if (pos == null) return;
      if (session.role == UserRole.customer) {
        await _customerApi.updateLiveLocation(
          session.token,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
      } else {
        await _vendorApi.updateLiveLocation(
          session.token,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
      }
    } catch (e) {
      debugPrint('LiveLocationReporter: $e');
    } finally {
      _running = false;
    }
  }
}
