import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:smart_sachet_water_distribution/core/cache/app_cache.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/cart_line.dart';

/// Shared cart count for the customer bottom-nav badge.
class CartController extends ChangeNotifier {
  CartController(this._dio, this._auth);

  final Dio _dio;
  final AuthController _auth;

  int itemCount = 0;
  List<CartLine> lines = [];
  bool loading = false;
  bool _refreshing = false;

  String get _cacheHint =>
      (_auth.session?.token.hashCode ?? 0).toRadixString(16);

  void applyFetchedCart(Map<String, dynamic> cart) {
    final nextLines = cartLinesFromResponse(cart);
    final nextCount = nextLines.fold<int>(0, (sum, l) => sum + l.quantity);
    final changed = loading || itemCount != nextCount || lines.length != nextLines.length;
    lines = nextLines;
    itemCount = nextCount;
    loading = false;
    unawaited(AppCache.putJson(AppCache.cartKey(_cacheHint), {
      'itemCount': itemCount,
      'lines': lines.map((l) => l.raw).toList(),
    }));
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
    }
  }

  Future<void> refresh() async {
    final session = _auth.session;
    if (session == null || session.role != UserRole.customer) {
      if (itemCount != 0 || lines.isNotEmpty) {
        itemCount = 0;
        lines = [];
        notifyListeners();
      }
      return;
    }
    if (_refreshing) return;
    _refreshing = true;
    try {
      final api = CustomerApi(_dio);
      final cart = await api.getCart(session.token);
      applyFetchedCart(cart);
    } catch (e) {
      debugPrint('CartController.refresh: $e');
      final cached = await AppCache.getJson(AppCache.cartKey(_cacheHint));
      if (cached is Map && cached['itemCount'] is num) {
        final cachedCount = (cached['itemCount'] as num).toInt();
        if (itemCount != cachedCount) {
          itemCount = cachedCount;
          notifyListeners();
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> loadCached() async {
    final cached = await AppCache.getJson(AppCache.cartKey(_cacheHint));
    if (cached is Map && cached['itemCount'] is num) {
      itemCount = (cached['itemCount'] as num).toInt();
      notifyListeners();
    }
  }
}
