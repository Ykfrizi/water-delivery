import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/notifications/push_notification_service.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';

/// Polls vendor orders and notifies when a customer places a new purchase.
///
/// Works while the vendor app is open. For closed-app delivery, the backend
/// should also send FCM/SMS to the vendor device token.
class VendorNewOrderWatcher {
  VendorNewOrderWatcher({
    required AuthController auth,
    required Dio dio,
    this.pollInterval = const Duration(seconds: 25),
  }) : _auth = auth,
       _api = VendorApi(dio);

  final AuthController _auth;
  final VendorApi _api;
  final Duration pollInterval;

  Timer? _timer;
  bool _running = false;
  bool _seededForSession = false;

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
    if (session == null || session.role != UserRole.vendor) {
      _timer?.cancel();
      _timer = null;
      _seededForSession = false;
      return;
    }
    _seededForSession = false;
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _tick());
    unawaited(_tick());
  }

  String _prefsKey(String token) =>
      'vendor_seen_orders_${token.hashCode.toRadixString(16)}';

  Future<void> _tick() async {
    if (_running) return;
    final session = _auth.session;
    if (session == null || session.role != UserRole.vendor) return;
    _running = true;
    try {
      final orders = await _api.listOrders(session.token, perPage: 40);
      final prefs = await SharedPreferences.getInstance();
      final key = _prefsKey(session.token);
      final raw = prefs.getString(key);
      final seen = <String>{};
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final e in decoded) {
              final s = e?.toString();
              if (s != null && s.isNotEmpty) seen.add(s);
            }
          }
        } catch (_) {
          /* corrupt cache — reseed */
        }
      }

      // First poll after vendor login: remember current orders, don't notify.
      final isFirstSeed = !_seededForSession;
      final currentIds = <String>{};

      for (final o in orders) {
        final number = _orderNumber(o);
        if (number == null) continue;
        currentIds.add(number);
        if (isFirstSeed) continue;
        if (seen.contains(number)) continue;

        final buyer = _buyerLabel(o);
        final total = _totalLabel(o);
        final status = (o['status'] ?? 'new').toString();
        await PushNotificationService.instance.showOrderUpdate(
          title: 'New order #$number',
          body: [
            if (buyer != null) 'From $buyer',
            ?total,
            'Status: $status — open Orders to approve.',
          ].join(' · '),
          orderNumber: number,
        );
      }

      _seededForSession = true;
      final next = {...seen, ...currentIds};
      final list = next.toList();
      final limited = list.length > 200
          ? list.sublist(list.length - 200)
          : list;
      await prefs.setString(key, jsonEncode(limited));
    } catch (e) {
      debugPrint('VendorNewOrderWatcher: $e');
    } finally {
      _running = false;
    }
  }

  static String? _orderNumber(Map<String, dynamic> o) {
    final n = (o['order_number'] ?? o['orderNumber'] ?? o['id'])?.toString();
    if (n == null || n.trim().isEmpty) return null;
    return n.trim();
  }

  static String? _buyerLabel(Map<String, dynamic> o) {
    final customer = o['customer'];
    if (customer is Map) {
      final name = customer['name'] ?? customer['full_name'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
      final email = customer['email'];
      if (email != null && email.toString().trim().isNotEmpty) {
        return email.toString().trim();
      }
    }
    final name = o['customer_name'] ?? o['buyer_name'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString().trim();
    }
    return null;
  }

  static String? _totalLabel(Map<String, dynamic> o) {
    final total = o['total'] ?? o['grand_total'] ?? o['amount'] ?? o['totals'];
    if (total is Map) {
      final v = total['total'] ?? total['grand_total'] ?? total['amount'];
      if (v != null) return formatMoneyDynamic(v);
      return null;
    }
    if (total != null) return formatMoneyDynamic(total);
    return null;
  }
}
