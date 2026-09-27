import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_zone_circle.dart';

/// Water Delivery delivers only in Ho (Volta Region), not Accra.
class ServiceArea {
  const ServiceArea._();

  /// Ho, Ghana — city centre.
  static const LatLng center = LatLng(6.6110, 0.4703);

  static const String cityName = 'Ho';
  static const String regionName = 'Volta Region';

  /// Covers Ho township and nearby communities, not Accra (~140 km west).
  static const double radiusKm = 18;
  static const double outskirtsRadiusKm = 10;

  static const CameraPosition camera = CameraPosition(
    target: center,
    zoom: 13.2,
  );

  static MapZoneCircle get zoneCircle => const MapZoneCircle(
    id: 'service-area-ho',
    latitude: 6.6110,
    longitude: 0.4703,
    radiusKm: radiusKm,
    name: 'Ho delivery area',
    color: Color(0xFF5E35B1),
  );

  static bool contains(double latitude, double longitude) {
    return distanceKm(latitude, longitude) <= radiusKm;
  }

  static bool containsLatLng(LatLng point) =>
      contains(point.latitude, point.longitude);

  static bool isOutskirts(double latitude, double longitude) {
    final distance = distanceKm(latitude, longitude);
    return distance > outskirtsRadiusKm && distance <= radiusKm;
  }

  static double distanceKm(double latitude, double longitude) {
    const r = 6371.0;
    final dLat = _rad(latitude - center.latitude);
    final dLng = _rad(longitude - center.longitude);
    final lat1 = _rad(center.latitude);
    final lat2 = _rad(latitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  /// City text from checkout. Accra / Tema / Kumasi are out of area.
  static bool cityIsAllowed(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty) return true;
    if (s.contains('accra') ||
        s.contains('tema') ||
        s.contains('kumasi') ||
        s.contains('takoradi')) {
      return false;
    }
    return s == 'ho' ||
        s.startsWith('ho ') ||
        s.endsWith(' ho') ||
        s.contains(' volta') ||
        s == 'volta' ||
        s.contains('hohoe');
  }

  static const String outsideAreaMessage =
      'Water Delivery delivers only in Ho (Volta Region), not Accra. '
      'Share a GPS pin inside Ho to place this order.';

  static const String vendorOutsidePinMessage =
      'This customer pin is outside Ho. We only navigate deliveries inside Ho.';
}

double _rad(double deg) => deg * math.pi / 180;
