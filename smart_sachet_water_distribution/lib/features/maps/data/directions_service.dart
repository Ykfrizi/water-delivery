import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_sachet_water_distribution/core/config/maps_config.dart';

class DirectionsStep {
  const DirectionsStep({
    required this.instruction,
    required this.distanceText,
    required this.durationText,
    required this.start,
    required this.end,
    this.maneuver,
  });

  final String instruction;
  final String distanceText;
  final String durationText;
  final LatLng start;
  final LatLng end;
  final String? maneuver;
}

class DirectionsResult {
  const DirectionsResult({
    required this.polyline,
    required this.steps,
    required this.distanceText,
    required this.durationText,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> polyline;
  final List<DirectionsStep> steps;
  final String distanceText;
  final String durationText;
  final int distanceMeters;
  final int durationSeconds;

  bool get hasPath => polyline.length >= 2;
}

String stripHtmlInstructions(String raw) {
  return raw
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Google Directions API road routes (falls back to empty → caller uses geodesic).
class DirectionsService {
  DirectionsService([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Returns encoded path points along roads between [origin] and [destination],
  /// optionally via [waypoints]. Empty if the API key is missing or the call fails.
  Future<List<LatLng>> route({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    final detailed = await routeDetailed(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    );
    return detailed?.polyline ?? const [];
  }

  Future<DirectionsResult?> routeDetailed({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    final key = MapsConfig.directionsApiKey;
    if (key.isEmpty) return null;

    try {
      final wp = waypoints.isEmpty
          ? null
          : waypoints.map((p) => '${p.latitude},${p.longitude}').join('|');
      final r = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          if (wp != null) 'waypoints': 'optimize:true|$wp',
          'mode': 'driving',
          'key': key,
        },
      );
      final routes = r.data?['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final route = routes.first;
      if (route is! Map) return null;

      final overview = route['overview_polyline'];
      final encoded = overview is Map ? overview['points']?.toString() : null;
      final polyline = (encoded == null || encoded.isEmpty)
          ? <LatLng>[]
          : decodePolyline(encoded);

      final legs = route['legs'];
      final steps = <DirectionsStep>[];
      var distanceMeters = 0;
      var durationSeconds = 0;
      var distanceText = '';
      var durationText = '';

      if (legs is List && legs.isNotEmpty) {
        for (final leg in legs.whereType<Map>()) {
          final dist = leg['distance'];
          final dur = leg['duration'];
          if (dist is Map) {
            distanceMeters += (dist['value'] as num?)?.toInt() ?? 0;
            final text = dist['text']?.toString();
            if (text != null && text.isNotEmpty) distanceText = text;
          }
          if (dur is Map) {
            durationSeconds += (dur['value'] as num?)?.toInt() ?? 0;
            final text = dur['text']?.toString();
            if (text != null && text.isNotEmpty) durationText = text;
          }
          final rawSteps = leg['steps'];
          if (rawSteps is! List) continue;
          for (final step in rawSteps.whereType<Map>()) {
            final start = _latLngFrom(step['start_location']);
            final end = _latLngFrom(step['end_location']);
            if (start == null || end == null) continue;
            steps.add(
              DirectionsStep(
                instruction: stripHtmlInstructions(
                  step['html_instructions']?.toString() ?? 'Continue',
                ),
                distanceText: step['distance'] is Map
                    ? (step['distance']['text']?.toString() ?? '')
                    : '',
                durationText: step['duration'] is Map
                    ? (step['duration']['text']?.toString() ?? '')
                    : '',
                start: start,
                end: end,
                maneuver: step['maneuver']?.toString(),
              ),
            );
          }
        }
      }

      if (polyline.isEmpty && steps.isEmpty) return null;
      return DirectionsResult(
        polyline: polyline.isNotEmpty ? polyline : [origin, destination],
        steps: steps,
        distanceText: distanceText,
        durationText: durationText,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
      );
    } catch (e) {
      debugPrint('DirectionsService: $e');
      return null;
    }
  }

  /// Multi-stop path: origin → stops… (road network).
  Future<List<LatLng>> routeSequence({
    required LatLng origin,
    required List<LatLng> stops,
  }) async {
    if (stops.isEmpty) return const [];
    if (stops.length == 1) {
      return route(origin: origin, destination: stops.first);
    }
    return route(
      origin: origin,
      destination: stops.last,
      waypoints: stops.sublist(0, stops.length - 1),
    );
  }

  static LatLng? _latLngFrom(dynamic value) {
    if (value is! Map) return null;
    final lat = value['lat'];
    final lng = value['lng'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  /// Decodes Google encoded polyline algorithm.
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
