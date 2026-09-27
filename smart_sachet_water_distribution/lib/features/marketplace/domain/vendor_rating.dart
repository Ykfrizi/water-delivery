/// Helpers for vendor average rating + review count from flexible JSON.
class VendorRating {
  const VendorRating({
    required this.average,
    required this.count,
  });

  final double average;
  final int count;

  bool get hasRatings => count > 0 && average > 0;

  String get label {
    if (!hasRatings) return 'No reviews yet';
    return '${average.toStringAsFixed(1)} · $count review${count == 1 ? '' : 's'}';
  }

  factory VendorRating.fromVendorJson(Map<String, dynamic> json) {
    double? avg = _asDouble(
      json['average_rating'] ??
          json['avg_rating'] ??
          json['rating_avg'] ??
          json['rating'],
    );
    int? count = _asInt(
      json['reviews_count'] ??
          json['review_count'] ??
          json['ratings_count'] ??
          json['reviews_total'],
    );

    final reviews = json['reviews'];
    if (reviews is List && reviews.isNotEmpty) {
      count ??= reviews.length;
      if (avg == null) {
        var sum = 0.0;
        var n = 0;
        for (final r in reviews) {
          if (r is! Map) continue;
          final rating = _asDouble(r['rating'] ?? r['stars'] ?? r['score']);
          if (rating == null) continue;
          sum += rating;
          n++;
        }
        if (n > 0) avg = sum / n;
      }
    }

    return VendorRating(
      average: avg ?? 0,
      count: count ?? 0,
    );
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
