import 'package:google_maps_flutter/google_maps_flutter.dart';

enum MapMarkerKind { customer, vendor }

class MapMarkerPoint {
  const MapMarkerPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
    required this.kind,
  });

  final String id;
  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;
  final MapMarkerKind kind;

  LatLng get latLng => LatLng(latitude, longitude);

  BitmapDescriptor get icon => switch (kind) {
    MapMarkerKind.customer => BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueAzure,
    ),
    MapMarkerKind.vendor => BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueGreen,
    ),
  };
}
