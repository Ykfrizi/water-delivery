import 'package:flutter_test/flutter_test.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/product_image.dart';

void main() {
  group('productImageUrlsFrom', () {
    test('reads image_url and rewrites localhost', () {
      final urls = productImageUrlsFrom({
        'image_url': 'http://127.0.0.1:8000/storage/products/a.jpg',
      });
      expect(urls, isNotEmpty);
      expect(urls.first.contains('127.0.0.1'), isFalse);
      expect(urls.first.contains('/storage/products/a.jpg'), isTrue);
    });

    test('reads images list of maps', () {
      final urls = productImageUrlsFrom({
        'images': [
          {'url': '/storage/products/b.png'},
          {'original_url': 'storage/products/c.webp'},
        ],
      });
      expect(urls.length, 2);
      expect(urls.every((u) => u.startsWith('http')), isTrue);
    });

    test('rewrites localhost without a port to the API host', () {
      final urls = productImageUrlsFrom({
        'image_url': 'http://localhost/storage/products/a.jpg',
      });
      expect(urls, isNotEmpty);
      expect(urls.first.contains('localhost'), isFalse);
      expect(urls.first.contains('/storage/products/a.jpg'), isTrue);
      expect(urls.first.startsWith('http://10.'), isTrue);
    });

    test('reads nested product media', () {
      final urls = productImageUrlsFrom({
        'product': {
          'media': [
            {'original_url': '/storage/x.jpg'},
          ],
        },
      });
      expect(urls, isNotEmpty);
    });
  });

  group('productImageItemsFrom', () {
    test('keeps image ids for deletion', () {
      final items = productImageItemsFrom({
        'image_url': 'http://localhost/storage/products/20/a.jpg',
        'images': [
          {'id': 14, 'url': 'http://localhost/storage/products/20/a.jpg'},
          {'id': 15, 'url': '/storage/products/20/b.jpg'},
        ],
      });
      expect(items.length, 2);
      expect(items.map((e) => e.id).toList(), [14, 15]);
      expect(items.every((e) => e.url.contains('localhost') == false), isTrue);
    });
  });
}
