import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/cart_line.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/explore_vendors_screen.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/vendor_store_screen.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/data/marketplace_api.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/marketplace_models.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/product_image.dart';

/// Customer home dashboard — greeting, vendors & products.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    this.isActive = true,
    required this.onOpenProducts,
    required this.onOpenCart,
    required this.onOpenOrders,
  });

  final bool isActive;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenCart;
  final VoidCallback onOpenOrders;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  bool _loading = true;
  String? _error;
  int _cartCount = 0;
  int _orderCount = 0;
  List<MarketplaceVendor> _vendors = [];
  List<MarketplaceProduct> _products = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isActive) _load();
    });
  }

  @override
  void didUpdateWidget(covariant CustomerHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final dio = context.read<Dio>();
    final auth = context.read<AuthController>();
    final token = auth.session?.token;
    final market = MarketplaceApi(dio);
    final customer = CustomerApi(dio);

    setState(() {
      _loading = true;
      _error = null;
    });

    var cartCount = 0;
    var orderCount = 0;
    var vendors = <MarketplaceVendor>[];
    var products = <MarketplaceProduct>[];
    final failed = <String>[];

    try {
      vendors = await market.listVendors(perPage: 12);
    } catch (_) {
      failed.add('vendors');
    }

    try {
      // Full recent catalog for the dashboard preview (newest first).
      final all = await market.listAllProducts(
        vendorLimit: 100,
        perVendor: 100,
        preferFullCatalog: true,
      );
      products = all.length > 12 ? all.take(12).toList() : all;
    } catch (_) {
      failed.add('products');
    }

    if (token != null) {
      try {
        final cart = await customer.getCart(token);
        cartCount = cartLinesFromResponse(cart).fold<int>(
          0,
          (sum, line) => sum + line.quantity,
        );
      } catch (_) {
        failed.add('cart');
      }
      try {
        final orders = await customer.listOrders(token, perPage: 5);
        orderCount = orders.length;
      } catch (_) {
        failed.add('orders');
      }
    }

    if (!mounted) return;
    setState(() {
      _vendors = vendors;
      _products = products;
      _cartCount = cartCount;
      _orderCount = orderCount;
      _loading = false;
      if (failed.length >= 3 && vendors.isEmpty && products.isEmpty) {
        _error = 'Could not load your dashboard. Check the API connection.';
      }
    });
  }

  Future<void> _openVendors() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ExploreVendorsScreen(),
      ),
    );
  }

  Future<void> _openVendor(MarketplaceVendor v) async {
    if (v.slug.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VendorStoreScreen(
          vendorSlug: v.slug,
          vendorName: v.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(UserRole.customer);
    final greeting = context.select<AuthController, String>(
      (a) => a.session?.user.greeting ?? 'Hello!',
    );
    const subtitle = 'Fresh sachet water near you';

    return Container(
        decoration: roleGradientDecoration(UserRole.customer),
        child: SafeArea(
          child: RefreshIndicator(
            color: accent,
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: BrandHeader(
                    title: greeting,
                    subtitle: subtitle,
                    actions: [
                      HeaderIconButton(
                        icon: Icons.refresh_rounded,
                        onPressed: _loading ? null : _load,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Row(
                          children: [
                            Expanded(
                              child: _StatChip(
                                label: 'Cart',
                                value: '$_cartCount',
                                icon: Icons.shopping_bag_outlined,
                                onTap: widget.onOpenCart,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatChip(
                                label: 'Orders',
                                value: '$_orderCount',
                                icon: Icons.receipt_long_outlined,
                                onTap: widget.onOpenOrders,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatChip(
                                label: 'Vendors',
                                value: '${_vendors.length}',
                                icon: Icons.storefront_outlined,
                                onTap: _openVendors,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _SectionHeader(
                          title: 'Vendors near you',
                          actionLabel: 'See all',
                          onAction: _openVendors,
                        ),
                        const SizedBox(height: 10),
                        if (_vendors.isEmpty)
                          const _EmptyHint(text: 'No vendors available yet.')
                        else
                          SizedBox(
                            height: 132,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _vendors.take(10).length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, i) {
                                final v = _vendors[i];
                                return _VendorCard(
                                  vendor: v,
                                  onTap: () => _openVendor(v),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 20),
                        _SectionHeader(
                          title: 'Recent products',
                          actionLabel: 'See all',
                          onAction: widget.onOpenProducts,
                        ),
                        const SizedBox(height: 10),
                        if (_products.isEmpty)
                          const _EmptyHint(
                            text: 'No products listed yet. Check back soon.',
                          )
                        else
                          ..._products.map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ProductRow(
                                    product: p,
                                    onTap: () {
                                      final slug = p.vendorSlug;
                                      if (slug == null || slug.isEmpty) {
                                        widget.onOpenProducts();
                                        return;
                                      }
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => VendorStoreScreen(
                                            vendorSlug: slug,
                                            vendorName: p.vendorName ?? 'Vendor',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: kCustomerBlue, size: 22),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: kOnLight,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: kOnLightMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor, required this.onTap});

  final MarketplaceVendor vendor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kCustomerBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: kCustomerBlue,
                  ),
                ),
                const Spacer(),
                Text(
                  vendor.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kOnLight,
                  ),
                ),
                if (vendor.embeddedProducts.isNotEmpty)
                  Text(
                    '${vendor.embeddedProducts.length} products',
                    style: const TextStyle(
                      fontSize: 12,
                      color: kOnLightMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onTap});

  final MarketplaceProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priceLabel = product.priceLabel;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: ListTile(
        onTap: onTap,
        leading: ProductImageThumb(
          imageUrl: product.imageUrl,
          size: 42,
          borderRadius: 10,
          badgeCount: product.imageUrls.length,
        ),
        title: Text(
          product.name,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: kOnLight,
          ),
        ),
        subtitle: Text(
          product.vendorName ?? priceLabel,
          style: const TextStyle(color: kOnLightMuted),
        ),
        trailing: Text(
          priceLabel,
          style: const TextStyle(
            color: kCustomerBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
