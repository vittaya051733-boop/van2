import 'package:flutter_test/flutter_test.dart';
import 'package:van2/models/home_page_lock_config.dart';
import 'package:van2/models/home_quick_action_config.dart';
import 'package:van2/models/home_shelves_config.dart';
import 'package:van2/public_catalog_service.dart';

PublicCatalogProduct _product(
  String id,
  String serviceType, {
  bool nationwide = false,
}) {
  return PublicCatalogProduct(
    id: id,
    shopId: 'shop-$id',
    shopName: 'Shop',
    shopImageUrl: null,
    shopLatitude: null,
    shopLongitude: null,
    data: <String, dynamic>{
      'serviceType': serviceType,
      if (nationwide) 'canShipNationwide': true,
    },
  );
}

void main() {
  group('home quick action config', () {
    test('missing quickActions keeps every button enabled', () {
      final config = HomeQuickActionConfig.fromFirestore(
        <String, dynamic>{'featuredProductIds': <String>['a']},
      );
      for (final spec in HomeQuickActionConfig.specs) {
        expect(config.isEnabled(spec.id), isTrue, reason: spec.id);
      }
      expect(
        config.enabledRetailServiceTypes,
        HomeQuickActionConfig.retailServiceTypeById.values.toSet(),
      );
    });

    test('disabled buttons are removed and remaining keep order', () {
      const all = <String>[
        'travel',
        'restaurant',
        'market',
        'shop',
        'pharmacy',
        'shop-map',
        'nationwide-shipping',
        'more',
      ];
      final config = HomeQuickActionConfig.fromFirestore(<String, dynamic>{
        'quickActions': <String, dynamic>{
          'restaurant': false,
          'shop-map': false,
        },
      });
      expect(
        all.where(config.isEnabled).toList(),
        <String>[
          'travel',
          'market',
          'shop',
          'pharmacy',
          'nationwide-shipping',
          'more',
        ],
      );
    });

    test('unknown keys are ignored', () {
      final config = HomeQuickActionConfig.fromFirestore(<String, dynamic>{
        'quickActions': <String, dynamic>{'legacy': false, 'shop': false},
      });
      expect(config.isEnabled('legacy'), isTrue);
      expect(config.isEnabled('shop'), isFalse);
      expect(config.isEnabled('market'), isTrue);
    });
  });

  group('home page lock config', () {
    test('missing homeLock keeps home usable', () {
      final config = HomeShelvesConfig.fromFirestore(
        <String, dynamic>{'quickActions': <String, dynamic>{}},
      );
      expect(config.homeLock.enabled, isFalse);
      expect(config.homeLock.message, HomePageLockConfig.defaultMessage);
    });

    test('enabled homeLock uses custom message', () {
      final config = HomeShelvesConfig.fromFirestore(<String, dynamic>{
        'homeLock': <String, dynamic>{
          'enabled': true,
          'message': 'ปิดปรับปรุงชั่วคราว',
        },
      });
      expect(config.homeLock.enabled, isTrue);
      expect(config.homeLock.message, 'ปิดปรับปรุงชั่วคราว');
    });

    test('empty message falls back to default', () {
      final config = HomePageLockConfig.fromFirestore(<String, dynamic>{
        'homeLock': <String, dynamic>{'enabled': true, 'message': '   '},
      });
      expect(config.message, HomePageLockConfig.defaultMessage);
    });
  });

  group('home product visibility', () {
    final products = <PublicCatalogProduct>[
      _product('food-1', 'ร้านอาหาร'),
      _product('market-1', 'ตลาด'),
      _product('shop-1', 'ร้านค้า'),
      _product('shop-nationwide', 'ร้านค้า', nationwide: true),
      _product('pharmacy-1', 'ร้านขายยา'),
    ];

    test('closing a category hides those products from home', () {
      final filtered = PublicCatalogService.filterHomeRetailProducts(
        products,
        enabledServiceTypes: <String>{'ตลาด', 'ร้านค้า', 'ร้านขายยา'},
      );
      expect(
        filtered.map((product) => product.id).toList(),
        <String>['market-1', 'shop-1', 'shop-nationwide', 'pharmacy-1'],
      );
    });

    test('closing nationwide hides nationwide products from home', () {
      final filtered = PublicCatalogService.filterHomeRetailProducts(
        products,
        nationwideEnabled: false,
      );
      expect(
        filtered.map((product) => product.id).toList(),
        <String>['food-1', 'market-1', 'shop-1', 'pharmacy-1'],
      );
    });

    test('closing every product category hides the home shelves', () {
      final filtered = PublicCatalogService.filterHomeRetailProducts(
        products,
        enabledServiceTypes: <String>{},
      );
      expect(filtered, isEmpty);
    });
  });
}
