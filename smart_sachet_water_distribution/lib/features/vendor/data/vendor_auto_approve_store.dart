import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_auto_approve_schedule.dart';

/// Persists auto-approve settings locally and best-effort syncs to profile.
class VendorAutoApproveStore extends ChangeNotifier {
  VendorAutoApproveStore(this._dio);

  final Dio _dio;
  VendorAutoApproveSchedule _schedule = const VendorAutoApproveSchedule();
  String? _tokenHint;
  var _ready = false;
  Future<void>? _inFlight;

  VendorAutoApproveSchedule get schedule => _schedule;

  String _key(String token) =>
      'vendor_auto_approve_${token.hashCode.toRadixString(16)}';

  Future<void> load(String token) {
    return _inFlight ??= _doLoad(token).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _doLoad(String token) async {
    _tokenHint = token;
    final prefs = await SharedPreferences.getInstance();
    VendorAutoApproveSchedule local = const VendorAutoApproveSchedule();
    final raw = prefs.getString(_key(token));
    if (raw != null && raw.isNotEmpty) {
      try {
        local = VendorAutoApproveSchedule.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {}
    }

    VendorAutoApproveSchedule remote = const VendorAutoApproveSchedule();
    var remoteConfigured = false;
    try {
      final profile = await VendorApi(_dio).getProfile(token);
      remote = VendorAutoApproveSchedule.fromJson(profile);
      remoteConfigured = remote.enabled || remote.hasAnySchedule;
    } catch (_) {}

    // Local is the source of truth. A Laravel profile that merely *lists*
    // auto_approve_* keys as null/false must not wipe a saved schedule.
    if (local.enabled || local.hasAnySchedule) {
      _schedule = local;
    } else if (remoteConfigured) {
      _schedule = remote;
    } else {
      _schedule = local;
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> save(String token, VendorAutoApproveSchedule next) async {
    _schedule = next;
    _tokenHint = token;
    _ready = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(token), jsonEncode(next.toJson()));

    try {
      await VendorApi(_dio).updateProfile(token, next.toProfilePayload());
    } catch (e) {
      debugPrint('VendorAutoApproveStore sync: $e');
    }
  }

  Future<void> stop(String token) async {
    await save(
      token,
      _schedule.copyWith(enabled: false),
    );
  }

  Future<void> ensureLoaded(String token) async {
    if (_ready && _tokenHint == token) return;
    await load(token);
  }
}
