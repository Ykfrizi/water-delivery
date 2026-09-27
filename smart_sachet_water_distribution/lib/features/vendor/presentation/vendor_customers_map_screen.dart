import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/maps/data/map_locations_repository.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_marker_point.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_zone_circle.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/service_area.dart';
import 'package:smart_sachet_water_distribution/features/maps/presentation/locations_map_view.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_delivery_nav_screen.dart';

/// Customer delivery locations, zones, and suggested delivery route.
class VendorCustomersMapScreen extends StatefulWidget {
  const VendorCustomersMapScreen({super.key});

  @override
  State<VendorCustomersMapScreen> createState() =>
      _VendorCustomersMapScreenState();
}

class _VendorCustomersMapScreenState extends State<VendorCustomersMapScreen> {
  List<MapMarkerPoint> _markers = [];
  List<MapZoneCircle> _zones = [];
  bool _loading = true;
  String? _error;
  bool _myLocation = false;
  MapType _mapType = MapType.normal;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poll = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final repo = MapLocationsRepository(context.read<Dio>());
    final hasPins = _markers.isNotEmpty;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final payload = await repo.vendorMapPayload(token);
      if (!mounted) return;
      final inHo = payload.customers
          .where((m) => ServiceArea.contains(m.latitude, m.longitude))
          .toList();
      final zones = [
        ServiceArea.zoneCircle,
        ...payload.zones.where(
          (z) => ServiceArea.contains(z.latitude, z.longitude),
        ),
      ];
      setState(() {
        _markers = inHo;
        _zones = zones;
        _loading = false;
        _error = null;
      });
      final issue = await const DeviceLocationService().permissionIssue();
      if (mounted && issue == null) {
        setState(() => _myLocation = true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (silent && hasPins) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && hasPins) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final greeting = context.select<AuthController, String>(
      (a) => a.session?.user.greeting ?? 'Hello!',
    );

    return Container(
        decoration: roleGradientDecoration(UserRole.vendor),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: greeting,
                subtitle:
                    'Ho delivery map · ${_markers.where((m) => m.kind == MapMarkerKind.customer).length} customers'
                    '${_zones.isEmpty ? '' : ' · ${_zones.length} zones'}',
                actions: [
                  HeaderIconButton(
                    icon: _mapType == MapType.normal
                        ? Icons.satellite_alt_rounded
                        : Icons.map_rounded,
                    onPressed: () {
                      setState(() {
                        _mapType = _mapType == MapType.normal
                            ? MapType.hybrid
                            : MapType.normal;
                      });
                    },
                    tooltip: _mapType == MapType.normal
                        ? 'Satellite view'
                        : 'Street map',
                  ),
                  HeaderIconButton(
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _load,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: kVendorMint,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  clipBehavior: Clip.none,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _load,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : LocationsMapView(
                          markers: _markers,
                          zones: _zones,
                          routeMode: MapRouteMode.deliverySequence,
                          myLocationEnabled: _myLocation,
                          mapType: _mapType,
                          onMapTypeChanged: (type) =>
                              setState(() => _mapType = type),
                          fallbackCenter: ServiceArea.center,
                          onMarkerTap: (m) {
                            if (m.kind != MapMarkerKind.customer) return;
                            final raw = m.id.startsWith('order-')
                                ? m.id.substring(6)
                                : m.id;
                            startVendorDeliveryNavigation(
                              context,
                              orderNumber: raw,
                            );
                          },
                          emptyMessage:
                              'Ho delivery map.\n'
                              'Customer pins appear from live GPS as soon as '
                              'they place an order — including before you '
                              'approve. Accept an order for turn-by-turn '
                              'directions.',
                          legend: const MapLegendCard(
                            items: [
                              (color: Colors.blue, label: 'Customer'),
                              (color: Colors.orange, label: 'Cluster'),
                              (color: kVendorGreen, label: 'Route'),
                              (color: kVendorGreen, label: 'Ho zone'),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}
