import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';

const int kMinCartItemQuantity = 30;
const int kMaxCartItemQuantity = 500;
const num kDeliveryFeeGhs = 10;
const num kOutskirtsDeliveryFeeGhs = 20;
const num kPlatformServiceFeeGhs = 1;
const double kVendorCommissionRate = 0.05;
const double kAdminDeliveryShareRate = 0.20;
const double kRiderDeliveryShareRate = 0.80;

num vendorCommissionFor(num subtotal) =>
  subtotal * kVendorCommissionRate;

num adminDeliveryShareFor(num deliveryFee) =>
  deliveryFee * kAdminDeliveryShareRate;

num riderDeliveryShareFor(num deliveryFee) =>
  deliveryFee * kRiderDeliveryShareRate;

/// One row in GET /customer/cart — field names vary by backend.
class CartLine {
  const CartLine({
    required this.id,
    this.productId,
    required this.title,
    required this.quantity,
    this.unitPrice,
    this.currency = kAppCurrency,
    required this.raw,
  });

  final int id;
  final int? productId;
  final String title;
  final int quantity;
  final num? unitPrice;
  final String currency;
  final Map<String, dynamic> raw;

  String get priceLabel => formatMoney(unitPrice, currency: currency);

  String get lineTotalLabel {
    if (unitPrice == null) return '—';
    return formatMoney(unitPrice! * quantity, currency: currency);
  }

  factory CartLine.fromJson(Map<String, dynamic> json) {
    final id = parseId(json['id']) ?? 0;
    final product = json['product'];
    final productId =
        parseId(json['product_id']) ??
        (product is Map ? parseId(product['id']) : null);
    String title = 'Item';
    if (product is Map) {
      title = (product['name'] ?? title).toString();
    } else {
      title = (json['name'] ?? json['title'] ?? title).toString();
    }
    final qty = parseId(json['quantity']) ?? 1;
    num? price;
    if (json['price'] is num) {
      price = json['price'] as num?;
    } else if (product is Map && product['price'] != null) {
      price = num.tryParse(product['price'].toString());
    }
    return CartLine(
      id: id,
      productId: productId,
      title: title,
      quantity: qty,
      unitPrice: price,
      currency: kAppCurrency,
      raw: json,
    );
  }
}

/// Pulls line items from various Laravel cart JSON shapes.
List<CartLine> cartLinesFromResponse(Map<String, dynamic> root) {
  List<CartLine> tryMap(Map<String, dynamic> map) {
    dynamic items =
        map['items'] ?? map['cart_items'] ?? map['lines'] ?? map['data'];
    if (items is! List) return [];
    return items
        .map((e) => CartLine.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((l) => l.id > 0)
        .toList();
  }

  final data = root['data'];
  final map = data is Map ? Map<String, dynamic>.from(data) : root;
  var lines = tryMap(map);
  if (lines.isEmpty && map['cart'] is Map) {
    lines = tryMap(Map<String, dynamic>.from(map['cart'] as Map));
  }
  if (lines.isEmpty) {
    lines = tryMap(root);
  }
  return lines;
}
