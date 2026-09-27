import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/core/network/api_response.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/marketplace_models.dart';

/// Public marketplace — no authentication (handoff §5).
class MarketplaceApi {
  MarketplaceApi(this._dio);

  final Dio _dio;

  Future<List<MarketplaceVendor>> listVendors({
    String? q,
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? sort,
    int perPage = 50,
  }) async {
    try {
      final r = await _dio.get<dynamic>(
        '/marketplace/vendors',
        queryParameters: <String, dynamic>{
          'per_page': perPage,
          if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
          'latitude': ?latitude,
          'longitude': ?longitude,
          'radius_km': ?radiusKm,
          if (sort != null && sort.trim().isNotEmpty) 'sort': sort.trim(),
        },
      );
      if (!isSuccess(r)) throwApiResponse(r);
      return decodeDataList(r.data)
          .map(MarketplaceVendor.fromJson)
          .where((v) => v.slug.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<Map<String, dynamic>> getVendor(String vendorSlug) async {
    try {
      final seg = apiPathSegment(vendorSlug);
      final r = await _dio.get<dynamic>('/marketplace/vendors/$seg');
      if (!isSuccess(r)) throwApiResponse(r);
      return unwrapDataMap(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  Future<List<MarketplaceProduct>> getVendorProducts(
    String vendorSlug, {
    String? q,
    bool? inStock,
    int perPage = 50,
    String? vendorName,
  }) async {
    try {
      final seg = apiPathSegment(vendorSlug);
      final query = <String, dynamic>{
        'per_page': perPage,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'in_stock': ?inStock,
      };

      // Try common marketplace product routes.
      final paths = <String>[
        '/marketplace/vendors/$seg/products',
        '/marketplace/vendors/$seg/catalog',
        '/vendors/$seg/products',
      ];

      List<Map<String, dynamic>> rows = [];
      Object? lastError;

      for (final path in paths) {
        try {
          final r = await _dio.get<dynamic>(path, queryParameters: query);
          if (!isSuccess(r)) {
            lastError = parseApiError(r.statusCode ?? 0, r.data);
            continue;
          }
          rows = productsFromPayload(r.data);
          if (rows.isNotEmpty) break;
        } on DioException catch (e) {
          lastError = e;
          continue;
        }
      }

      // Fallback: products embedded on vendor profile.
      if (rows.isEmpty) {
        try {
          final profile = await getVendor(vendorSlug);
          rows = productsFromPayload(profile);
        } catch (_) {
          /* keep empty */
        }
      }

      if (rows.isEmpty && lastError is DioException) {
        throwFromDio(lastError);
      }

      return rows
          .map(
            (e) => MarketplaceProduct.fromJson(
              e,
              vendorSlug: vendorSlug,
              vendorName: vendorName,
            ),
          )
          .toList();
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }

  /// Approved vendors with each vendor's full product catalog attached.
  Future<List<VendorCatalog>> listVendorsWithProducts({
    String? q,
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? sort,
    int perVendor = 100,
  }) async {
    final vendors = await listVendors(
      q: q,
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
      sort: sort,
      perPage: 200,
    );

    final catalogs = await Future.wait(
      vendors.map((vendor) async {
        List<MarketplaceProduct> products = const [];
        try {
          products = await getVendorProducts(
            vendor.slug,
            vendorName: vendor.name,
            perPage: perVendor,
            q: q,
          );
        } catch (_) {
          products = [
            for (final row in vendor.embeddedProducts)
              MarketplaceProduct.fromJson(
                row,
                vendorSlug: vendor.slug,
                vendorName: vendor.name,
              ),
          ];
        }
        return VendorCatalog(vendor: vendor, products: products);
      }),
    );

    return catalogs;
  }

  /// Loads products across marketplace vendors for the customer Products tab.
  ///
  /// Fetches every approved vendor page, then each vendor's full product list,
  /// sorted newest-first so customers can browse all recent products.
  Future<List<MarketplaceProduct>> listAllProducts({
    String? q,
    int vendorLimit = 100,
    int perVendor = 100,
    bool preferFullCatalog = true,
  }) async {
    final vendors = await _listAllVendors(perPage: vendorLimit);
    final products = <MarketplaceProduct>[];
    final seen = <int>{};
    final query = q?.trim();

    for (final vendor in vendors) {
      List<MarketplaceProduct> fetched = const [];

      if (preferFullCatalog) {
        try {
          fetched = await getVendorProducts(
            vendor.slug,
            vendorName: vendor.name,
            perPage: perVendor,
            q: query,
          );
        } catch (_) {
          fetched = const [];
        }
      }

      if (fetched.isEmpty) {
        final rows = vendor.embeddedProducts;
        fetched = [
          for (final row in rows)
            MarketplaceProduct.fromJson(
              row,
              vendorSlug: vendor.slug,
              vendorName: vendor.name,
            ),
        ];
        if (query != null && query.isNotEmpty) {
          final lower = query.toLowerCase();
          fetched = fetched
              .where(
                (p) =>
                    p.name.toLowerCase().contains(lower) ||
                    (p.vendorName ?? '').toLowerCase().contains(lower),
              )
              .toList();
        }
      }

      for (final p in fetched) {
        final id = p.id;
        if (id != null) {
          if (seen.contains(id)) continue;
          seen.add(id);
        }
        products.add(p);
      }
    }

    products.sort(_compareProductsNewestFirst);
    return products;
  }

  Future<List<MarketplaceVendor>> _listAllVendors({int perPage = 100}) async {
    final all = <MarketplaceVendor>[];
    final first = await listVendors(perPage: perPage);
    all.addAll(first);
    // Single-page APIs return everything; if we already hit the page size,
    // try a larger page once more to reduce truncation risk.
    if (first.length >= perPage && perPage < 200) {
      try {
        final wider = await listVendors(perPage: 200);
        if (wider.length > all.length) {
          all
            ..clear()
            ..addAll(wider);
        }
      } catch (_) {
        /* keep first page */
      }
    }
    return all;
  }

  static int _compareProductsNewestFirst(
    MarketplaceProduct a,
    MarketplaceProduct b,
  ) {
    final aTime = _productRecencyScore(a);
    final bTime = _productRecencyScore(b);
    final byTime = bTime.compareTo(aTime);
    if (byTime != 0) return byTime;
    final aId = a.id ?? 0;
    final bId = b.id ?? 0;
    return bId.compareTo(aId);
  }

  static int _productRecencyScore(MarketplaceProduct p) {
    for (final key in const [
      'created_at',
      'createdAt',
      'updated_at',
      'updatedAt',
      'published_at',
    ]) {
      final raw = p.raw[key];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return p.id ?? 0;
  }

  Future<List<Map<String, dynamic>>> getVendorReviews(String vendorSlug) async {
    try {
      final seg = apiPathSegment(vendorSlug);
      final r = await _dio.get<dynamic>('/marketplace/vendors/$seg/reviews');
      if (!isSuccess(r)) throwApiResponse(r);
      return decodeDataList(r.data);
    } on DioException catch (e) {
      throwFromDio(e);
    }
  }
}
