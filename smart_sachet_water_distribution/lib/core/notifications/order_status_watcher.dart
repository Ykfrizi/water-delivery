import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_sachet_water_distribution/core/notifications/push_notification_service.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';

/// Polls customer orders and fires local notifications on status changes.
///
/// Complements backend FCM/SMS: works when the app is open.
class OrderStatusWatcher {
  OrderStatusWatcher({
    required AuthController auth,
    required Dio dio,
    this.pollInterval = const Duration(seconds: 45),
  })  : _auth = auth,
        _api = CustomerApi(dio);

  final AuthController _auth;
  final CustomerApi _api;
  final Duration pollInterval;

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
    final session = _auth.session;
    if (session == null || session.role != UserRole.customer) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _tick());
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_running) return;
    final session = _auth.session;
    if (session == null || session.role != UserRole.customer) return;
    _running = true;
    try {
      final orders = await _api.listOrders(session.token, perPage: 40, page: 1);
      final prefs = await SharedPreferences.getInstance();
      for (final o in orders) {
        final number =
            (o['order_number'] ?? o['orderNumber'] ?? o['id'])?.toString();
        final status = (o['status'] ?? '').toString().toLowerCase().trim();
        if (number == null || number.isEmpty || status.isEmpty) continue;
        final key = 'order_status_$number';
        final prev = prefs.getString(key);
        if (prev == null) {
          await prefs.setString(key, status);
          continue;
        }
        if (prev == status) continue;
        await prefs.setString(key, status);
        final label = _friendlyStatus(status);
        await PushNotificationService.instance.showOrderUpdate(
          title: 'Order #$number',
          body: label,
          orderNumber: number,
        );
      }
    } catch (e) {
      debugPrint('OrderStatusWatcher: $e');
    } finally {
      _running = false;
    }
  }

  static String _friendlyStatus(String status) {
    return switch (status) {
      'pending' ||
      'awaiting_approval' ||
      'new' =>
        'Your order was placed and is awaiting vendor approval.',
      'processing' ||
      'approved' ||
      'accepted' =>
        'Your order was approved and is being prepared.',
      'out_for_delivery' ||
      'shipped' ||
      'on_the_way' ||
      'delivering' =>
        'Your order is out for delivery — open the app to track on the map.',
      'delivered' || 'completed' => 'Your order was delivered. Enjoy!',
      'cancelled' || 'rejected' => 'Your order was cancelled.',
      _ => 'Order status updated to $status.',
    };
  }
}
