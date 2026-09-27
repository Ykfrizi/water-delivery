import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/core/config/api_config.dart';

final _imageExt = RegExp(
  r'\.(jpe?g|png|gif|webp|bmp|heic)(\?.*)?$',
  caseSensitive: false,
);

/// Resolves API/media paths to a phone-reachable absolute URL.
String resolveMediaUrl(String path) {
  var s = path.trim();
  if (s.isEmpty) return s;

  // Strip surrounding quotes / JSON escapes.
  if ((s.startsWith('"') && s.endsWith('"')) ||
      (s.startsWith("'") && s.endsWith("'"))) {
    s = s.substring(1, s.length - 1).trim();
  }

  if (s.startsWith('http://') || s.startsWith('https://')) {
    return _rewriteLocalhostToApiHost(s);
  }

  final origin = Uri.parse(ApiConfig.baseUrl).origin;

  // Common Laravel leftovers.
  if (s.startsWith('public/')) s = s.substring(7);
  if (s.startsWith('storage/app/public/')) {
    s = 'storage/${s.substring('storage/app/public/'.length)}';
  }

  if (!s.startsWith('/')) {
    // Bare relative image path → public disk URL.
    if (!s.startsWith('storage/') && _imageExt.hasMatch(s)) {
      s = 'storage/$s';
    }
    s = '/$s';
  } else if (!s.startsWith('/storage/') &&
      !s.startsWith('/api/') &&
      _imageExt.hasMatch(s)) {
    // "/products/x.jpg" → "/storage/products/x.jpg"
    s = '/storage$s';
  }

  return '$origin$s';
}

String _rewriteLocalhostToApiHost(String absoluteUrl) {
  final uri = Uri.tryParse(absoluteUrl);
  if (uri == null || !uri.hasScheme) return absoluteUrl;

  final host = uri.host.toLowerCase();
  final isLoopback =
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '0.0.0.0' ||
      host == '::1' ||
      host == '10.0.2.2'; // Android emulator alias for host machine

  if (!isLoopback) return absoluteUrl;

  final api = Uri.parse(ApiConfig.baseUrl);
  return uri
      .replace(
        scheme: api.scheme,
        host: api.host,
        port: api.hasPort ? api.port : null,
      )
      .toString();
}

String? _urlFromDynamic(dynamic value) {
  if (value == null) return null;

  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return null;
    // JSON-encoded list accidentally stored as string.
    if (s.startsWith('[') && s.endsWith(']')) {
      return null;
    }
    if (s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('/') ||
        s.startsWith('storage/') ||
        s.startsWith('public/') ||
        _imageExt.hasMatch(s)) {
      return resolveMediaUrl(s);
    }
    return null;
  }

  if (value is Map) {
    final nested = Map<String, dynamic>.from(value);
    for (final key in const [
      'url',
      'original_url',
      'originalUrl',
      'full_url',
      'fullUrl',
      'image_url',
      'imageUrl',
      'src',
      'path',
      'file_url',
      'fileUrl',
      'preview_url',
      'previewUrl',
      'large_url',
      'thumb_url',
      'thumbnail',
      'file_name',
      'fileName',
    ]) {
      final v = nested[key];
      if (v is String && v.trim().isNotEmpty) {
        var candidate = v.trim();
        // Spatie sometimes returns only file_name — prefix storage if needed.
        if (key == 'file_name' || key == 'fileName') {
          final dir =
              nested['directory']?.toString() ??
              nested['collection']?.toString();
          if (dir != null && dir.isNotEmpty && !candidate.contains('/')) {
            candidate = '$dir/$candidate';
          }
        }
        final resolved = resolveMediaUrl(candidate);
        if (resolved.isNotEmpty) return resolved;
      }
    }
  }
  return null;
}

void _collectFromList(List list, void Function(String? url) add) {
  for (final item in list) {
    add(_urlFromDynamic(item));
  }
}

/// All product image URLs from flexible API JSON (gallery / media arrays).
List<String> productImageUrlsFrom(Map<String, dynamic> json) {
  final found = <String>[];

  void add(String? url) {
    if (url == null || url.isEmpty || found.contains(url)) return;
    found.add(url);
  }

  // Nested product object (common Laravel resource wrapping).
  final nestedProduct = json['product'];
  if (nestedProduct is Map) {
    for (final url in productImageUrlsFrom(
      Map<String, dynamic>.from(nestedProduct),
    )) {
      add(url);
    }
  }

  for (final key in const [
    'images',
    'photos',
    'pictures',
    'media',
    'gallery',
    'product_images',
    'image_urls',
    'imageUrls',
    'files',
    'attachments',
  ]) {
    final value = json[key];
    if (value is List) {
      _collectFromList(value, add);
    } else if (value is String && value.trim().startsWith('[')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) _collectFromList(decoded, add);
      } catch (_) {
        /* ignore */
      }
    } else {
      add(_urlFromDynamic(value));
    }
  }

  for (final key in const [
    'image_url',
    'imageUrl',
    'photo_url',
    'photoUrl',
    'thumbnail_url',
    'thumbnailUrl',
    'cover_image',
    'coverImage',
    'featured_image',
    'featuredImage',
    'image',
    'photo',
    'picture',
    'thumbnail',
    'cover',
  ]) {
    add(_urlFromDynamic(json[key]));
  }

  return found;
}

/// First product image URL, or null when none.
String? productImageUrlFrom(Map<String, dynamic> json) {
  final urls = productImageUrlsFrom(json);
  return urls.isEmpty ? null : urls.first;
}

/// One saved catalog photo. [id] is required to delete it on the API.
class ProductImageRef {
  const ProductImageRef({this.id, required this.url});

  final int? id;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is ProductImageRef && other.id == id && other.url == url;

  @override
  int get hashCode => Object.hash(id, url);
}

int? _parseImageId(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

/// Saved product images with ids when the API provides them (edit / remove).
List<ProductImageRef> productImageItemsFrom(Map<String, dynamic> json) {
  final items = <ProductImageRef>[];
  final seen = <String>{};

  void add(int? id, String? url) {
    if (url == null || url.isEmpty || seen.contains(url)) return;
    seen.add(url);
    items.add(ProductImageRef(id: id, url: url));
  }

  void addFromValue(dynamic value) {
    if (value is List) {
      for (final item in value) {
        addFromValue(item);
      }
      return;
    }
    if (value is String && value.trim().startsWith('[')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) addFromValue(decoded);
      } catch (_) {
        /* ignore */
      }
      return;
    }
    if (value is Map) {
      final nested = Map<String, dynamic>.from(value);
      add(_parseImageId(nested['id']), _urlFromDynamic(value));
      return;
    }
    add(null, _urlFromDynamic(value));
  }

  final nestedProduct = json['product'];
  if (nestedProduct is Map) {
    for (final item in productImageItemsFrom(
      Map<String, dynamic>.from(nestedProduct),
    )) {
      add(item.id, item.url);
    }
  }

  for (final key in const [
    'images',
    'photos',
    'pictures',
    'media',
    'gallery',
    'product_images',
    'image_urls',
    'imageUrls',
    'files',
    'attachments',
  ]) {
    if (json[key] != null) addFromValue(json[key]);
  }

  for (final url in productImageUrlsFrom(json)) {
    add(null, url);
  }

  return items;
}

/// Square product thumb with a water-drop fallback when no image is set.
class ProductImageThumb extends StatelessWidget {
  const ProductImageThumb({
    super.key,
    this.imageUrl,
    this.size = 56,
    this.borderRadius = 12,
    this.badgeCount,
  });

  final String? imageUrl;
  final double size;
  final double borderRadius;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final raw = imageUrl?.trim();
    final url = (raw == null || raw.isEmpty) ? null : resolveMediaUrl(raw);
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? _fallback(context)
            : Image.network(
                url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, _, _) => _fallback(context),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Center(
                      child: SizedBox(
                        width: size * 0.28,
                        height: size * 0.28,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
              ),
      ),
    );

    final extra = badgeCount;
    if (extra == null || extra <= 1) return thumb;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        thumb,
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+${extra - 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Icon(
        Icons.water_drop_outlined,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
        size: size * 0.42,
      ),
    );
  }
}
