import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/cart_line.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/cart_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/vendor_store_screen.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/data/marketplace_api.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/marketplace_models.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/product_image.dart';

/// Customer marketplace — all vendors with their products grouped underneath.
class CustomerProductsScreen extends StatefulWidget {
  const CustomerProductsScreen({super.key});

  @override
  State<CustomerProductsScreen> createState() => _CustomerProductsScreenState();
}

class _CustomerProductsScreenState extends State<CustomerProductsScreen> {
  final _search = TextEditingController();
  List<VendorCatalog> _catalogs = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int get _productCount =>
      _catalogs.fold<int>(0, (sum, c) => sum + c.products.length);

  Future<void> _load() async {
    final api = MarketplaceApi(context.read<Dio>());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var list = await api.listVendorsWithProducts(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        perVendor: 100,
      );
      // Keep vendors that match search even if they currently have no products,
      // but prefer showing catalogs that include products first.
      list = [
        ...list.where((c) => c.products.isNotEmpty),
        ...list.where((c) => c.products.isEmpty),
      ];
      if (!mounted) return;
      setState(() {
        _catalogs = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addToCart(MarketplaceProduct p) async {
    final id = p.id;
    if (id == null) {
      showErrorSnackBar(context, 'Product has no id.');
      return;
    }
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;

    setState(() => _busy = true);
    try {
      await CustomerApi(context.read<Dio>()).addCartItem(
        token,
        productId: id,
        quantity: kMinCartItemQuantity,
      );
      if (!mounted) return;
      context.read<CartController>().refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.name} added to cart'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openVendor(MarketplaceVendor v) {
    if (v.slug.isEmpty) return;
    Navigator.of(context).push(
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
    final theme = Theme.of(context);

    return Container(
        decoration: authGradientDecoration(),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: 'Vendors & products',
                subtitle: _loading
                    ? 'Loading marketplace catalog…'
                    : _catalogs.isEmpty
                        ? 'Browse approved vendors and their products'
                        : '${_catalogs.length} vendor${_catalogs.length == 1 ? '' : 's'} · $_productCount products',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  child: TextField(
                    controller: _search,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search vendors or products…',
                      filled: true,
                      fillColor: Colors.transparent,
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      suffixIcon: IconButton(
                        onPressed: _loading ? null : _load,
                        icon: Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: kCustomerGray,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: RefreshIndicator(
                      color: kCustomerBlue,
                      onRefresh: _load,
                      child: _buildBody(theme),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _catalogs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }
    if (_catalogs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.storefront_outlined, size: 52, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            'No vendors yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Approved vendors and their products appear here after they publish a catalog.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade700,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(14),
      itemCount: _catalogs.length,
      itemBuilder: (context, i) {
        final catalog = _catalogs[i];
        final v = catalog.vendor;
        final products = catalog.products;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  onTap: () => _openVendor(v),
                  leading: CircleAvatar(
                    backgroundColor:
                        kCustomerBlue.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: kCustomerBlue,
                    ),
                  ),
                  title: Text(
                    v.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: kOnLight,
                    ),
                  ),
                  subtitle: Text(
                    products.isEmpty
                        ? 'No products yet'
                        : '${products.length} product${products.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: kOnLightMuted),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
                if (products.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        for (final p in products)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: kCustomerGray,
                              borderRadius: BorderRadius.circular(12),
                              child: ListTile(
                                dense: true,
                                onTap: () => _openVendor(v),
                                leading: ProductImageThumb(
                                  imageUrl: p.imageUrl,
                                  size: 40,
                                  borderRadius: 10,
                                  badgeCount: p.imageUrls.length,
                                ),
                                title: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: kOnLight,
                                  ),
                                ),
                                  subtitle: Text(
                                    p.price != null ? p.priceLabel : '—',
                                    style: const TextStyle(
                                      color: kCustomerBlue,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                trailing: FilledButton.tonal(
                                  onPressed: (_busy || p.inStock == false)
                                      ? null
                                      : () => _addToCart(p),
                                  child: const Text('Add'),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
