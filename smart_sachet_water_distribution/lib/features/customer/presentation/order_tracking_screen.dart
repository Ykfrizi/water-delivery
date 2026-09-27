import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/config/maps_config.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_tracking.dart';
import 'package:smart_sachet_water_distribution/features/maps/data/directions_service.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/service_area.dart';

/// Live map for an in-progress delivery (courier GPS + destination).
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({
    super.key,
    required this.orderNumber,
    this.initialOrder,
  });

  final String orderNumber;
  final Map<String, dynamic>? initialOrder;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Map<String, dynamic>? _order;
  OrderTrackingSnapshot? _snap;
  List<LatLng> _roadPath = const [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    if (_order != null) {
      _snap = OrderTrackingSnapshot.fromOrder(_order!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthController>();
    final api = CustomerApi(context.read<Dio>());
    final token = auth.token;
    if (token == null) return;
    try {
      Map<String, dynamic> order;
      try {
        order = await api.getOrderTracking(
          token,
          widget.orderNumber,
        );
      } on ApiException {
        order = await api.getOrder(token, widget.orderNumber);
      }
      final snap = OrderTrackingSnapshot.fromOrder(order);
      var path = <LatLng>[];
      final from = snap.courier ?? snap.vendor;
      final to = snap.destination;
      if (from != null && to != null) {
        path = await DirectionsService(
          context.read<Dio>(),
        ).route(origin: from, destination: to);
        if (path.isEmpty) path = [from, to];
      }
      if (!mounted) return;
      setState(() {
        _order = order;
        _snap = snap;
        _roadPath = path;
        _loading = false;
        _error = null;
      });
      await _fit();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fit() async {
    final c = _map;
    final snap = _snap;
    if (c == null || snap == null) return;
    final pts = <LatLng>[
      if (snap.courier != null) snap.courier!,
      if (snap.destination != null) snap.destination!,
      if (snap.vendor != null) snap.vendor!,
      ..._roadPath,
    ];
    if (pts.isEmpty || !mounted) return;
    if (pts.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
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
        64,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = customerAppTheme();
    final snap = _snap;

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Track #${widget.orderNumber}'),
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Material(
              color: snap?.isLive == true
                  ? kCustomerBlue.withValues(alpha: 0.12)
                  : kCustomerGray,
              child: ListTile(
                leading: Icon(
                  snap?.isLive == true
                      ? Icons.delivery_dining_rounded
                      : Icons.info_outline_rounded,
                  color: kCustomerBlue,
                ),
                title: Text(
                  snap == null ? 'Loading tracking…' : 'Status: ${snap.status}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  [
                    if (snap?.etaMinutes != null)
                      'ETA ~${snap!.etaMinutes} min',
                    if (snap?.updatedAt != null) 'Updated ${snap!.updatedAt}',
                    if (snap?.isLive != true)
                      'Live map unlocks when the order is out for delivery.',
                  ].where((e) => e.isNotEmpty).join(' · '),
                ),
              ),
            ),
            Expanded(
              child: _loading && snap == null
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && snap == null
                  ? Center(child: Text(_error!))
                  : !MapsConfig.isConfigured
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Configure Google Maps to see live tracking.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : snap == null || !snap.canShowMap
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Courier location is not available yet. '
                          'Pull to refresh once delivery starts.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target:
                            snap.courier ??
                            snap.destination ??
                            snap.vendor ??
                            ServiceArea.center,
                        zoom: 13,
                      ),
                      myLocationButtonEnabled: false,
                      markers: {
                        if (snap.courier != null)
                          Marker(
                            markerId: const MarkerId('courier'),
                            position: snap.courier!,
                            infoWindow: const InfoWindow(title: 'Courier'),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueAzure,
                            ),
                          ),
                        if (snap.destination != null)
                          Marker(
                            markerId: const MarkerId('destination'),
                            position: snap.destination!,
                            infoWindow: const InfoWindow(
                              title: 'Delivery address',
                            ),
                          ),
                        if (snap.vendor != null)
                          Marker(
                            markerId: const MarkerId('vendor'),
                            position: snap.vendor!,
                            infoWindow: const InfoWindow(title: 'Vendor'),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueViolet,
                            ),
                          ),
                      },
                      polylines: {
                        if (_roadPath.length >= 2)
                          Polyline(
                            polylineId: const PolylineId('road'),
                            points: _roadPath,
                            color: kCustomerBlue,
                            width: 5,
                          ),
                      },
                      onMapCreated: (c) {
                        _map = c;
                        _fit();
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
