import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/config/maps_config.dart';
import 'package:smart_sachet_water_distribution/features/maps/data/directions_service.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_cluster.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_marker_point.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_route_builder.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_zone_circle.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/service_area.dart';

LatLngBounds? _boundsForPoints(Iterable<LatLng> points) {
  final list = points.toList();
  if (list.isEmpty) return null;
  var minLat = list.first.latitude;
  var maxLat = list.first.latitude;
  var minLng = list.first.longitude;
  var maxLng = list.first.longitude;
  for (final p in list.skip(1)) {
    minLat = minLat < p.latitude ? minLat : p.latitude;
    maxLat = maxLat > p.latitude ? maxLat : p.latitude;
    minLng = minLng < p.longitude ? minLng : p.longitude;
    maxLng = maxLng > p.longitude ? maxLng : p.longitude;
  }
  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}

/// Advanced operations map: clustering, delivery routes, and geofence zones.
class LocationsMapView extends StatefulWidget {
  const LocationsMapView({
    super.key,
    required this.markers,
    this.zones = const [],
    this.routeMode = MapRouteMode.none,
    this.emptyMessage = 'No locations to show yet.',
    this.legend,
    this.enableClustering = true,
    this.showControls = true,
    this.initialShowRoutes = true,
    this.myLocationEnabled = false,
    this.mapType = MapType.normal,
    this.onMapTypeChanged,
    this.onMarkerTap,
    this.fallbackCenter = ServiceArea.center,
  });

  final List<MapMarkerPoint> markers;
  final List<MapZoneCircle> zones;
  final MapRouteMode routeMode;
  final String emptyMessage;
  final Widget? legend;
  final bool enableClustering;
  final bool showControls;
  final bool initialShowRoutes;
  final bool myLocationEnabled;
  final MapType mapType;
  final ValueChanged<MapType>? onMapTypeChanged;
  final ValueChanged<MapMarkerPoint>? onMarkerTap;
  final LatLng fallbackCenter;

  @override
  State<LocationsMapView> createState() => _LocationsMapViewState();
}

enum MapRouteMode { none, vendorToCustomer, deliverySequence }

class _LocationsMapViewState extends State<LocationsMapView> {
  GoogleMapController? _controller;
  double _zoom = 12;
  late bool _showRoutes;
  bool _showZones = true;
  bool _clusterEnabled = true;
  late MapType _mapType;
  Set<Polyline> _roadPolylines = {};

  @override
  void initState() {
    super.initState();
    _clusterEnabled = widget.enableClustering;
    _showRoutes = widget.initialShowRoutes;
    _mapType = widget.mapType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_showRoutes) _loadRoadRoutes();
    });
  }

  @override
  void didUpdateWidget(covariant LocationsMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapType != widget.mapType) {
      _mapType = widget.mapType;
    }
    final oldIds = oldWidget.markers.map((m) => m.id).join('|');
    final newIds = widget.markers.map((m) => m.id).join('|');
    final idsChanged = oldIds != newIds;
    final layoutChanged =
        oldWidget.zones.length != widget.zones.length ||
        oldWidget.routeMode != widget.routeMode;
    if (idsChanged || layoutChanged) {
      _fitContent();
      _loadRoadRoutes();
    }
  }

  Future<void> _loadRoadRoutes() async {
    if (!_showRoutes || widget.routeMode == MapRouteMode.none) {
      if (_roadPolylines.isNotEmpty) {
        setState(() => _roadPolylines = {});
      }
      return;
    }
    final vendors = _vendors;
    final customers = _customers;
    final service = DirectionsService();
    final lines = <Polyline>{};

    if (widget.routeMode == MapRouteMode.vendorToCustomer &&
        vendors.isNotEmpty &&
        customers.isNotEmpty) {
      var i = 0;
      // Cap Directions calls so a busy admin map does not freeze.
      for (final customer in customers.take(12)) {
        MapMarkerPoint? nearest;
        var best = double.infinity;
        for (final vendor in vendors) {
          final d = MapRouteBuilder.haversineKm(customer.latLng, vendor.latLng);
          if (d < best) {
            best = d;
            nearest = vendor;
          }
        }
        if (nearest == null) continue;
        final path = await service.route(
          origin: nearest.latLng,
          destination: customer.latLng,
        );
        final points = path.length >= 2
            ? path
            : [nearest.latLng, customer.latLng];
        lines.add(
          Polyline(
            polylineId: PolylineId('road-vc-$i'),
            points: points,
            color: const Color(0xFFC62828).withValues(alpha: 0.8),
            width: 4,
          ),
        );
        i++;
      }
    } else if (widget.routeMode == MapRouteMode.deliverySequence) {
      final stops = customers.isNotEmpty ? customers : widget.markers;
      if (stops.isNotEmpty) {
        final start = widget.zones.isNotEmpty
            ? widget.zones.first.center
            : (vendors.isNotEmpty ? vendors.first.latLng : stops.first.latLng);
        final ordered = MapRouteBuilder.orderedStops(
          stops: stops,
          start: start,
        );
        final path = await service.routeSequence(
          origin: start,
          stops: ordered.map((s) => s.latLng).toList(),
        );
        final points = path.length >= 2
            ? path
            : [start, ...ordered.map((s) => s.latLng)];
        if (points.length >= 2) {
          lines.add(
            Polyline(
              polylineId: const PolylineId('road-sequence'),
              points: points,
              color: const Color(0xFF5E35B1).withValues(alpha: 0.9),
              width: 5,
            ),
          );
        }
      }
    }

    if (!mounted) return;
    setState(() => _roadPolylines = lines);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  List<MapMarkerPoint> get _vendors =>
      widget.markers.where((m) => m.kind == MapMarkerKind.vendor).toList();

  List<MapMarkerPoint> get _customers =>
      widget.markers.where((m) => m.kind == MapMarkerKind.customer).toList();

  Set<Marker> get _googleMarkers {
    final source = _clusterEnabled
        ? MapClusterEngine.cluster(widget.markers, zoom: _zoom)
        : [for (final m in widget.markers) ClusteredMapItem.single(m)];

    return {
      for (final item in source)
        Marker(
          markerId: MarkerId(item.id),
          position: item.latLng,
          icon: item.isCluster
              ? BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                )
              : item.members.first.icon,
          infoWindow: InfoWindow(title: item.title, snippet: item.snippet),
          onTap: item.isCluster
              ? () =>
                    _zoomInto(item.latLng, targetZoom: (_zoom + 2).clamp(3, 18))
              : widget.onMarkerTap == null
              ? null
              : () => widget.onMarkerTap!(item.members.first),
        ),
    };
  }

  Set<Polyline> get _polylines {
    if (!_showRoutes) return {};
    if (_roadPolylines.isNotEmpty) return _roadPolylines;
    switch (widget.routeMode) {
      case MapRouteMode.none:
        return {};
      case MapRouteMode.vendorToCustomer:
        return MapRouteBuilder.vendorToCustomerRoutes(
          vendors: _vendors,
          customers: _customers,
        );
      case MapRouteMode.deliverySequence:
        final start = widget.zones.isNotEmpty
            ? widget.zones.first.center
            : (_vendors.isNotEmpty ? _vendors.first.latLng : null);
        return MapRouteBuilder.deliverySequenceRoute(
          stops: _customers.isNotEmpty ? _customers : widget.markers,
          start: start,
        );
    }
  }

  Set<Circle> get _circles {
    if (!_showZones) return {};
    return {for (final z in widget.zones) z.toGoogleCircle()};
  }

  Future<void> _zoomInto(LatLng target, {required double targetZoom}) async {
    final c = _controller;
    if (c == null) return;
    await c.animateCamera(CameraUpdate.newLatLngZoom(target, targetZoom));
  }

  Future<void> _fitContent() async {
    final controller = _controller;
    if (controller == null) return;
    final points = <LatLng>[
      ...widget.markers.map((m) => m.latLng),
      ...widget.zones.map((z) => z.center),
    ];
    final bounds = _boundsForPoints(points);
    if (bounds == null) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(ServiceArea.camera),
      );
      return;
    }
    if ((bounds.northeast.latitude - bounds.southwest.latitude).abs() <
            0.0008 &&
        (bounds.northeast.longitude - bounds.southwest.longitude).abs() <
            0.0008) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 13.2),
      );
      return;
    }
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  bool get _isSatellite =>
      _mapType == MapType.satellite || _mapType == MapType.hybrid;

  void _setMapType(MapType type) {
    setState(() => _mapType = type);
    widget.onMapTypeChanged?.call(type);
  }

  void _toggleMapType() {
    _setMapType(_isSatellite ? MapType.normal : MapType.hybrid);
  }

  @override
  Widget build(BuildContext context) {
    if (!MapsConfig.isConfigured) {
      return _MapsSetupHint(
        markers: widget.markers,
        emptyMessage: widget.emptyMessage,
      );
    }

    final hasContent = widget.markers.isNotEmpty || widget.zones.isNotEmpty;
    final fallback = widget.fallbackCenter;
    final initial = widget.markers.isNotEmpty
        ? widget.markers.first.latLng
        : widget.zones.isNotEmpty
        ? widget.zones.first.center
        : fallback;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initial,
            zoom: hasContent ? 12 : 11,
          ),
          mapType: _mapType,
          markers: _googleMarkers,
          polylines: _polylines,
          circles: _circles,
          myLocationButtonEnabled: widget.myLocationEnabled,
          myLocationEnabled: widget.myLocationEnabled,
          zoomControlsEnabled: false,
          compassEnabled: true,
          mapToolbarEnabled: false,
          onCameraMove: (pos) {
            final next = pos.zoom;
            if ((next - _zoom).abs() < 0.15) return;
            setState(() => _zoom = next);
          },
          onMapCreated: (c) async {
            _controller = c;
            if (hasContent) await _fitContent();
          },
        ),
        if (!hasContent)
          Positioned(
            left: 16,
            right: 16,
            bottom: widget.legend != null ? 72 : 20,
            child: Material(
              elevation: 2,
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  widget.emptyMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        if (widget.showControls)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: _MapLayerToggles(
              showRoutes: _showRoutes,
              showZones: _showZones,
              clusterEnabled: _clusterEnabled,
              satellite: _isSatellite,
              routesAvailable: widget.routeMode != MapRouteMode.none,
              zonesAvailable: widget.zones.isNotEmpty,
              clusteringAvailable: widget.enableClustering,
              onRoutes: (v) {
                setState(() => _showRoutes = v);
                if (v) _loadRoadRoutes();
              },
              onZones: (v) => setState(() => _showZones = v),
              onCluster: (v) => setState(() => _clusterEnabled = v),
              onSatellite: (v) =>
                  _setMapType(v ? MapType.hybrid : MapType.normal),
              onFit: _fitContent,
            ),
          ),
        Positioned(
          right: 12,
          bottom: widget.legend != null ? 78 : 16,
          child: Material(
            elevation: 5,
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            child: InkWell(
              onTap: _toggleMapType,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isSatellite
                          ? Icons.map_rounded
                          : Icons.satellite_alt_rounded,
                      color: const Color(0xFF1565C0),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isSatellite ? 'Street map' : 'Satellite',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.legend != null)
          Positioned(left: 12, right: 12, bottom: 12, child: widget.legend!),
      ],
    );
  }
}

class _MapLayerToggles extends StatelessWidget {
  const _MapLayerToggles({
    required this.showRoutes,
    required this.showZones,
    required this.clusterEnabled,
    required this.satellite,
    required this.routesAvailable,
    required this.zonesAvailable,
    required this.clusteringAvailable,
    required this.onRoutes,
    required this.onZones,
    required this.onCluster,
    required this.onSatellite,
    required this.onFit,
  });

  final bool showRoutes;
  final bool showZones;
  final bool clusterEnabled;
  final bool satellite;
  final bool routesAvailable;
  final bool zonesAvailable;
  final bool clusteringAvailable;
  final ValueChanged<bool> onRoutes;
  final ValueChanged<bool> onZones;
  final ValueChanged<bool> onCluster;
  final ValueChanged<bool> onSatellite;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white.withValues(alpha: 0.94),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (routesAvailable)
              _ToggleChip(
                label: 'Routes',
                icon: Icons.alt_route_rounded,
                selected: showRoutes,
                onSelected: onRoutes,
              ),
            if (zonesAvailable) ...[
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'Zones',
                icon: Icons.radar_rounded,
                selected: showZones,
                onSelected: onZones,
              ),
            ],
            if (clusteringAvailable) ...[
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'Cluster',
                icon: Icons.bubble_chart_rounded,
                selected: clusterEnabled,
                onSelected: onCluster,
              ),
            ],
            const SizedBox(width: 6),
            _ToggleChip(
              label: satellite ? 'Satellite' : 'Street',
              icon: satellite
                  ? Icons.satellite_alt_rounded
                  : Icons.map_rounded,
              selected: satellite,
              onSelected: onSatellite,
            ),
            const SizedBox(width: 6),
            ActionChip(
              avatar: const Icon(Icons.fit_screen_rounded, size: 18),
              label: const Text('Fit'),
              onPressed: onFit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final ink = selected
        ? Theme.of(context).colorScheme.primary
        : kOnLight;
    return FilterChip(
      avatar: Icon(icon, size: 18, color: ink),
      label: Text(
        label,
        style: TextStyle(color: ink, fontWeight: FontWeight.w800),
      ),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      side: BorderSide(
        color: selected ? ink : const Color(0x33000000),
      ),
    );
  }
}

class _MapsSetupHint extends StatelessWidget {
  const _MapsSetupHint({required this.markers, required this.emptyMessage});

  final List<MapMarkerPoint> markers;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'Google Maps API key required',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'On web, pass --dart-define=GOOGLE_MAPS_API_KEY=your_key.\n'
              'On Android, set GOOGLE_MAPS_API_KEY in android/local.properties '
              'and do a full restart (not hot reload).',
              textAlign: TextAlign.center,
            ),
            if (markers.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${markers.length} location(s) loaded — map will appear once the key is set.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MapLegendCard extends StatelessWidget {
  const MapLegendCard({super.key, required this.items});

  final List<({Color color, String label})> items;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final item in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(item.label, style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
