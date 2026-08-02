import 'package:flutter_test/flutter_test.dart';
import 'package:van2/public_catalog_service.dart';
import 'package:van2/services/nationwide_catalog_service.dart';

PublicCatalogProduct _nationwideProduct({
  required String id,
  required String shopId,
  required String name,
  String catalogType = 'อาหาร',
}) {
  return PublicCatalogProduct(
    id: id,
    shopId: shopId,
    shopName: 'ร้าน $shopId',
    shopImageUrl: 'https://example.com/$shopId.jpg',
    shopLatitude: 13.7563,
    shopLongitude: 100.5018,
    data: <String, dynamic>{
      'name': name,
      'catalogType': catalogType,
      'canShipNationwide': true,
    },
  );
}

PublicCatalogSection _nationwideSection({
  required String shopId,
  required List<PublicCatalogProduct> products,
}) {
  return PublicCatalogSection(
    shopId: shopId,
    shopName: 'ร้าน $shopId',
    shopImageUrl: 'https://example.com/$shopId.jpg',
    shopLatitude: 13.7563,
    shopLongitude: 100.5018,
    products: products,
  );
}

void main() {
  group('nationwide shipping eligibility regression', () {
    test('positive reason can show product even when boolean is stale', () {
      expect(
        nationwideShippingEligibleForRegressionTest(<String, dynamic>{
          'canShipNationwide': false,
          'nationwideShippingReason':
              'ทุเรียนเป็นผลไม้สดที่สามารถแพ็คและจัดส่งได้ทั่วประเทศโดยขนส่งทั่วไป',
        }),
        isTrue,
      );
    });

    test('negative reason does not show product', () {
      expect(
        nationwideShippingEligibleForRegressionTest(<String, dynamic>{
          'canShipNationwide': false,
          'nationwideShippingReason': 'สินค้าไม่เหมาะกับการจัดส่งทั่วประเทศ',
        }),
        isFalse,
      );
    });

    test('explicit true boolean is enough for manual merchant selection', () {
      expect(
        nationwideShippingEligibleForRegressionTest(<String, dynamic>{
          'canShipNationwide': true,
        }),
        isTrue,
      );
    });

    test('closed shop active flag does not block nationwide product', () {
      expect(
        nationwideShippingEligibleForRegressionTest(<String, dynamic>{
          'isActive': false,
          'canShipNationwide': true,
          'nationwideShippingReason':
              'ร้านค้าระบุว่าสินค้านี้เหมาะกับการส่งทั่วประเทศ',
        }),
        isTrue,
      );
    });
  });

  group('nationwide category catalog regression', () {
    test('two shops in same category produce one picker entry with count 2', () {
      final sections = <PublicCatalogSection>[
        _nationwideSection(
          shopId: 'shop-a',
          products: <PublicCatalogProduct>[
            _nationwideProduct(
              id: 'p1',
              shopId: 'shop-a',
              name: 'ข้าวผัด A',
            ),
          ],
        ),
        _nationwideSection(
          shopId: 'shop-b',
          products: <PublicCatalogProduct>[
            _nationwideProduct(
              id: 'p2',
              shopId: 'shop-b',
              name: 'ข้าวผัด B',
            ),
          ],
        ),
      ];

      final categories =
          NationwideCatalogService.buildCategoriesFromSections(sections);

      expect(categories, hasLength(1));
      expect(categories.single.label, 'อาหาร');
      expect(categories.single.productCount, 2);
    });

    test('productsInCategoryFromSections returns mixed-shop products only', () {
      final sections = <PublicCatalogSection>[
        _nationwideSection(
          shopId: 'shop-a',
          products: <PublicCatalogProduct>[
            _nationwideProduct(
              id: 'food-a',
              shopId: 'shop-a',
              name: 'ส้มตำ',
            ),
            _nationwideProduct(
              id: 'gadget-a',
              shopId: 'shop-a',
              name: 'พัดลม',
              catalogType: 'เครื่องใช้ไฟฟ้า',
            ),
          ],
        ),
        _nationwideSection(
          shopId: 'shop-b',
          products: <PublicCatalogProduct>[
            _nationwideProduct(
              id: 'food-b',
              shopId: 'shop-b',
              name: 'ลาบ',
            ),
          ],
        ),
      ];

      final foodProducts = NationwideCatalogService.productsInCategoryFromSections(
        sections,
        'อาหาร',
      );

      expect(foodProducts, hasLength(2));
      expect(
        foodProducts.map((product) => product.shopId).toSet(),
        <String>{'shop-a', 'shop-b'},
      );
    });

    test('categories sort by product count descending then label', () {
      final sections = <PublicCatalogSection>[
        _nationwideSection(
          shopId: 'shop-a',
          products: <PublicCatalogProduct>[
            _nationwideProduct(
              id: 'food-1',
              shopId: 'shop-a',
              name: 'อาหาร 1',
            ),
          ],
        ),
        _nationwideSection(
          shopId: 'shop-b',
          products: <PublicCatalogProduct>[
            _nationwideProduct(
              id: 'gadget-1',
              shopId: 'shop-b',
              name: 'พัดลม',
              catalogType: 'เครื่องใช้ไฟฟ้า',
            ),
            _nationwideProduct(
              id: 'gadget-2',
              shopId: 'shop-b',
              name: 'ไดร์เป่าผม',
              catalogType: 'เครื่องใช้ไฟฟ้า',
            ),
          ],
        ),
      ];

      final categories =
          NationwideCatalogService.buildCategoriesFromSections(sections);

      expect(categories, hasLength(2));
      expect(categories.first.label, 'เครื่องใช้ไฟฟ้า');
      expect(categories.first.productCount, 2);
      expect(categories.last.label, 'อาหาร');
      expect(categories.last.productCount, 1);
    });

    test('nationwide product keeps shop name for detail and checkout', () {
      final product = _nationwideProduct(
        id: 'p1',
        shopId: 'shop-a',
        name: 'สินค้าทดสอบ',
      );

      expect(product.shopName, 'ร้าน shop-a');
      expect(product.shopId, 'shop-a');
    });
  });
}
