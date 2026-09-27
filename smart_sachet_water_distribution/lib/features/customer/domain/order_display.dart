import 'package:smart_sachet_water_distribution/core/money/currency.dart';

/// Extracts line rows from various order JSON shapes.
List<Map<String, dynamic>> orderLineItems(Map<String, dynamic> order) {
  for (final key in ['items', 'order_items', 'lines', 'products']) {
    final v = order[key];
    if (v is List) {
      return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  }
  return [];
}

String orderLineTitle(Map<String, dynamic> line) {
  final p = line['product'];
  if (p is Map) {
    return (p['name'] ?? p['title'] ?? 'Item').toString();
  }
  return (line['product_name'] ??
          line['name'] ??
          line['title'] ??
          'Item')
      .toString();
}

String? orderLineQty(Map<String, dynamic> line) {
  return line['quantity']?.toString() ??
      line['qty']?.toString() ??
      line['count']?.toString();
}

String? orderLinePrice(Map<String, dynamic> line) {
  final p = line['price'] ?? line['unit_price'] ?? line['total'] ?? line['amount'];
  if (p == null) return null;
  final currency = line['currency']?.toString() ??
      (line['product'] is Map
          ? (line['product'] as Map)['currency']?.toString()
          : null);
  return formatMoneyDynamic(p, currency: currency);
}

String prettyTotals(dynamic v) => prettyMoneyTotals(v);

bool orderIsDelivered(Map<String, dynamic> order) {
  final s = (order['status'] ?? '').toString().toLowerCase().trim();
  return s == 'delivered' || s == 'completed';
}

/// Human-readable drop-off lines. Hides GPS coordinates and raw JSON keys.
List<String> customerShippingLines(dynamic shipping) {
  if (shipping is! Map) return const [];
  final ship = Map<String, dynamic>.from(shipping);
  final parts = <String>[];
  for (final key in const [
    'line1',
    'address',
    'street',
    'address_line',
    'line2',
  ]) {
    final v = ship[key]?.toString().trim();
    if (v != null && v.isNotEmpty && !parts.contains(v)) parts.add(v);
  }
  final locality = <String>[];
  for (final key in const ['city', 'town', 'region', 'state']) {
    final v = ship[key]?.toString().trim();
    if (v != null && v.isNotEmpty && !locality.contains(v)) locality.add(v);
  }
  if (locality.isNotEmpty) parts.add(locality.join(', '));
  final phone = (ship['phone'] ?? ship['mobile'])?.toString().trim();
  if (phone != null && phone.isNotEmpty) parts.add('Phone $phone');
  return parts;
}

String? orderVendorName(Map<String, dynamic> order) {
  final vendor = order['vendor'];
  if (vendor is Map) {
    for (final key in const ['business_name', 'name', 'shop_name']) {
      final name = vendor[key]?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
  }
  for (final key in const ['vendor_name', 'shop_name', 'business_name']) {
    final name = order[key]?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

String? orderVendorSlug(Map<String, dynamic> order) {
  final vendor = order['vendor'];
  if (vendor is Map) {
    final slug = (vendor['slug'] ?? vendor['vendor_slug'] ?? '').toString().trim();
    if (slug.isNotEmpty) return slug;
  }
  for (final key in ['vendor_slug', 'vendorSlug']) {
    final slug = order[key]?.toString().trim();
    if (slug != null && slug.isNotEmpty) return slug;
  }
  return null;
}
