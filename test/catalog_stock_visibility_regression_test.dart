import 'package:flutter_test/flutter_test.dart';
import 'package:van2/public_catalog_service.dart';

void main() {
  group('catalog stock visibility regression', () {
    test('hides products with zero stock', () {
      expect(
        catalogProductInStockForRegressionTest(<String, dynamic>{
          'name': 'กาแฟ',
          'stock': 0,
        }),
        isFalse,
      );
    });

    test('shows products with positive stock', () {
      expect(
        catalogProductInStockForRegressionTest(<String, dynamic>{
          'name': 'กาแฟ',
          'stock': 3,
        }),
        isTrue,
      );
    });

    test('shows products without stock field as unlimited', () {
      expect(
        catalogProductInStockForRegressionTest(<String, dynamic>{
          'name': 'บริการล้างรถ',
        }),
        isTrue,
      );
    });

    test('hides variant products when every active variant is out of stock', () {
      expect(
        catalogProductInStockForRegressionTest(<String, dynamic>{
          'hasVariants': true,
          'variants': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'v1',
              'price': 120,
              'stock': 0,
              'isActive': true,
            },
            <String, dynamic>{
              'id': 'v2',
              'price': 150,
              'stock': 0,
              'isActive': true,
            },
          ],
        }),
        isFalse,
      );
    });

    test('shows variant products when at least one variant has stock', () {
      expect(
        catalogProductInStockForRegressionTest(<String, dynamic>{
          'hasVariants': true,
          'variants': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'v1',
              'price': 120,
              'stock': 0,
              'isActive': true,
            },
            <String, dynamic>{
              'id': 'v2',
              'price': 150,
              'stock': 2,
              'isActive': true,
            },
          ],
        }),
        isTrue,
      );
    });
  });
}
