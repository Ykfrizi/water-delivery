import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
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
import 'package:smart_sachet_water_distribution/features/marketplace/presentation/vendor_rating_stars.dart';

/// GET /marketplace/vendors — every vendor with their products displayed.
class ExploreVendorsScreen extends StatefulWidget {
  const ExploreVendorsScreen({super.key});

  @override
  State<ExploreVendorsScreen> createState() => _ExploreVendorsScreenState();
}

class _ExploreVendorsScreenState extends State<ExploreVendorsScreen> {
  final _search = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _radiusKm = TextEditingController();

  String? _sort;

  List<VendorCatalog> _catalogs = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _filtersActive =>
      _lat.text.trim().isNotEmpty ||
      _lng.text.trim().isNotEmpty ||
      _radiusKm.text.trim().isNotEmpty ||
      (_sort != null && _sort!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    _lat.dispose();
    _lng.dispose();
    _radiusKm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = MarketplaceApi(context.read<Dio>());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lat = double.tryParse(_lat.text.trim());
      final lng = double.tryParse(_lng.text.trim());
      final rad = double.tryParse(_radiusKm.text.trim());
      final list = await api.listVendorsWithProducts(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        latitude: lat,
        longitude: lng,
        radiusKm: rad,
        sort: _sort,
        perVendor: 100,
      );
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

  void _openStore(MarketplaceVendor v) {
    if (v.slug.isEmpty) {
      showErrorSnackBar(context, 'Vendor has no slug.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VendorStoreScreen(
          vendorSlug: v.slug,
          vendorName: v.name,
        ),
      ),
    );
  }

  Future<void> _addToCart(MarketplaceProduct p) async {
    final id = p.id;
    if (id == null) {
      showErrorSnackBar(context, 'Product has no id.');
      return;
    }
    final token = context.read<AuthController>().session?.token;
    if (token == null) {
      showErrorSnackBar(context, 'Sign in to add items to cart.');
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    final theme = customerAppTheme();
    final productCount =
        _catalogs.fold<int>(0, (sum, c) => sum + c.products.length);

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: kCustomerBlueDeep,
        body: Container(
          decoration: authGradientDecoration(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (Navigator.of(context).canPop())
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 10),
                        child: AppLogo(size: 40, showShadow: true),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: Navigator.of(context).canPop() ? 0 : 12,
                            top: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Discover vendors',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _loading
                                    ? 'Loading vendors & products…'
                                    : '${_catalogs.length} vendor${_catalogs.length == 1 ? '' : 's'} · $productCount products',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton.filledTonal(
                            onPressed: _showFilterSheet,
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.16),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                          if (_filtersActive)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFAB40),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
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
                          onPressed: _load,
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
                const SizedBox(height: 12),
                Expanded(
                  child: RefreshIndicator(
                    color: kCustomerBlue,
                    onRefresh: _load,
                    child: _buildBody(theme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFilterSheet() async {
    final theme = Theme.of(context);
    final lat = TextEditingController(text: _lat.text);
    final lng = TextEditingController(text: _lng.text);
    final rad = TextEditingController(text: _radiusKm.text);
    var sort = _sort;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCustomerGray,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
            left: 20,
            right: 20,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Marketplace filters',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Optional: use your GPS, set a search radius (km), and sort.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final pos = await const DeviceLocationService()
                            .getPositionOrExplain(context);
                        if (pos == null) return;
                        setModal(() {
                          lat.text = pos.latitudeLabel;
                          lng.text = pos.longitudeLabel;
                          if (rad.text.trim().isEmpty) rad.text = '10';
                          sort ??= 'distance';
                        });
                      },
                      icon: const Icon(Icons.my_location_rounded),
                      label: const Text('Use my location'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: lat,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        filled: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: lng,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        filled: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: rad,
                      decoration: const InputDecoration(
                        labelText: 'Radius (km)',
                        filled: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Sort',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: kOnLight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in const <(String?, String)>[
                          (null, 'Default'),
                          ('name', 'Name'),
                          ('-name', 'Name Z–A'),
                          ('distance', 'Distance'),
                          ('created_at', 'Newest'),
                        ])
                          HeaderFilterChip(
                            label: option.$2,
                            selected: sort == option.$1,
                            onSelected: (_) => setModal(() => sort = option.$1),
                            accent: kCustomerBlue,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            lat.clear();
                            lng.clear();
                            rad.clear();
                            setModal(() => sort = null);
                          },
                          child: const Text('Clear'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            _lat.text = lat.text;
                            _lng.text = lng.text;
                            _radiusKm.text = rad.text;
                            _sort = sort;
                            Navigator.pop(ctx);
                            _load();
                          },
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      lat.dispose();
      lng.dispose();
      rad.dispose();
    });
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _catalogs.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    if (_catalogs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.store_mall_directory_outlined,
            size: 56,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No vendors found',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _catalogs.length,
      itemBuilder: (context, i) {
        final catalog = _catalogs[i];
        final v = catalog.vendor;
        final products = catalog.products;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            elevation: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  onTap: () => _openStore(v),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: v.logoUrl != null && v.logoUrl!.isNotEmpty
                                ? Image.network(
                                    v.logoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stack) =>
                                        ColoredBox(
                                      color: kCustomerBlue
                                          .withValues(alpha: 0.15),
                                      child: const Icon(
                                        Icons.storefront_rounded,
                                        color: kCustomerBlue,
                                      ),
                                    ),
                                  )
                                : ColoredBox(
                                    color: kCustomerBlue
                                        .withValues(alpha: 0.15),
                                    child: const Icon(
                                      Icons.storefront_rounded,
                                      color: kCustomerBlue,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: kOnLight,
                                ),
                              ),
                              const SizedBox(height: 4),
                              VendorRatingStars(rating: v.rating, size: 16),
                              if (v.description != null &&
                                  v.description!.isNotEmpty)
                                Text(
                                  v.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: kOnLightMuted,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                products.isEmpty
                                    ? 'No products listed yet'
                                    : '${products.length} product${products.length == 1 ? '' : 's'}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: kCustomerBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _openStore(v),
                          child: const Text('Store'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'This vendor has not published products yet.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        for (final p in products)
                          _ProductTile(
                            product: p,
                            busy: _busy,
                            onAdd: () => _addToCart(p),
                            onOpen: () => _openStore(v),
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

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.busy,
    required this.onAdd,
    required this.onOpen,
  });

  final MarketplaceProduct product;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final priceLabel = product.priceLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kCustomerGray,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                ProductImageThumb(
                  imageUrl: product.imageUrl,
                  size: 40,
                  borderRadius: 10,
                  badgeCount: product.imageUrls.length,
                ),
                const SizedBox(width: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        priceLabel,
                        style: const TextStyle(
                          color: kCustomerBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: (busy || product.inStock == false) ? null : onAdd,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
