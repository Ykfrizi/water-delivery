import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/product_image.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/vendor_rating.dart';

/// Vendor directory row (handoff §5) with attached catalog products.
class MarketplaceVendor {
  const MarketplaceVendor({
    required this.slug,
    required this.name,
    this.logoUrl,
    this.description,
    required this.raw,
  });

  final String slug;
  final String name;
  final String? logoUrl;
  final String? description;
  final Map<String, dynamic> raw;

  factory MarketplaceVendor.fromJson(Map<String, dynamic> json) {
    String slug = (json['slug'] ?? json['vendor_slug'] ?? json['id'])?.toString() ?? '';
    if (slug.isEmpty && json['vendor'] is Map) {
      final v = Map<String, dynamic>.from(json['vendor'] as Map);
      slug = (v['slug'] ?? v['id'])?.toString() ?? '';
    }
    final name = (json['name'] ??
            json['business_name'] ??
            json['store_name'] ??
            'Vendor')
        .toString();
    return MarketplaceVendor(
      slug: slug,
      name: name,
      logoUrl: json['logo_url']?.toString() ?? json['logoUrl']?.toString(),
      description: json['description']?.toString(),
      raw: json,
    );
  }

  VendorRating get rating => VendorRating.fromVendorJson(raw);

  /// Product rows embedded on the vendor list/detail payload, if any.
  List<Map<String, dynamic>> get embeddedProducts {
    for (final key in const ['products', 'catalog', 'items']) {
      final v = raw[key];
      if (v is List) {
        return v
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return const [];
  }
}

/// One marketplace vendor plus the products loaded for that storefront.
class VendorCatalog {
  const VendorCatalog({
    required this.vendor,
    required this.products,
  });

  final MarketplaceVendor vendor;
  final List<MarketplaceProduct> products;
}

/// Product row from GET /marketplace/vendors/{vendor}/products.
class MarketplaceProduct {
  const MarketplaceProduct({
    required this.id,
    required this.name,
    this.price,
    this.currency,
    this.inStock,
    this.vendorSlug,
    this.vendorName,
    this.imageUrl,
    this.imageUrls = const [],
    required this.raw,
  });

  final int? id;
  final String name;
  final num? price;
  final String? currency;
  final bool? inStock;
  final String? vendorSlug;
  final String? vendorName;
  final String? imageUrl;
  final List<String> imageUrls;
  final Map<String, dynamic> raw;

  /// Always display prices in GHS.
  String get priceLabel => formatMoney(price, currency: currency);

  factory MarketplaceProduct.fromJson(
    Map<String, dynamic> json, {
    String? vendorSlug,
    String? vendorName,
  }) {
    Map<String, dynamic> row = json;
    final nested = json['product'];
    if (nested is Map && (json['name'] == null && json['price'] == null)) {
      row = {
        ...Map<String, dynamic>.from(nested),
        ...json,
      };
    }

    final id = _parseInt(row['id']) ?? _parseInt(row['product_id']);
    final priceRaw = row['price'] ?? row['unit_price'] ?? row['amount'];
    final price = priceRaw is num
        ? priceRaw
        : num.tryParse(priceRaw?.toString() ?? '');
    final stock = row['in_stock'] ??
        row['inStock'] ??
        row['stock'] ??
        row['stock_quantity'] ??
        row['quantity'];
    bool? inStock;
    if (stock is bool) {
      inStock = stock;
    } else if (stock is num) {
      inStock = stock > 0;
    }

    String? resolvedVendorSlug = vendorSlug ??
        row['vendor_slug']?.toString() ??
        row['vendorSlug']?.toString();
    String? resolvedVendorName = vendorName ??
        row['vendor_name']?.toString() ??
        row['vendorName']?.toString() ??
        row['business_name']?.toString();
    final vendor = row['vendor'];
    if (vendor is Map) {
      final v = Map<String, dynamic>.from(vendor);
      resolvedVendorSlug ??= (v['slug'] ?? v['id'])?.toString();
      resolvedVendorName ??=
          (v['name'] ?? v['business_name'])?.toString();
    }

    final images = productImageUrlsFrom(row);
    return MarketplaceProduct(
      id: id,
      name: (row['name'] ?? row['title'] ?? 'Product').toString(),
      price: price,
      currency: kAppCurrency,
      inStock: inStock,
      vendorSlug: resolvedVendorSlug,
      vendorName: resolvedVendorName,
      imageUrl: images.isEmpty ? null : images.first,
      imageUrls: images,
      raw: row,
    );
  }

  MarketplaceProduct copyWithVendor({
    String? vendorSlug,
    String? vendorName,
  }) {
    return MarketplaceProduct(
      id: id,
      name: name,
      price: price,
      currency: kAppCurrency,
      inStock: inStock,
      vendorSlug: vendorSlug ?? this.vendorSlug,
      vendorName: vendorName ?? this.vendorName,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      raw: raw,
    );
  }
}

int? _parseInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}
