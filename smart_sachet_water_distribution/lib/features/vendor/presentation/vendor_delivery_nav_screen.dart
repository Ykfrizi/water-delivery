import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
import 'package:smart_sachet_water_distribution/core/config/maps_config.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/maps/data/directions_service.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_location_parser.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_route_builder.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/service_area.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens driver navigation to the customer after an order is accepted.
Future<void> startVendorDeliveryNavigation(
  BuildContext context, {
  required String orderNumber,
  Map<String, dynamic>? order,
}) async {
  final auth = context.read<AuthController>();
  final token = auth.session?.token;
  if (token == null) return;

  final api = VendorApi(context.read<Dio>());
  Map<String, dynamic> data = order ?? {};
  try {
    data = await api.getOrder(token, orderNumber);
  } catch (_) {
    if (data.isEmpty) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Could not load the order for navigation.');
      }
      return;
    }
  }

  final coords = parseCoordinates(data);
  if (coords == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Order accepted. No customer GPS pin yet — ask them to share '
            'location in Ho, or open the Customers map.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  final dest = LatLng(coords.lat, coords.lng);
  if (!ServiceArea.containsLatLng(dest)) {
    if (context.mounted) {
      showErrorSnackBar(context, ServiceArea.vendorOutsidePinMessage);
    }
    return;
  }

  final name = data['customer'] is Map
      ? (data['customer']['name'] ?? data['customer']['full_name'])?.toString()
      : data['customer_name']?.toString();
  final phone = customerPhoneFrom(data);

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VendorDeliveryNavScreen(
        orderNumber: orderNumber,
        destination: dest,
        customerName: name,
        customerPhone: phone,
      ),
    ),
  );
}

/// In-app driver map: live GPS, road route, next turn, satellite toggle.
class VendorDeliveryNavScreen extends StatefulWidget {
  const VendorDeliveryNavScreen({
    super.key,
    required this.orderNumber,
    required this.destination,
    this.customerName,
    this.customerPhone,
  });

  final String orderNumber;
  final LatLng destination;
  final String? customerName;
  final String? customerPhone;

  @override
  State<VendorDeliveryNavScreen> createState() =>
      _VendorDeliveryNavScreenState();
}

class _VendorDeliveryNavScreenState extends State<VendorDeliveryNavScreen> {
  static const _location = DeviceLocationService();

  GoogleMapController? _map;
  StreamSubscription<DevicePosition>? _gps;
  Timer? _publishTimer;
  DevicePosition? _me;
  DirectionsResult? _route;
  DirectionsStep? _nextStep;
  bool _follow = true;
  bool _loadingRoute = true;
  bool _navigating = false;
  MapType _mapType = MapType.normal;
  String? _error;
  DateTime _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _rerouteTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _gps?.cancel();
    _publishTimer?.cancel();
    _rerouteTimer?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final issue = await _location.permissionIssue();
    if (!mounted) return;
    if (issue != null) {
      setState(() {
        _error = issue;
        _loadingRoute = false;
      });
      return;
    }

    final pos = await _location.tryGetCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      setState(() => _me = pos);
      await _refreshRoute(pos);
      await _publishCourier(pos);
    } else {
      setState(() => _loadingRoute = false);
    }

    _gps = _location.watchPosition().listen((p) {
      if (!mounted) return;
      setState(() {
        _me = p;
        _nextStep = _stepFor(p);
      });
      if (_follow) _followCamera(p);
      final now = DateTime.now();
      if (now.difference(_lastPublish) >= const Duration(seconds: 20)) {
        _publishCourier(p);
      }
    });

    _publishTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!mounted) return;
      final me = _me;
      if (me != null) _publishCourier(me);
    });
  }

  Future<void> _refreshRoute(DevicePosition origin, {bool silent = false}) async {
    if (!silent && mounted) setState(() => _loadingRoute = true);
    final from = LatLng(origin.latitude, origin.longitude);
    final result = await DirectionsService(
      context.read<Dio>(),
    ).routeDetailed(origin: from, destination: widget.destination);
    if (!mounted) return;
    setState(() {
      _route =
          result ??
          DirectionsResult(
            polyline: [from, widget.destination],
            steps: const [],
            distanceText:
                '${MapRouteBuilder.haversineKm(from, widget.destination).toStringAsFixed(1)} km',
            durationText: '',
            distanceMeters:
                (MapRouteBuilder.haversineKm(from, widget.destination) * 1000)
                    .round(),
            durationSeconds: 0,
          );
      _nextStep = _stepFor(origin);
      _loadingRoute = false;
      _error = null;
    });
    if (!silent && !_navigating) await _fitOverview();
  }

  DirectionsStep? _stepFor(DevicePosition me) {
    final steps = _route?.steps;
    if (steps == null || steps.isEmpty) return null;
    final here = LatLng(me.latitude, me.longitude);
    DirectionsStep? best;
    var bestKm = double.infinity;
    for (final step in steps) {
      final d = MapRouteBuilder.haversineKm(here, step.end);
      if (d < bestKm) {
        bestKm = d;
        best = step;
      }
    }
    // Skip a step we've essentially arrived at.
    if (best != null && bestKm < 0.04) {
      final i = steps.indexOf(best);
      if (i >= 0 && i + 1 < steps.length) return steps[i + 1];
    }
    return best;
  }

  Future<void> _followCamera(DevicePosition pos) async {
    final c = _map;
    if (c == null) return;
    final heading = pos.heading;
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 16.4,
          tilt: 48,
          bearing: (heading != null && heading >= 0) ? heading : 0,
        ),
      ),
    );
  }

  Future<void> _fitOverview() async {
    final c = _map;
    final me = _me;
    if (c == null || me == null) return;
    final pts = <LatLng>[
      LatLng(me.latitude, me.longitude),
      widget.destination,
      ...?_route?.polyline,
    ];
    if (pts.isEmpty || !mounted) return;
    var minLat = pts.first.latitude;
    var maxLat = pts.first.latitude;
    var minLng = pts.first.longitude;
    var maxLng = pts.first.longitude;
    for (final p in pts.skip(1)) {
      minLat = minLat < p.latitude ? minLat : p.latitude;
      maxLat = maxLat > p.latitude ? maxLat : p.latitude;
      minLng = minLng < p.longitude ? minLng : p.longitude;
      maxLng = maxLng > p.longitude ? maxLng : p.longitude;
    }
    if (!mounted) return;
    if (minLat == maxLat && minLng == maxLng) {
      await c.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 15),
      );
      return;
    }
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  Future<void> _publishCourier(DevicePosition pos) async {
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    _lastPublish = DateTime.now();
    try {
      await VendorApi(context.read<Dio>()).updateCourierLocation(
        token,
        widget.orderNumber,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (_) {}
  }

  Future<void> _startInAppNavigation() async {
    setState(() {
      _navigating = true;
      _follow = true;
      _error = null;
    });
    var pos = _me;
    pos ??= await _location.tryGetCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() {
        _error = 'Turn on GPS so we can navigate in this map.';
        _navigating = false;
      });
      return;
    }
    setState(() => _me = pos);
    await _refreshRoute(pos);
    await _followCamera(pos);
    _rerouteTimer?.cancel();
    _rerouteTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      final p = _me;
      if (p != null) unawaited(_refreshRoute(p, silent: true));
    });
  }

  void _stopInAppNavigation() {
    _rerouteTimer?.cancel();
    _rerouteTimer = null;
    if (mounted) setState(() => _navigating = false);
  }

  Future<void> _callCustomer() async {
    final raw = widget.customerPhone?.trim() ?? '';
    if (raw.isEmpty) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'This customer has not shared a phone number yet.',
        );
      }
      return;
    }
    final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      showErrorSnackBar(context, 'Could not open the phone dialer.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = vendorAppTheme();
    final accent = roleAccent(UserRole.vendor);
    final me = _me;
    final route = _route;
    final step = _nextStep;
    final customer = widget.customerName?.trim();
    final phone = widget.customerPhone?.trim();

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: kVendorGreenDeep,
        body: Stack(
          children: [
            if (!MapsConfig.isConfigured)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Configure Google Maps to navigate.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: me != null
                      ? LatLng(me.latitude, me.longitude)
                      : ServiceArea.center,
                  zoom: 15,
                  tilt: 30,
                ),
                mapType: _mapType,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                compassEnabled: true,
                trafficEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                polylines: {
                  if (route != null && route.polyline.length >= 2)
                    Polyline(
                      polylineId: const PolylineId('drive'),
                      points: route.polyline,
                      color: accent,
                      width: 6,
                    ),
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('customer'),
                    position: widget.destination,
                    infoWindow: InfoWindow(
                      title: customer?.isNotEmpty == true
                          ? customer!
                          : 'Customer',
                      snippet: 'Delivery in Ho',
                    ),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
                  ),
                },
                onMapCreated: (c) => _map = c,
                onCameraMoveStarted: () {
                  // Driver panned away — don't fight them.
                },
              ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          onPressed: () {
                            setState(() {
                              _mapType = _mapType == MapType.hybrid ||
                                      _mapType == MapType.satellite
                                  ? MapType.normal
                                  : MapType.hybrid;
                            });
                          },
                          icon: Icon(
                            _mapType == MapType.normal
                                ? Icons.satellite_alt_rounded
                                : Icons.map_rounded,
                          ),
                          tooltip: _mapType == MapType.normal
                              ? 'Satellite'
                              : 'Street map',
                        ),
                        IconButton.filledTonal(
                          onPressed: () {
                            setState(() => _follow = !_follow);
                            final p = _me;
                            if (_follow && p != null) _followCamera(p);
                          },
                          icon: Icon(
                            _follow
                                ? Icons.navigation_rounded
                                : Icons.navigation_outlined,
                          ),
                          tooltip: _follow ? 'Following you' : 'Follow me',
                        ),
                        IconButton.filledTonal(
                          onPressed: _fitOverview,
                          icon: const Icon(Icons.fit_screen_rounded),
                          tooltip: 'Show full route',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Material(
                      color: Colors.white,
                      elevation: 6,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: _loadingRoute
                            ? const Row(
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Getting directions in Ho…'),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step?.instruction ??
                                        'Drive to the customer in Ho',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      if (route?.durationText.isNotEmpty ==
                                          true)
                                        route!.durationText,
                                      if (route?.distanceText.isNotEmpty ==
                                          true)
                                        route!.distanceText,
                                      if (customer != null &&
                                          customer.isNotEmpty)
                                        customer,
                                      if (phone != null && phone.isNotEmpty)
                                        phone,
                                      'Order #${widget.orderNumber}',
                                    ].join(' · '),
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _error!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (phone != null && phone.isNotEmpty) ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _callCustomer,
                            icon: const Icon(Icons.call_rounded),
                            label: Text('Call $phone'),
                          ),
                          const SizedBox(height: 8),
                        ],
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _navigating
                              ? _stopInAppNavigation
                              : _startInAppNavigation,
                          icon: Icon(
                            _navigating
                                ? Icons.stop_rounded
                                : Icons.navigation_rounded,
                          ),
                          label: Text(
                            _navigating
                                ? 'Stop navigation'
                                : 'Start navigation',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _navigating
                              ? 'Navigating in this map · follow the green route'
                              : 'Directions stay in this screen — satellite or normal map',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
