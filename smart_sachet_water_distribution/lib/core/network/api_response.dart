List<Map<String, dynamic>> _mapsFromList(List list) {
  final out = <Map<String, dynamic>>[];
  for (final e in list) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    // JSON:API / nested resource: { type, id, attributes: {...} }
    final attrs = m['attributes'];
    if (attrs is Map) {
      final merged = Map<String, dynamic>.from(attrs);
      if (m['id'] != null) merged.putIfAbsent('id', () => m['id']);
      out.add(merged);
    } else {
      out.add(m);
    }
  }
  return out;
}

List<Map<String, dynamic>>? _listFromMap(Map<String, dynamic> m) {
  List<Map<String, dynamic>>? emptyCandidate;

  for (final key in const [
    'data',
    'products',
    'items',
    'results',
    'records',
    'catalog',
  ]) {
    final v = m[key];
    if (v is List) {
      final list = _mapsFromList(v);
      if (list.isNotEmpty) return list;
      emptyCandidate ??= list;
    } else if (v is Map) {
      final nested = _listFromMap(Map<String, dynamic>.from(v));
      if (nested != null && nested.isNotEmpty) return nested;
      if (nested != null) emptyCandidate ??= nested;
    }
  }

  // Numeric-keyed map masquerading as a list: { "0": {...}, "1": {...} }
  final numericMaps = <Map<String, dynamic>>[];
  var allNumeric = m.isNotEmpty;
  for (final e in m.entries) {
    if (int.tryParse(e.key.toString()) == null || e.value is! Map) {
      allNumeric = false;
      break;
    }
    numericMaps.add(Map<String, dynamic>.from(e.value as Map));
  }
  if (allNumeric && numericMaps.isNotEmpty) return numericMaps;

  return emptyCandidate;
}

/// Shared decoding for Laravel-style JSON: `{ data: [...] }` or raw lists/maps.
List<Map<String, dynamic>> decodeDataList(dynamic body) {
  if (body == null) return [];
  if (body is List) return _mapsFromList(body);
  if (body is Map) {
    return _listFromMap(Map<String, dynamic>.from(body)) ?? [];
  }
  return [];
}

/// Pulls a product list from a vendor profile / detail payload when products
/// are embedded instead of (or in addition to) a dedicated products endpoint.
List<Map<String, dynamic>> productsFromPayload(dynamic body) {
  final direct = decodeDataList(body);
  if (direct.isNotEmpty) return direct;

  if (body is! Map) return [];
  final root = Map<String, dynamic>.from(body);
  final unwrapped = unwrapDataMap(root);

  for (final source in [unwrapped, root]) {
    for (final key in const ['products', 'catalog', 'items']) {
      final v = source[key];
      if (v is List) {
        final list = _mapsFromList(v);
        if (list.isNotEmpty) return list;
      }
    }
  }
  return [];
}

Map<String, dynamic> unwrapDataMap(dynamic data) {
  if (data == null) return {};
  if (data is Map<String, dynamic>) {
    final inner = data['data'];
    if (inner is Map) {
      return Map<String, dynamic>.from(inner);
    }
    return data;
  }
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  return {};
}

/// Parses id from dynamic JSON (int or string).
int? parseId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

/// Reads resource id from list/detail JSON (flat or nested).
dynamic resourceIdFrom(Map<String, dynamic> row) {
  final direct = row['id'] ?? row['product_id'] ?? row['uuid'];
  if (direct != null) return direct;

  final product = row['product'];
  if (product is Map) {
    final p = Map<String, dynamic>.from(product);
    return p['id'] ?? p['product_id'] ?? p['uuid'];
  }
  return null;
}

/// Safe segment for `/resource/{id}` URLs (integer, UUID, slug).
String apiPathSegment(dynamic id) {
  if (id == null) return '';
  if (id is int) return id.toString();
  if (id is double) {
    final asInt = id.toInt();
    if (id == asInt.toDouble()) return asInt.toString();
  }
  final asInt = int.tryParse(id.toString());
  if (asInt != null && id.toString() == asInt.toString()) {
    return asInt.toString();
  }
  return Uri.encodeComponent(id.toString());
}
