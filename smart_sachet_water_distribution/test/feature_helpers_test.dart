import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_sachet_water_distribution/core/pagination/paginated_result.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_tracking.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/cart_line.dart';
import 'package:smart_sachet_water_distribution/features/maps/data/directions_service.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_location_parser.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_marker_point.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/service_area.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/vendor_rating.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_settlement.dart';

void main() {
  group('Revenue policy', () {
    test('splits commission and delivery revenue', () {
      expect(kPlatformServiceFeeGhs, 1);
      expect(vendorCommissionFor(25), 1.25);
      expect(adminDeliveryShareFor(10), 2);
      expect(riderDeliveryShareFor(10), 8);
    });

    test('reconciles cash sales and prepaid commission offset', () {
      final settlement = VendorSettlement.fromOrders([
        {
          'status': 'delivered',
          'payment_method': 'cash_on_delivery',
          'payment_status': 'paid',
          'total': 100,
        },
        {
          'status': 'delivered',
          'payment_method': 'paystack',
          'payment_status': 'paid',
          'total': 200,
        },
      ], now: DateTime(2026, 9, 6));

      expect(settlement.cashSales, 100);
      expect(settlement.prepaidSales, 200);
      expect(settlement.commissionDue, 15);
      expect(settlement.prepaidCommissionOffset, 10);
      expect(settlement.cashCommissionDue, 5);
    });
  });

  group('VendorRating', () {
    test('parses average and count', () {
      final r = VendorRating.fromVendorJson({
        'average_rating': 4.5,
        'reviews_count': 12,
      });
      expect(r.average, 4.5);
      expect(r.count, 12);
      expect(r.hasRatings, isTrue);
    });

    test('computes average from review list', () {
      final r = VendorRating.fromVendorJson({
        'reviews': [
          {'rating': 5},
          {'rating': 3},
        ],
      });
      expect(r.average, 4);
      expect(r.count, 2);
    });
  });

  group('PaginatedResult', () {
    test('hasMore from last_page', () {
      final p = parsePaginatedMaps(
        {
          'data': [
            {'id': 1},
            {'id': 2},
          ],
          'meta': {
            'current_page': 1,
            'last_page': 3,
            'per_page': 2,
            'total': 6,
          },
        },
        page: 1,
        perPage: 2,
        decodeList: (body) {
          final data = (body as Map)['data'] as List;
          return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        },
      );
      expect(p.items.length, 2);
      expect(p.hasMore, isTrue);
      expect(p.lastPage, 3);
    });
  });

  group('DirectionsService.decodePolyline', () {
    test('decodes a short polyline', () {
      // Encoded for a tiny segment near (38.5, -120.2)
      final pts = DirectionsService.decodePolyline('_p~iF~ps|U');
      expect(pts, isNotEmpty);
      expect(pts.first, isA<LatLng>());
    });
  });

  group('OrderTrackingSnapshot', () {
    test('reads courier and destination', () {
      final snap = OrderTrackingSnapshot.fromOrder({
        'status': 'out_for_delivery',
        'courier_latitude': 5.6,
        'courier_longitude': -0.18,
        'shipping_address': {'latitude': 5.61, 'longitude': -0.19},
      });
      expect(snap.isLive, isTrue);
      expect(snap.courier?.latitude, 5.6);
      expect(snap.destination?.latitude, 5.61);
      expect(snap.canShowMap, isTrue);
    });
  });

  group('ServiceArea', () {
    test('Ho centre is inside, Accra is not', () {
      expect(ServiceArea.contains(6.6110, 0.4703), isTrue);
      expect(ServiceArea.contains(5.6037, -0.1870), isFalse);
      expect(ServiceArea.cityIsAllowed('Ho'), isTrue);
      expect(ServiceArea.cityIsAllowed('Accra'), isFalse);
    });
  });

  group('parseCoordinates', () {
    test('reads top-level live order coordinates', () {
      final coords = parseCoordinates({
        'order_number': 'SM-1',
        'latitude': 6.6110,
        'longitude': 0.4703,
      });
      expect(coords?.lat, 6.6110);
      expect(coords?.lng, 0.4703);
    });

    test('reads nested customer last_latitude', () {
      final coords = parseCoordinates({
        'customer': {
          'name': 'Ama',
          'last_latitude': 6.62,
          'last_longitude': 0.48,
        },
      });
      expect(coords?.lat, 6.62);
      expect(coords?.lng, 0.48);
    });

    test('markerFromOrder uses person name', () {
      final marker = markerFromOrder({
        'id': 9,
        'name': 'Kofi',
        'latitude': 6.61,
        'longitude': 0.47,
        'live': true,
      });
      expect(marker?.title, 'Kofi');
      expect(marker?.kind, MapMarkerKind.customer);
    });
  });

  group('stripHtmlInstructions', () {
    test('strips google directions html', () {
      expect(
        stripHtmlInstructions('Turn <b>left</b> onto <div>Market St</div>'),
        'Turn left onto Market St',
      );
    });
  });
}
