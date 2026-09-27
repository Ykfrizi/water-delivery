import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:smart_sachet_water_distribution/core/notifications/push_notification_service.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_auto_approve_store.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_order_status.dart';

/// While auto-approve is active, pending orders are approved automatically.
class VendorAutoApproveWatcher with WidgetsBindingObserver {
  VendorAutoApproveWatcher({
    required AuthController auth,
    required Dio dio,
    required VendorAutoApproveStore store,
    this.pollInterval = const Duration(seconds: 12),
  })  : _auth = auth,
        _store = store,
        _api = VendorApi(dio);

  final AuthController _auth;
  final VendorAutoApproveStore _store;
  final VendorApi _api;
  final Duration pollInterval;

  Timer? _timer;
  bool _running = false;

  void start() {
    _auth.addListener(_onAuth);
    _store.addListener(_onStore);
    WidgetsBinding.instance.addObserver(this);
    _onAuth();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_onAuth);
    _store.removeListener(_onStore);
    _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_tick());
    }
  }

  void _onStore() => unawaited(_tick());

  void _onAuth() {
    final session = _auth.session;
    if (session == null || session.role != UserRole.vendor) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    unawaited(_store.ensureLoaded(session.token));
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _tick());
    unawaited(_tick());
  }

  String? _orderRef(Map<String, dynamic> o) {
    for (final key in [
      'order_number',
      'orderNumber',
      'number',
      'id',
    ]) {
      final v = o[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  Future<void> _tick() async {
    if (_running) return;
    final session = _auth.session;
    if (session == null || session.role != UserRole.vendor) return;

    _running = true;
    try {
      await _store.ensureLoaded(session.token);
      var schedule = _store.schedule;

      if (schedule.isOneTimeExpired) {
        if (schedule.hasWeekly) {
          schedule = schedule.copyWith(clearWindow: true);
          await _store.save(session.token, schedule);
        } else if (schedule.enabled) {
          await _store.save(
            session.token,
            schedule.copyWith(enabled: false, clearWindow: true),
          );
          return;
        } else {
          return;
        }
      }

      if (!schedule.isActiveAt(DateTime.now())) {
        debugPrint(
          'VendorAutoApproveWatcher idle '
          '(enabled=${schedule.enabled}, window=${schedule.hasOneTimeWindow}, '
          'weekly=${schedule.hasWeekly})',
        );
        return;
      }

      final orders = await _api.listOrders(
        session.token,
        perPage: 80,
      );
      for (final o in orders) {
        final status = o['status']?.toString();
        if (!orderNeedsVendorApproval(status)) continue;
        final number = _orderRef(o);
        if (number == null) continue;
        try {
          await _api.approveOrder(session.token, number);
          await PushNotificationService.instance.showOrderUpdate(
            title: 'Auto-approved #$number',
            body: 'Order was approved automatically by your schedule.',
            orderNumber: number,
          );
        } catch (e) {
          debugPrint('Auto-approve failed for $number: $e');
        }
      }
    } catch (e) {
      debugPrint('VendorAutoApproveWatcher: $e');
    } finally {
      _running = false;
    }
  }
}
