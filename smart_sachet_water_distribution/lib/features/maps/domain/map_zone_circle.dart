import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A delivery geofence drawn as a circle on the map.
class MapZoneCircle {
  const MapZoneCircle({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.name,
    this.color = const Color(0xFF00838F),
  });

  final String id;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final String name;
  final Color color;

  LatLng get center => LatLng(latitude, longitude);

  double get radiusMeters => radiusKm * 1000;

  Circle toGoogleCircle() {
    return Circle(
      circleId: CircleId(id),
      center: center,
      radius: radiusMeters,
      fillColor: color.withValues(alpha: 0.14),
      strokeColor: color.withValues(alpha: 0.85),
      strokeWidth: 2,
    );
  }

  static MapZoneCircle? fromJson(Map<String, dynamic> json, {Color? color}) {
    final lat = _asDouble(json['latitude'] ?? json['lat']);
    final lng = _asDouble(json['longitude'] ?? json['lng']);
    var radius = _asDouble(json['radius_km'] ?? json['radius']);
    if (radius == null) {
      final meters = _asDouble(json['radius_m'] ?? json['radius_meters']);
      if (meters != null) radius = meters / 1000;
    }
    if (lat == null || lng == null || radius == null || radius <= 0) {
      return null;
    }
    final id = (json['id'] ?? '$lat,$lng').toString();
    final name = (json['name'] ?? json['label'] ?? 'Delivery zone').toString();
    return MapZoneCircle(
      id: 'zone-$id',
      latitude: lat,
      longitude: lng,
      radiusKm: radius,
      name: name,
      color: color ?? const Color(0xFF00838F),
    );
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }
}
