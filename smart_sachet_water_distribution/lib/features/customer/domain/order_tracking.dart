import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_location_parser.dart';

/// Live courier + destination points parsed from an order / tracking payload.
class OrderTrackingSnapshot {
  const OrderTrackingSnapshot({
    required this.status,
    this.courier,
    this.destination,
    this.vendor,
    this.updatedAt,
    this.etaMinutes,
  });

  final String status;
  final LatLng? courier;
  final LatLng? destination;
  final LatLng? vendor;
  final String? updatedAt;
  final int? etaMinutes;

  bool get canShowMap =>
      courier != null || destination != null || vendor != null;

  bool get isLive {
    final s = status.toLowerCase();
    return s.contains('deliver') ||
        s.contains('ship') ||
        s == 'out_for_delivery' ||
        s == 'on_the_way';
  }

  factory OrderTrackingSnapshot.fromOrder(Map<String, dynamic> order) {
    final status = (order['status'] ?? '—').toString();
    final tracking = order['tracking'];
    final trackMap = tracking is Map
        ? Map<String, dynamic>.from(tracking)
        : <String, dynamic>{};

    LatLng? courier = _pair(
      order['courier_latitude'] ??
          order['courier_lat'] ??
          order['driver_latitude'] ??
          order['driver_lat'] ??
          trackMap['latitude'] ??
          trackMap['lat'],
      order['courier_longitude'] ??
          order['courier_lng'] ??
          order['driver_longitude'] ??
          order['driver_lng'] ??
          trackMap['longitude'] ??
          trackMap['lng'],
    );
    for (final candidate in [
      order['courier_location'],
      order['driver_location'],
      trackMap['location'],
      tracking,
    ]) {
      if (courier != null) break;
      if (candidate is Map) {
        final c = parseCoordinates(Map<String, dynamic>.from(candidate));
        if (c != null) courier = LatLng(c.lat, c.lng);
      }
    }

    LatLng? destination;
    for (final candidate in [
      order['shipping_address'],
      order['delivery_location'],
      order,
    ]) {
      if (destination != null) break;
      if (candidate is Map) {
        final c = parseCoordinates(Map<String, dynamic>.from(candidate));
        if (c != null) destination = LatLng(c.lat, c.lng);
      }
    }

    LatLng? vendor;
    for (final candidate in [order['vendor'], order['store']]) {
      if (vendor != null) break;
      if (candidate is Map) {
        final m = Map<String, dynamic>.from(candidate);
        final c = parseCoordinates(m);
        if (c != null) {
          vendor = LatLng(c.lat, c.lng);
        } else {
          vendor = _pair(
            m['vendor_latitude'] ?? m['store_latitude'],
            m['vendor_longitude'] ?? m['store_longitude'],
          );
        }
      }
    }
    vendor ??= _pair(
      order['vendor_latitude'] ?? order['store_latitude'],
      order['vendor_longitude'] ?? order['store_longitude'],
    );

    final eta = int.tryParse(
      (order['eta_minutes'] ?? trackMap['eta_minutes'] ?? '').toString(),
    );

    return OrderTrackingSnapshot(
      status: status,
      courier: courier,
      destination: destination,
      vendor: vendor,
      updatedAt: (order['location_updated_at'] ??
              trackMap['updated_at'] ??
              order['updated_at'])
          ?.toString(),
      etaMinutes: eta,
    );
  }

  static LatLng? _pair(dynamic lat, dynamic lng) {
    double? a;
    double? b;
    if (lat is num) a = lat.toDouble();
    if (lng is num) b = lng.toDouble();
    a ??= double.tryParse(lat?.toString() ?? '');
    b ??= double.tryParse(lng?.toString() ?? '');
    if (a == null || b == null) return null;
    if (a == 0 && b == 0) return null;
    return LatLng(a, b);
  }
}
