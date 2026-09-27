import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/maps/data/map_locations_repository.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_marker_point.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_zone_circle.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/service_area.dart';
import 'package:smart_sachet_water_distribution/features/maps/presentation/locations_map_view.dart';

enum _AdminMapFilter { all, vendors, customers }

/// Admin operations map — vendors, customers, routes, and zones.
class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  List<MapMarkerPoint> _vendors = [];
  List<MapMarkerPoint> _customers = [];
  List<MapZoneCircle> _zones = [];
  bool _loading = true;
  String? _error;
  _AdminMapFilter _filter = _AdminMapFilter.all;
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
    final hasPins = _vendors.isNotEmpty || _customers.isNotEmpty;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await repo.adminMapPayload(token);
      if (!mounted) return;
      setState(() {
        _vendors = result.vendors;
        _customers = result.customers;
        _zones = result.zones;
        _loading = false;
        _error = null;
      });
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

  List<MapMarkerPoint> get _visibleMarkers {
    return switch (_filter) {
      _AdminMapFilter.all => [..._vendors, ..._customers],
      _AdminMapFilter.vendors => _vendors,
      _AdminMapFilter.customers => _customers,
    };
  }

  Widget _mapBody() {
    if (_loading && _vendors.isEmpty && _customers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _vendors.isEmpty && _customers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return LocationsMapView(
      markers: _visibleMarkers,
      zones: _filter == _AdminMapFilter.customers ? const [] : _zones,
      routeMode: MapRouteMode.vendorToCustomer,
      initialShowRoutes: false,
      mapType: _mapType,
      onMapTypeChanged: (type) => setState(() => _mapType = type),
      fallbackCenter: ServiceArea.center,
      emptyMessage:
          'No map pins yet.\n'
          'Vendors and customers appear from live GPS. Keep those apps open '
          'with location on — pending-order customers show here too.',
      legend: const MapLegendCard(
        items: [
          (color: Colors.green, label: 'Vendor'),
          (color: Colors.blue, label: 'Customer'),
          (color: Colors.orange, label: 'Cluster'),
          (color: kAdminCyan, label: 'Route'),
          (color: kAdminCyan, label: 'Zone'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(UserRole.admin);

    return Scaffold(
      body: Container(
        decoration: roleGradientDecoration(UserRole.admin),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: 'Operations map',
                subtitle:
                    '${_vendors.length} vendors · ${_customers.length} customers',
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    HeaderFilterChip(
                      label: 'All',
                      selected: _filter == _AdminMapFilter.all,
                      onSelected: (_) =>
                          setState(() => _filter = _AdminMapFilter.all),
                      accent: accent,
                      showCheckmark: false,
                    ),
                    HeaderFilterChip(
                      label: 'Vendors ${_vendors.length}',
                      selected: _filter == _AdminMapFilter.vendors,
                      onSelected: (_) =>
                          setState(() => _filter = _AdminMapFilter.vendors),
                      accent: accent,
                      showCheckmark: false,
                    ),
                    HeaderFilterChip(
                      label: 'Customers ${_customers.length}',
                      selected: _filter == _AdminMapFilter.customers,
                      onSelected: (_) => setState(
                        () => _filter = _AdminMapFilter.customers,
                      ),
                      accent: accent,
                      showCheckmark: false,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  clipBehavior: Clip.none,
                  child: _mapBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
