import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_marker_point.dart';

/// Builds delivery-style polylines between map markers.
class MapRouteBuilder {
  MapRouteBuilder._();

  static double haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  /// Straight (geodesic) lines from each customer to the nearest vendor.
  static Set<Polyline> vendorToCustomerRoutes({
    required List<MapMarkerPoint> vendors,
    required List<MapMarkerPoint> customers,
    Color color = const Color(0xFFC62828),
  }) {
    if (vendors.isEmpty || customers.isEmpty) return {};
    final lines = <Polyline>{};
    var i = 0;
    for (final customer in customers) {
      MapMarkerPoint? nearest;
      var best = double.infinity;
      for (final vendor in vendors) {
        final d = haversineKm(customer.latLng, vendor.latLng);
        if (d < best) {
          best = d;
          nearest = vendor;
        }
      }
      if (nearest == null) continue;
      lines.add(
        Polyline(
          polylineId: PolylineId('route-vc-$i'),
          points: [nearest.latLng, customer.latLng],
          color: color.withValues(alpha: 0.75),
          width: 3,
          geodesic: true,
          patterns: [PatternItem.dash(18), PatternItem.gap(10)],
        ),
      );
      i++;
    }
    return lines;
  }

  /// Greedy nearest-neighbor ordering of stops (does not draw a polyline).
  static List<MapMarkerPoint> orderedStops({
    required List<MapMarkerPoint> stops,
    LatLng? start,
  }) {
    if (stops.isEmpty) return const [];
    final remaining = List<MapMarkerPoint>.from(stops);
    final ordered = <MapMarkerPoint>[];
    var current = start ?? remaining.first.latLng;

    while (remaining.isNotEmpty) {
      var bestIndex = 0;
      var best = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final d = haversineKm(current, remaining[i].latLng);
        if (d < best) {
          best = d;
          bestIndex = i;
        }
      }
      final next = remaining.removeAt(bestIndex);
      ordered.add(next);
      current = next.latLng;
    }
    return ordered;
  }

  /// Greedy delivery sequence visiting every customer once (nearest-neighbor).
  static Set<Polyline> deliverySequenceRoute({
    required List<MapMarkerPoint> stops,
    LatLng? start,
    Color color = const Color(0xFF5E35B1),
  }) {
    if (stops.isEmpty) return {};
    final ordered = orderedStops(stops: stops, start: start);
    final path = <LatLng>[?start, ...ordered.map((s) => s.latLng)];

    if (path.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route-sequence'),
        points: path,
        color: color.withValues(alpha: 0.85),
        width: 4,
        geodesic: true,
      ),
    };
  }
}
