import 'package:share_plus/share_plus.dart';
import 'package:smart_sachet_water_distribution/app/brand.dart';
import 'package:smart_sachet_water_distribution/core/config/api_config.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_display.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_location_parser.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_order_status.dart';

String publicOriginFromApiBase() {
  return ApiConfig.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
}

String rewriteShareUrlIfLocalhost(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) return url;
  if (parsed.host != 'localhost' && parsed.host != '127.0.0.1') {
    return url;
  }
  final origin = Uri.parse(publicOriginFromApiBase());
  return parsed
      .replace(
        scheme: origin.scheme,
        host: origin.host,
        port: origin.hasPort ? origin.port : null,
      )
      .toString();
}

String? customerNameFrom(Map<String, dynamic> json) {
  final customer = json['customer'];
  if (customer is Map) {
    final name = (customer['name'] ?? customer['full_name'])?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
  }
  final ship = json['shipping_address'];
  if (ship is Map) {
    final name = (ship['name'] ?? ship['recipient'] ?? ship['full_name'])
        ?.toString()
        .trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

String customerAddressFrom(Map<String, dynamic> json) {
  final ship = json['shipping_address'];
  if (ship is! Map) return '';
  final parts = <String>[];
  for (final key in const [
    'line1',
    'address',
    'street',
    'address_line',
    'line2',
    'city',
    'town',
    'region',
    'state',
  ]) {
    final v = ship[key]?.toString().trim();
    if (v != null && v.isNotEmpty && !parts.contains(v)) parts.add(v);
  }
  return parts.join(', ');
}

Future<void> shareVendorDeliveryLink({
  required VendorApi api,
  required String token,
  required String orderNumber,
  required Map<String, dynamic> order,
}) async {
  final data = await api.createDeliveryLink(token, orderNumber);
  var url = data['url']?.toString().trim() ?? '';
  final shareToken = data['token']?.toString().trim();
  if (url.isEmpty && shareToken != null && shareToken.isNotEmpty) {
    url = '${publicOriginFromApiBase()}/d/$shareToken';
  }
  url = rewriteShareUrlIfLocalhost(url);
  if (url.isEmpty) {
    throw StateError('Could not create a delivery link.');
  }

  final name = customerNameFrom(order) ?? 'Customer';
  final phone = customerPhoneFrom(order);
  final address = customerAddressFrom(order);
  final lines = orderLineItems(order);
  final itemLines = lines
      .map((line) {
        final qty = orderLineQty(line);
        final title = orderLineTitle(line);
        return qty == null ? '• $title' : '• $title × $qty';
      })
      .join('\n');

  final buffer = StringBuffer()
    ..writeln('${AppBrand.name} drop-off')
    ..writeln('Order #$orderNumber')
    ..writeln('Customer: $name');
  if (phone != null) buffer.writeln('Phone: $phone');
  if (address.isNotEmpty) buffer.writeln('Address: $address');
  buffer.writeln('Payment: ${vendorPaymentKindLabel(order)}');
  if (itemLines.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Items:')
      ..writeln(itemLines);
  }
  buffer
    ..writeln()
    ..writeln('Open for map and full details (expires in 24 hours):')
    ..writeln(url);

  await SharePlus.instance.share(
    ShareParams(
      text: buffer.toString().trim(),
      subject: '${AppBrand.name} — order #$orderNumber',
    ),
  );
}
