import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Google Maps / Apple Maps turn-by-turn to [destination].
Future<bool> openExternalDrivingNavigation(LatLng destination) async {
  final lat = destination.latitude.toStringAsFixed(6);
  final lng = destination.longitude.toStringAsFixed(6);

  final candidates = <Uri>[
    Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
    Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$lat,$lng&travelmode=driving',
    ),
    Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
  ];

  for (final uri in candidates) {
    try {
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (e) {
      debugPrint('openExternalDrivingNavigation: $e');
    }
  }
  return false;
}
