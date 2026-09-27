import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/product_image.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_product_detail_screen.dart';

/// CRUD /vendor/products
class VendorProductsScreen extends StatefulWidget {
  const VendorProductsScreen({super.key});

  @override
  State<VendorProductsScreen> createState() => _VendorProductsScreenState();
}

class _VendorProductsScreenState extends State<VendorProductsScreen> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> _normalizeProductRow(Map<String, dynamic> row) {
    final nested = row['product'];
    if (nested is Map) {
      final inner = Map<String, dynamic>.from(nested);
      final id = resourceIdFrom(row) ?? resourceIdFrom(inner);
      return {...inner, ...row, 'id': ?id};
    }
    final id = resourceIdFrom(row);
    if (id != null && row['id'] == null) {
      return {...row, 'id': id};
    }
    return row;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (!mounted) return;
    final token = context.read<AuthController>().token;
    if (token == null) return;
    final api = VendorApi(context.read<Dio>());
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final list = await api.listProducts(token);
      if (!mounted) return;
      setState(() {
        _products = list.map(_normalizeProductRow).toList();
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _upsert({Map<String, dynamic>? existing}) async {
    final form = await showDialog<_ProductFormData>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => _ProductEditorDialog(existing: existing),
    );
    if (form == null || !mounted) return;

    final token = context.read<AuthController>().token;
    if (token == null) return;
    final api = VendorApi(context.read<Dio>());
    final body = form.toRequestBody();

    setState(() => _busy = true);
    try {
      if (existing == null) {
        final created = await api.createProduct(
          token,
          body,
          imagePaths: form.imagePaths,
        );
        _showSnack('Product created');
        await _load(showSpinner: false);
        // If list reload is empty/stale, keep the created row visible.
        if (mounted && created.isNotEmpty) {
          final createdRow = _normalizeProductRow(created);
          final createdId = resourceIdFrom(createdRow);
          final alreadyListed =
              createdId != null &&
              _products.any(
                (p) => resourceIdFrom(p)?.toString() == createdId.toString(),
              );
          if (!alreadyListed) {
            setState(() => _products = [createdRow, ..._products]);
          }
        }
      } else {
        final id = resourceIdFrom(existing);
        if (id == null) {
          showErrorSnackBar(context, 'Missing product id from API.');
          return;
        }
        await api.updateProduct(token, id, body, imagePaths: form.imagePaths);
        _showSnack('Product updated');
        await _load(showSpinner: false);
      }
    } on ApiException catch (e) {
      if (mounted) {
        final msg = e.fieldErrors.isNotEmpty
            ? firstFieldError(
                e.fieldErrors,
                keys: const [
                  'name',
                  'price',
                  'stock',
                  'stock_quantity',
                  'quantity',
                  'description',
                  'image',
                  'images',
                  'image_url',
                  'photo',
                  'remove_image_ids',
                ],
              )
            : e.message;
        showErrorSnackBar(context, msg);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = resourceIdFrom(row);
    if (id == null) {
      if (mounted) showErrorSnackBar(context, 'Missing product id from API.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          'Remove "${row['name']?.toString() ?? 'this product'}" from your catalog? Past orders keep the name; customers will no longer see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final token = context.read<AuthController>().token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await VendorApi(context.read<Dio>()).deleteProduct(token, id);
      _showSnack('Product deleted');
      await _load(showSpinner: false);
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
    final accent = roleAccent(UserRole.vendor);

    return Container(
      decoration: roleGradientDecoration(UserRole.vendor),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandHeader(
              title: 'Catalog',
              subtitle: 'Products customers can order',
              actions: [
                HeaderIconButton(
                  icon: Icons.add_rounded,
                  onPressed: _busy ? null : () => _upsert(),
                  tooltip: 'Add product',
                ),
              ],
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: kVendorMint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!),
                                FilledButton(
                                  onPressed: _load,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            if (_busy)
                              const LinearProgressIndicator(minHeight: 2),
                            Expanded(
                              child: RefreshIndicator(
                                color: accent,
                                onRefresh: () => _load(),
                                child: _products.isEmpty
                                    ? ListView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding: const EdgeInsets.all(24),
                                        children: [
                                          const SizedBox(height: 60),
                                          Icon(
                                            Icons.inventory_2_outlined,
                                            size: 48,
                                            color: Colors.grey.shade500,
                                          ),
                                          const SizedBox(height: 12),
                                          const Center(
                                            child: Text(
                                              'No products yet',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Tap + to add a product.\n'
                                            'If you already added some, pull to refresh or check the API is running.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Center(
                                            child: FilledButton.icon(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _upsert(),
                                              icon: const Icon(Icons.add),
                                              label: const Text('Add product'),
                                            ),
                                          ),
                                        ],
                                      )
                                    : ListView.builder(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding: const EdgeInsets.all(14),
                                        itemCount: _products.length,
                                        itemBuilder: (context, i) {
                                          final p = _products[i];
                                          final id =
                                              resourceIdFrom(p) ?? p['id'];
                                          final price = p['price'];
                                          final stock =
                                              p['stock'] ?? p['stock_quantity'];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            child: Material(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              elevation: 2,
                                              child: ListTile(
                                                onTap: () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          VendorProductDetailScreen(
                                                            product: p,
                                                          ),
                                                    ),
                                                  );
                                                },
                                                leading: ProductImageThumb(
                                                  imageUrl: productImageUrlFrom(
                                                    p,
                                                  ),
                                                  size: 52,
                                                  badgeCount:
                                                      productImageUrlsFrom(
                                                        p,
                                                      ).length,
                                                ),
                                                title: Text(
                                                  p['name']?.toString() ??
                                                      'Product',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  'ID: $id · ${formatMoneyDynamic(price)} · Stock: $stock',
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.edit_outlined,
                                                      ),
                                                      onPressed: _busy
                                                          ? null
                                                          : () => _upsert(
                                                              existing: p,
                                                            ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                      ),
                                                      onPressed: _busy
                                                          ? null
                                                          : () => _delete(p),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductFormData {
  const _ProductFormData({
    required this.name,
    required this.price,
    this.stockQty,
    this.description,
    this.imagePaths = const [],
    this.removeImageIds = const [],
  });

  final String name;
  final num price;
  final int? stockQty;
  final String? description;
  final List<String> imagePaths;
  final List<int> removeImageIds;

  Map<String, dynamic> toRequestBody() {
    return <String, dynamic>{
      'name': name,
      'price': price,
      'currency': kAppCurrency,
      if (description != null && description!.isNotEmpty)
        'description': description,
      if (stockQty != null) ...{
        'stock_quantity': stockQty,
        'stock': stockQty,
        'quantity': stockQty,
      },
      if (removeImageIds.isNotEmpty) 'remove_image_ids': removeImageIds,
    };
  }
}

/// Owns [TextEditingController]s so they are disposed only after the route closes.
class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _descCtrl;
  final List<String> _pickedImagePaths = [];
  List<ProductImageRef> _existingImages = [];
  final List<int> _removedImageIds = [];

  static const _maxImages = 10;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?['name']?.toString() ?? '');
    _priceCtrl = TextEditingController(text: e?['price']?.toString() ?? '');
    _stockCtrl = TextEditingController(
      text: (e?['stock'] ?? e?['stock_quantity'])?.toString() ?? '',
    );
    _descCtrl = TextEditingController(
      text: e?['description']?.toString() ?? '',
    );
    _existingImages = e == null
        ? <ProductImageRef>[]
        : List<ProductImageRef>.from(productImageItemsFrom(e));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  int get _totalSelected => _existingImages.length + _pickedImagePaths.length;

  Future<void> _pickImages() async {
    final remaining = _maxImages - _totalSelected;
    if (remaining <= 0) {
      showErrorSnackBar(context, 'You can upload up to $_maxImages images.');
      return;
    }
    final picker = ImagePicker();
    try {
      // Prefer multi-select; fall back to single pick if the platform channel fails.
      List<XFile> files = const [];
      try {
        files = await picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
      } on PlatformException catch (e) {
        if (e.code == 'channel-error') {
          final one = await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 85,
          );
          if (one != null) files = [one];
        } else {
          rethrow;
        }
      }
      if (!mounted || files.isEmpty) return;
      setState(() {
        for (final f in files) {
          if (_totalSelected >= _maxImages) break;
          if (!_pickedImagePaths.contains(f.path)) {
            _pickedImagePaths.add(f.path);
          }
        }
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final needsRebuild = e.code == 'channel-error';
      showErrorSnackBar(
        context,
        needsRebuild
            ? 'Gallery plugin not linked yet. Stop the app, run flutter pub get, then do a full restart (not hot reload).'
            : 'Could not open gallery (${e.code}).',
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        'Could not open gallery. Fully restart the app after installing image_picker.',
      );
    }
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showErrorSnackBar(context, 'Product name is required.');
      return;
    }

    final priceText = _priceCtrl.text.trim();
    if (priceText.isEmpty) {
      showErrorSnackBar(context, 'Price is required.');
      return;
    }
    final price = num.tryParse(priceText);
    if (price == null || price < 0) {
      showErrorSnackBar(context, 'Enter a valid price.');
      return;
    }

    final stockText = _stockCtrl.text.trim();
    int? stockQty;
    if (stockText.isNotEmpty) {
      stockQty = int.tryParse(stockText);
      if (stockQty == null || stockQty < 0) {
        showErrorSnackBar(context, 'Enter a valid stock quantity.');
        return;
      }
    }

    final desc = _descCtrl.text.trim();

    final hasImages =
        _pickedImagePaths.isNotEmpty || _existingImages.isNotEmpty;
    if (!hasImages) {
      showErrorSnackBar(context, 'At least one product image is required.');
      return;
    }

    Navigator.pop(
      context,
      _ProductFormData(
        name: name,
        price: price,
        stockQty: stockQty,
        description: desc.isEmpty ? null : desc,
        imagePaths: List<String>.from(_pickedImagePaths),
        removeImageIds: List<int>.from(_removedImageIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;

    return AlertDialog(
      title: Text(isNew ? 'New product' : 'Edit product'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Price (GHS) *',
                hintText: 'Amount in Ghana Cedis',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: _stockCtrl,
              decoration: const InputDecoration(labelText: 'Stock qty'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            Text('Photos *', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'At least one image is required. Gallery upload, max $_maxImages. '
              'Tap the X on a photo to remove it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final img in _existingImages)
                  _ImageChip(
                    child: ProductImageThumb(
                      imageUrl: img.url,
                      size: 72,
                      borderRadius: 10,
                    ),
                    onRemove: () => setState(() {
                      _existingImages.remove(img);
                      final id = img.id;
                      if (id != null && !_removedImageIds.contains(id)) {
                        _removedImageIds.add(id);
                      }
                    }),
                  ),
                for (var i = 0; i < _pickedImagePaths.length; i++)
                  _ImageChip(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(_pickedImagePaths[i]),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    onRemove: () =>
                        setState(() => _pickedImagePaths.removeAt(i)),
                  ),
                if (_totalSelected < _maxImages)
                  InkWell(
                    onTap: _pickImages,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade400),
                        color: Colors.grey.shade100,
                      ),
                      child: const Icon(Icons.add_a_photo_outlined),
                    ),
                  ),
              ],
            ),
            if (_pickedImagePaths.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_pickedImagePaths.length} new photo${_pickedImagePaths.length == 1 ? '' : 's'} to upload'
                '${_existingImages.isEmpty ? '' : ' · ${_existingImages.length} already saved'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (_existingImages.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_existingImages.length} saved photo${_existingImages.length == 1 ? '' : 's'}'
                '${_removedImageIds.isEmpty ? '' : ' · tap X to remove'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _ImageChip extends StatelessWidget {
  const _ImageChip({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -6,
          top: -6,
          child: Material(
            color: Colors.black87,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
