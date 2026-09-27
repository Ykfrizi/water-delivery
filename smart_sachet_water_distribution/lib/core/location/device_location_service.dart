import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class DevicePosition {
  const DevicePosition({
    required this.latitude,
    required this.longitude,
    this.heading,
    this.speedMps,
  });

  final double latitude;
  final double longitude;
  final double? heading;
  final double? speedMps;

  String get latitudeLabel => latitude.toStringAsFixed(6);
  String get longitudeLabel => longitude.toStringAsFixed(6);
}

/// Reads the device GPS position with runtime permission handling.
class DeviceLocationService {
  const DeviceLocationService();

  Future<String?> permissionIssue() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      return 'Turn on location services on your phone to share delivery location.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return 'Location permission denied. Enable it in phone settings.';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. Enable it in app settings.';
    }
    return null;
  }

  /// Requests GPS and opens phone/app settings when location is off.
  Future<String?> ensureReady({bool openSettingsIfDisabled = true}) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (openSettingsIfDisabled) {
        await Geolocator.openLocationSettings();
      }
      final nowEnabled = await Geolocator.isLocationServiceEnabled();
      if (!nowEnabled) {
        return 'Turn on location on your phone. Delivery cannot continue without it.';
      }
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return 'Allow location access. We need it to deliver your order.';
    }
    if (permission == LocationPermission.deniedForever) {
      if (openSettingsIfDisabled) {
        await Geolocator.openAppSettings();
      }
      return 'Enable location permission in app settings to continue.';
    }
    return null;
  }

  Future<DevicePosition?> tryGetCurrentPosition() async {
    final issue = await permissionIssue();
    if (issue != null) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return _fromPosition(pos);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return _fromPosition(last);
      return null;
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return _fromPosition(last);
      } catch (_) {}
      return null;
    }
  }

  DevicePosition _fromPosition(Position pos) {
    return DevicePosition(
      latitude: pos.latitude,
      longitude: pos.longitude,
      heading: pos.heading,
      speedMps: pos.speed,
    );
  }

  /// Live GPS updates for driver-style navigation.
  Stream<DevicePosition> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).map(
      (pos) => DevicePosition(
        latitude: pos.latitude,
        longitude: pos.longitude,
        heading: pos.heading,
        speedMps: pos.speed,
      ),
    );
  }

  /// Reads GPS and shows a snackbar on failure. Returns null if unavailable.
  Future<DevicePosition?> getPositionOrExplain(BuildContext context) async {
    final issue = await permissionIssue();
    if (issue != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(issue), behavior: SnackBarBehavior.floating),
        );
      }
      return null;
    }
    try {
      final pos = await tryGetCurrentPosition();
      if (pos == null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read GPS. Try again outdoors.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return pos;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read GPS. Try again outdoors.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }
  }
}
