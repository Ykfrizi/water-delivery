import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_marker_point.dart';

/// Simple zoom-aware grid clustering for map markers.
class MapClusterEngine {
  MapClusterEngine._();

  /// At higher zoom, returns individuals; when zoomed out, groups nearby pins.
  static List<ClusteredMapItem> cluster(
    List<MapMarkerPoint> markers, {
    required double zoom,
  }) {
    if (markers.isEmpty) return const [];
    if (zoom >= 13.5 || markers.length <= 2) {
      return [for (final m in markers) ClusteredMapItem.single(m)];
    }

    // Cell size grows as zoom decreases (~degrees).
    final cell = zoom >= 12
        ? 0.012
        : zoom >= 10
        ? 0.03
        : zoom >= 8
        ? 0.08
        : 0.18;

    final buckets = <String, List<MapMarkerPoint>>{};
    for (final m in markers) {
      final key =
          '${(m.latitude / cell).floor()}_${(m.longitude / cell).floor()}';
      (buckets[key] ??= []).add(m);
    }

    final out = <ClusteredMapItem>[];
    var clusterIndex = 0;
    for (final group in buckets.values) {
      if (group.length == 1) {
        out.add(ClusteredMapItem.single(group.first));
      } else {
        final lat =
            group.map((e) => e.latitude).reduce((a, b) => a + b) / group.length;
        final lng =
            group.map((e) => e.longitude).reduce((a, b) => a + b) /
            group.length;
        out.add(
          ClusteredMapItem.cluster(
            id: 'cluster-${clusterIndex++}',
            latitude: lat,
            longitude: lng,
            members: group,
          ),
        );
      }
    }
    return out;
  }
}

class ClusteredMapItem {
  const ClusteredMapItem._({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.members,
  });

  factory ClusteredMapItem.single(MapMarkerPoint point) => ClusteredMapItem._(
    id: point.id,
    latitude: point.latitude,
    longitude: point.longitude,
    members: [point],
  );

  factory ClusteredMapItem.cluster({
    required String id,
    required double latitude,
    required double longitude,
    required List<MapMarkerPoint> members,
  }) => ClusteredMapItem._(
    id: id,
    latitude: latitude,
    longitude: longitude,
    members: members,
  );

  final String id;
  final double latitude;
  final double longitude;
  final List<MapMarkerPoint> members;

  bool get isCluster => members.length > 1;

  LatLng get latLng => LatLng(latitude, longitude);

  String get title =>
      isCluster ? '${members.length} nearby' : members.first.title;

  String? get snippet => isCluster
      ? members.map((m) => m.title).take(3).join(' · ')
      : members.first.subtitle;
}
