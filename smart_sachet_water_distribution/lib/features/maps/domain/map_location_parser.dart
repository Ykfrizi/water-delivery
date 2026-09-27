import 'dart:convert';

import 'package:smart_sachet_water_distribution/features/maps/domain/map_marker_point.dart';

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty || s == 'null') return null;
  return double.tryParse(s);
}

bool _valid(double lat, double lng) =>
    lat.abs() <= 90 && lng.abs() <= 180 && !(lat == 0 && lng == 0);

({double lat, double lng})? _pair(dynamic lat, dynamic lng) {
  final a = _asDouble(lat);
  final b = _asDouble(lng);
  if (a == null || b == null || !_valid(a, b)) return null;
  return (lat: a, lng: b);
}

/// Extracts latitude/longitude from flexible API JSON shapes.
({double lat, double lng})? parseCoordinates(Map<String, dynamic> json) {
  final direct = _pair(
    json['latitude'] ??
        json['lat'] ??
        json['last_latitude'] ??
        json['customer_latitude'] ??
        json['delivery_latitude'] ??
        json['shipping_latitude'] ??
        json['gps_lat'],
    json['longitude'] ??
        json['lng'] ??
        json['lon'] ??
        json['long'] ??
        json['last_longitude'] ??
        json['customer_longitude'] ??
        json['delivery_longitude'] ??
        json['shipping_longitude'] ??
        json['gps_lng'],
  );
  if (direct != null) return direct;

  for (final key in const [
    'shipping_address',
    'delivery_address',
    'address',
    'customer_location',
    'delivery_location',
    'location',
    'geo',
    'coordinates',
    'gps',
    'meta',
    'metadata',
  ]) {
    final nested = json[key];
    final parsed = _fromDynamic(nested);
    if (parsed != null) return parsed;
  }

  final customer = json['customer'];
  if (customer is Map) {
    final parsed = parseCoordinates(Map<String, dynamic>.from(customer));
    if (parsed != null) return parsed;
  }

  return null;
}

({double lat, double lng})? _fromDynamic(dynamic nested) {
  if (nested == null) return null;
  if (nested is Map) {
    return parseCoordinates(Map<String, dynamic>.from(nested));
  }
  if (nested is List && nested.length >= 2) {
    // GeoJSON is [lng, lat]; also accept [lat, lng] if first value looks like lat.
    final a = _asDouble(nested[0]);
    final b = _asDouble(nested[1]);
    if (a == null || b == null) return null;
    if (a.abs() <= 90 && b.abs() <= 180 && _valid(a, b)) {
      return (lat: a, lng: b);
    }
    if (_valid(b, a)) return (lat: b, lng: a);
  }
  if (nested is String) {
    final s = nested.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('{') || s.startsWith('[')) {
      try {
        return _fromDynamic(jsonDecode(s));
      } catch (_) {}
    }
    final parts = s.split(RegExp(r'[,\s]+'));
    if (parts.length >= 2) {
      return _pair(parts[0], parts[1]);
    }
  }
  return null;
}

String _orderLabel(Map<String, dynamic> order) {
  final n = order['order_number'] ?? order['orderNumber'];
  if (n != null && n.toString().trim().isNotEmpty) {
    return 'Order #$n';
  }
  if (order['live'] == true) return 'Live GPS';
  final id = order['id'];
  return id == null ? 'Customer' : 'Customer #$id';
}

String? _personLabel(Map<String, dynamic> json) {
  final customer = json['customer'];
  if (customer is Map) {
    final name = customer['name'] ?? customer['full_name'];
    final email = customer['email'];
    if (name != null) return name.toString();
    if (email != null) return email.toString();
  }
  return json['customer_name']?.toString() ??
      json['customer_email']?.toString() ??
      json['buyer_name']?.toString() ??
      json['buyer_email']?.toString() ??
      json['name']?.toString() ??
      json['business_name']?.toString();
}

MapMarkerPoint? markerFromOrder(
  Map<String, dynamic> order, {
  MapMarkerKind kind = MapMarkerKind.customer,
}) {
  final coords = parseCoordinates(order);
  if (coords == null) return null;

  final id =
      (order['order_number'] ??
              order['orderNumber'] ??
              order['id'] ??
              '${coords.lat},${coords.lng}')
          .toString();
  final person = _personLabel(order);
  return MapMarkerPoint(
    id: 'order-$id',
    latitude: coords.lat,
    longitude: coords.lng,
    title: person ?? _orderLabel(order),
    subtitle: _orderLabel(order),
    kind: kind,
  );
}

MapMarkerPoint? markerFromVendor(Map<String, dynamic> vendor) {
  final coords = parseCoordinates(vendor);
  if (coords == null) return null;

  final slug = (vendor['slug'] ?? vendor['id'] ?? vendor['name']).toString();
  final name = (vendor['name'] ?? vendor['business_name'] ?? 'Vendor')
      .toString();
  return MapMarkerPoint(
    id: 'vendor-$slug',
    latitude: coords.lat,
    longitude: coords.lng,
    title: name,
    subtitle: slug,
    kind: MapMarkerKind.vendor,
  );
}

List<MapMarkerPoint> uniqueMarkers(List<MapMarkerPoint> input) {
  final seen = <String>{};
  final out = <MapMarkerPoint>[];
  for (final m in input) {
    if (seen.add(m.id)) out.add(m);
  }
  return out;
}

String? customerPhoneFrom(Map<String, dynamic> json) {
  final customer = json['customer'];
  if (customer is Map) {
    final phone = (customer['phone'] ?? customer['mobile'])?.toString().trim();
    if (phone != null && phone.isNotEmpty) return phone;
  }
  for (final key in const ['customer_phone', 'phone', 'mobile']) {
    final v = json[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  final ship = json['shipping_address'];
  if (ship is Map) {
    final phone = (ship['phone'] ?? ship['mobile'])?.toString().trim();
    if (phone != null && phone.isNotEmpty) return phone;
  }
  return null;
}
