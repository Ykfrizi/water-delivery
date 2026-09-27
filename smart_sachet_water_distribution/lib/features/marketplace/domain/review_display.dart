/// Shared parsing for review JSON from marketplace / vendor / customer APIs.
String reviewAuthorName(Map<String, dynamic> review) {
  final customer = review['customer'];
  if (customer is Map) {
    final name = (customer['name'] ?? customer['full_name'])?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
  }
  for (final key in const ['customer_name', 'user_name', 'author', 'name']) {
    final v = review[key]?.toString().trim();
    if (v != null && v.isNotEmpty && v.toLowerCase() != 'customer') return v;
  }
  return 'Customer';
}

int reviewStarRating(Map<String, dynamic> review) {
  return int.tryParse(
        (review['rating'] ?? review['stars'] ?? review['score'] ?? '0')
            .toString(),
      ) ??
      0;
}

String reviewComment(Map<String, dynamic> review) {
  return (review['comment'] ?? review['body'] ?? review['review'] ?? '')
      .toString()
      .trim();
}

String reviewDateLabel(Map<String, dynamic> review) {
  final raw = (review['created_at'] ?? review['date'] ?? '').toString().trim();
  if (raw.isEmpty) return '';
  return raw.split('T').first;
}
