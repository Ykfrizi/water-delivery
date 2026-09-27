import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/product_image.dart';

/// Read-only product detail for vendors (tap a product in the list).
class VendorProductDetailScreen extends StatelessWidget {
  const VendorProductDetailScreen({super.key, required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final theme = vendorAppTheme();
    final accent = roleAccent(UserRole.vendor);
    final name = product['name']?.toString() ?? 'Product';
    final id = resourceIdFrom(product) ?? product['id'];
    final price = product['price'];
    final stock = product['stock'] ?? product['stock_quantity'];
    final desc = product['description']?.toString().trim();
    final images = productImageUrlsFrom(product);
    final currency = (product['currency'] ?? kAppCurrency)
        .toString()
        .toUpperCase();

    return Theme(
      data: theme,
      child: Scaffold(
        body: Container(
          decoration: authGradientDecoration(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                      ),
                      Expanded(
                        child: Text(
                          'Product details',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5FAFC),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                        children: [
                          if (images.isNotEmpty) ...[
                            SizedBox(
                              height: 220,
                              child: PageView.builder(
                                itemCount: images.length,
                                itemBuilder: (context, i) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.network(
                                        resolveMediaUrl(images[i]),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const ColoredBox(
                                              color: Color(0xFFE0F7FA),
                                              child: Center(
                                                child: Icon(
                                                  Icons.water_drop_outlined,
                                                  size: 48,
                                                  color: Color(0xFF00838F),
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (images.length > 1) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${images.length} photos · swipe to browse',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ] else ...[
                            Container(
                              height: 160,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F7FA),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.water_drop_outlined,
                                  size: 48,
                                  color: Color(0xFF00838F),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            name,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            formatMoneyDynamic(price, currency: currency),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _InfoCard(
                            children: [
                              _kv('Product ID', id?.toString() ?? '—'),
                              _kv('Stock', stock?.toString() ?? '—'),
                              _kv('Currency', currency),
                              if (product['status'] != null)
                                _kv('Status', product['status'].toString()),
                              if (product['sku'] != null)
                                _kv('SKU', product['sku'].toString()),
                            ],
                          ),
                          if (desc != null && desc.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              'Description',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              desc,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
