import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_orders_api.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_vendors_api.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_location_parser.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_marker_point.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_zone_circle.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/data/marketplace_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';

/// Loads map markers + delivery zones from API responses.
class MapLocationsRepository {
  MapLocationsRepository(this._dio);

  final Dio _dio;

  Future<({List<MapMarkerPoint> customers, List<MapZoneCircle> zones})>
  vendorMapPayload(String token) async {
    final api = VendorApi(_dio);
    final orders = await api.listOrders(token, perPage: 100);
    final markers = <MapMarkerPoint>[];
    var detailLookups = 0;
    for (final order in orders) {
      var m = markerFromOrder(order);
      if (m == null && detailLookups < 25) {
        final num =
            (order['order_number'] ?? order['orderNumber'] ?? order['id'])
                ?.toString();
        if (num != null && num.isNotEmpty) {
          try {
            final detail = await api.getOrder(token, num);
            m = markerFromOrder(detail);
            detailLookups++;
          } catch (_) {}
        }
      }
      if (m != null) markers.add(m);
    }

    try {
      final profile = await api.getProfile(token);
      final store = markerFromVendor(profile);
      if (store != null) markers.add(store);
    } catch (_) {}

    final zones = <MapZoneCircle>[];
    try {
      final zoneRows = await api.listZones(token);
      for (final row in zoneRows) {
        final z = MapZoneCircle.fromJson(row, color: const Color(0xFF5E35B1));
        if (z != null) zones.add(z);
      }
    } catch (_) {}

    return (customers: uniqueMarkers(markers), zones: zones);
  }

  /// Backward-compatible helper used by older call sites.
  Future<List<MapMarkerPoint>> vendorCustomerLocations(String token) async {
    final payload = await vendorMapPayload(token);
    return payload.customers;
  }

  Future<
    ({
      List<MapMarkerPoint> vendors,
      List<MapMarkerPoint> customers,
      List<MapZoneCircle> zones,
    })
  >
  adminMapPayload(String token) async {
    final fromEndpoint = await _tryAdminMapEndpoint(token);
    var vendors = fromEndpoint?.vendors ?? <MapMarkerPoint>[];
    var customers = fromEndpoint?.customers ?? <MapMarkerPoint>[];
    final zones = <MapZoneCircle>[];

    if (fromEndpoint == null) {
      final loaded = await adminLocations(token);
      vendors = loaded.vendors;
      customers = loaded.customers;
      zones.addAll(loaded.zones);
    } else {
      zones.addAll(fromEndpoint.zones);
    }

    if (zones.isEmpty) {
      for (final v in vendors) {
        zones.add(
          MapZoneCircle(
            id: 'coverage-${v.id}',
            latitude: v.latitude,
            longitude: v.longitude,
            radiusKm: 3,
            name: '${v.title} coverage',
            color: const Color(0xFF2E7D32),
          ),
        );
      }
    }

    return (
      vendors: uniqueMarkers(vendors),
      customers: uniqueMarkers(customers),
      zones: zones,
    );
  }

  Future<
    ({
      List<MapMarkerPoint> vendors,
      List<MapMarkerPoint> customers,
      List<MapZoneCircle> zones,
    })
  >
  adminLocations(String token) async {
    final customers = <MapMarkerPoint>[];
    final vendors = <MapMarkerPoint>[];
    final zones = <MapZoneCircle>[];

    try {
      final ordersApi = AdminOrdersApi(_dio);
      final orders = await ordersApi.listOrders(token, perPage: 100);
      var detailLookups = 0;
      for (final summary in orders) {
        var marker = markerFromOrder(summary.raw);
        if (marker == null &&
            summary.orderNumber.isNotEmpty &&
            detailLookups < 12) {
          try {
            final detail = await ordersApi.getOrder(token, summary.orderNumber);
            marker = markerFromOrder(detail);
            detailLookups++;
          } catch (_) {}
        }
        if (marker != null) customers.add(marker);
      }
    } catch (_) {}

    try {
      final vendorsApi = AdminVendorsApi(_dio);
      final rows = await vendorsApi.listVendors(token, perPage: 100);
      var profileLookups = 0;
      for (final v in rows) {
        var marker = markerFromVendor(v.raw);
        _collectZones(v.raw, zones);
        if (marker == null && v.slug.isNotEmpty && profileLookups < 20) {
          try {
            final profile = await vendorsApi.getVendor(token, v.slug);
            marker = markerFromVendor(profile);
            _collectZones(profile, zones);
            profileLookups++;
          } catch (_) {}
        }
        if (marker != null) vendors.add(marker);
      }
    } catch (_) {
      try {
        final market = MarketplaceApi(_dio);
        final vendorRows = await market.listVendors(perPage: 100);
        for (final v in vendorRows) {
          final m = markerFromVendor(v.raw);
          if (m != null) vendors.add(m);
        }
      } catch (_) {}
    }

    return (
      vendors: uniqueMarkers(vendors),
      customers: uniqueMarkers(customers),
      zones: zones,
    );
  }

  void _collectZones(Map<String, dynamic> json, List<MapZoneCircle> out) {
    for (final key in const ['delivery_zones', 'zones', 'coverage_zones']) {
      final list = json[key];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final z = MapZoneCircle.fromJson(
          Map<String, dynamic>.from(item),
          color: const Color(0xFF2E7D32),
        );
        if (z != null) out.add(z);
      }
    }
  }

  Future<
    ({
      List<MapMarkerPoint> vendors,
      List<MapMarkerPoint> customers,
      List<MapZoneCircle> zones,
    })?
  >
  _tryAdminMapEndpoint(String token) async {
    for (final path in const [
      '/admin/map',
      '/admin/maps',
      '/admin/locations',
    ]) {
      try {
        final r = await _dio.get<dynamic>(
          path,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        if (!isSuccess(r)) continue;
        final body = unwrapDataMap(r.data);
        final vendors = <MapMarkerPoint>[];
        final customers = <MapMarkerPoint>[];
        final zones = <MapZoneCircle>[];

        void ingestList(dynamic list, MapMarkerKind kind) {
          if (list is! List) return;
          for (final item in list) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);
            final marker = kind == MapMarkerKind.vendor
                ? markerFromVendor(map)
                : markerFromOrder(map, kind: kind);
            if (marker != null) {
              if (kind == MapMarkerKind.vendor) {
                vendors.add(marker);
              } else {
                customers.add(marker);
              }
            }
            _collectZones(map, zones);
          }
        }

        ingestList(body['vendors'], MapMarkerKind.vendor);
        ingestList(body['customers'], MapMarkerKind.customer);
        ingestList(body['orders'], MapMarkerKind.customer);
        _collectZones(body, zones);

        if (vendors.isNotEmpty || customers.isNotEmpty) {
          return (
            vendors: uniqueMarkers(vendors),
            customers: uniqueMarkers(customers),
            zones: zones,
          );
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
