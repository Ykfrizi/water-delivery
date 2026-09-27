import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/cart_line.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_display.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/cart_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/vendor_review_composer.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/data/marketplace_api.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/marketplace_models.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/product_image.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/vendor_rating.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/presentation/review_list_tile.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/presentation/vendor_rating_stars.dart';

/// Vendor storefront: GET profile + products (+ reviews). POST cart items.
class VendorStoreScreen extends StatefulWidget {
  const VendorStoreScreen({
    super.key,
    required this.vendorSlug,
    required this.vendorName,
  });

  final String vendorSlug;
  final String vendorName;

  @override
  State<VendorStoreScreen> createState() => _VendorStoreScreenState();
}

class _VendorStoreScreenState extends State<VendorStoreScreen> {
  List<MarketplaceProduct> _products = [];
  List<Map<String, dynamic>> _reviews = [];
  Map<String, dynamic> _profile = {};
  bool _loading = true;
  bool _canReview = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final dio = context.read<Dio>();
    final market = MarketplaceApi(dio);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Map<String, dynamic> profile = {};
      try {
        profile = await market.getVendor(widget.vendorSlug);
      } catch (_) {
        /* profile optional if products load */
      }

      var products = <MarketplaceProduct>[];
      try {
        products = await market.getVendorProducts(
          widget.vendorSlug,
          vendorName: widget.vendorName,
        );
      } catch (_) {
        // Last resort: products embedded on profile payload.
        final embedded = productsFromPayload(profile);
        products = embedded
            .map(
              (e) => MarketplaceProduct.fromJson(
                e,
                vendorSlug: widget.vendorSlug,
                vendorName: widget.vendorName,
              ),
            )
            .toList();
      }

      // If products endpoint returned empty, still try profile embed.
      if (products.isEmpty && profile.isNotEmpty) {
        final embedded = productsFromPayload(profile);
        if (embedded.isNotEmpty) {
          products = embedded
              .map(
                (e) => MarketplaceProduct.fromJson(
                  e,
                  vendorSlug: widget.vendorSlug,
                  vendorName: widget.vendorName,
                ),
              )
              .toList();
        }
      }

      List<Map<String, dynamic>> reviews = [];
      try {
        reviews = await market.getVendorReviews(widget.vendorSlug);
      } catch (_) {
        /* optional */
      }

      var canReview = false;
      final token = context.read<AuthController>().session?.token;
      if (token != null) {
        try {
          final orders = await CustomerApi(dio).listOrders(token, perPage: 50);
          canReview = orders.any(
            (o) =>
                orderVendorSlug(o) == widget.vendorSlug && orderIsDelivered(o),
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _products = products;
        _reviews = reviews;
        _canReview = canReview;
        _loading = false;
        if (products.isEmpty && profile.isEmpty) {
          _error = 'Could not load this store. Pull to refresh or try again.';
        }
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

  String? get _storeDescription {
    final raw = _profile['description']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('/marketplace/') || raw.contains('GET /')) return null;
    return raw;
  }

  Future<void> _addToCart(MarketplaceProduct p) async {
    final id = p.id;
    if (id == null) {
      showErrorSnackBar(context, 'Product has no id.');
      return;
    }
    final auth = context.read<AuthController>();
    final token = auth.session?.token;
    if (token == null) return;

    final api = CustomerApi(context.read<Dio>());
    try {
      await api.addCartItem(
        token,
        productId: id,
        quantity: kMinCartItemQuantity,
      );
      if (!mounted) return;
      context.read<CartController>().refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to cart'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.message);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = customerAppTheme();

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
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                      ),
                      Expanded(
                        child: Text(
                          widget.vendorName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_storeDescription != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      _storeDescription!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: kCustomerGray,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                    ),
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _buildBody(theme),
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

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        VendorRatingStars(
          rating: VendorRating.fromVendorJson({
            ..._profile,
            'reviews': _reviews,
            if (_reviews.isNotEmpty) 'reviews_count': _reviews.length,
          }),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Products',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              '${_products.length}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: kCustomerBlue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined, size: 44, color: Colors.grey.shade500),
                const SizedBox(height: 10),
                Text(
                  'No products listed for this vendor',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This vendor has not listed products yet. Pull to refresh.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          )
        else
          ..._products.map((p) => _ProductTile(product: p, onAdd: () => _addToCart(p))),
        if (_canReview) ...[
          const SizedBox(height: 20),
          VendorReviewComposer(
            vendorSlug: widget.vendorSlug,
            onSubmitted: _load,
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Reviews (${_reviews.length})',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (_reviews.isEmpty)
          const Text(
            'No reviews yet. After a delivery you can rate this shop.',
            style: TextStyle(color: kOnLightMuted, height: 1.35),
          )
        else
          ..._reviews.map((r) => ReviewListTile(review: r)),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onAdd});

  final MarketplaceProduct product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceLabel = product.priceLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ProductImageThumb(
                imageUrl: product.imageUrl,
                size: 64,
                badgeCount: product.imageUrls.length,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: kOnLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      priceLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: kCustomerBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (product.inStock != null)
                      Text(
                        product.inStock! ? 'In stock' : 'Out of stock',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: product.inStock!
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: product.inStock == false ? null : onAdd,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
