/// Laravel-style paginated list metadata.
class PaginatedResult<T> {
  const PaginatedResult({
    required this.items,
    this.page = 1,
    this.perPage = 20,
    this.total,
    this.lastPage,
  });

  final List<T> items;
  final int page;
  final int perPage;
  final int? total;
  final int? lastPage;

  bool get hasMore {
    if (lastPage != null) return page < lastPage!;
    if (total != null) return page * perPage < total!;
    return items.length >= perPage;
  }

  PaginatedResult<T> append(PaginatedResult<T> next) {
    return PaginatedResult(
      items: [...items, ...next.items],
      page: next.page,
      perPage: next.perPage,
      total: next.total ?? total,
      lastPage: next.lastPage ?? lastPage,
    );
  }
}

/// Parses common Laravel pagination envelopes.
PaginatedResult<Map<String, dynamic>> parsePaginatedMaps(
  dynamic body, {
  required int page,
  required int perPage,
  required List<Map<String, dynamic>> Function(dynamic) decodeList,
}) {
  final items = decodeList(body);
  int? total;
  int? lastPage;
  int resolvedPage = page;
  int resolvedPerPage = perPage;

  if (body is Map) {
    final meta = body['meta'];
    final map = meta is Map ? Map<String, dynamic>.from(meta) : body;
    total = int.tryParse((map['total'] ?? body['total'])?.toString() ?? '');
    lastPage = int.tryParse(
      (map['last_page'] ?? body['last_page'])?.toString() ?? '',
    );
    resolvedPage = int.tryParse(
          (map['current_page'] ?? body['current_page'])?.toString() ?? '',
        ) ??
        page;
    resolvedPerPage = int.tryParse(
          (map['per_page'] ?? body['per_page'])?.toString() ?? '',
        ) ??
        perPage;
  }

  return PaginatedResult(
    items: items,
    page: resolvedPage,
    perPage: resolvedPerPage,
    total: total,
    lastPage: lastPage,
  );
}
