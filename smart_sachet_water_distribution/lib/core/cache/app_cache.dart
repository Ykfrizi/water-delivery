import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight offline cache for lists (orders, cart snapshot, vendors).
class AppCache {
  AppCache._();

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<void> putJson(String key, Object? value) async {
    final p = await _prefs;
    await p.setString(key, jsonEncode(value));
  }

  static Future<dynamic> getJson(String key) async {
    final p = await _prefs;
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getMapList(String key) async {
    final v = await getJson(key);
    if (v is! List) return [];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> putMapList(
    String key,
    List<Map<String, dynamic>> list,
  ) async {
    await putJson(key, list);
  }

  static String ordersKey(String tokenHint) => 'cache_orders_$tokenHint';
  static String cartKey(String tokenHint) => 'cache_cart_$tokenHint';
  static String vendorsKey() => 'cache_vendors';
  static String voucherKey(String tokenHint) => 'customer_voucher_$tokenHint';
  static String deliveryAddressKey(String userId) =>
      'customer_delivery_address_$userId';

  static Future<void> putDeliveryAddress({
    required String userId,
    required String line1,
    required String city,
    required String phone,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    await putJson(deliveryAddressKey(id), {
      'line1': line1.trim(),
      'city': city.trim(),
      'phone': phone.trim(),
    });
  }

  static Future<Map<String, String>> getDeliveryAddress(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return const {};
    final raw = await getJson(deliveryAddressKey(id));
    if (raw is! Map) return const {};
    String read(String key) => (raw[key] ?? '').toString().trim();
    return {
      'line1': read('line1'),
      'city': read('city'),
      'phone': read('phone'),
    };
  }

  static Future<void> putVoucherCode(String tokenHint, String? code) async {
    final p = await _prefs;
    final key = voucherKey(tokenHint);
    final trimmed = (code ?? '').trim().toUpperCase();
    if (trimmed.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, trimmed);
    }
  }

  static Future<String?> getVoucherCode(String tokenHint) async {
    final p = await _prefs;
    final v = p.getString(voucherKey(tokenHint));
    if (v == null || v.trim().isEmpty) return null;
    return v.trim().toUpperCase();
  }
}
