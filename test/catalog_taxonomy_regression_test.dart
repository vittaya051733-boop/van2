import 'package:flutter_test/flutter_test.dart';
import 'package:van2/category_catalog_screen.dart';

void main() {
  group('catalog taxonomy regression', () {
    test('dragon fruit is always fruit even if stale category exists', () {
      expect(
        catalogTypeForProductDataForRegressionTest(<String, dynamic>{
          'serviceType': 'ตลาด',
          'name': 'แก้วมังกรสด',
          'catalogType': 'ของสด',
        }),
        'ผลไม้',
      );
    });

    test('fresh chicken and fresh meat stay in fresh goods', () {
      expect(
        catalogTypeForProductDataForRegressionTest(<String, dynamic>{
          'serviceType': 'ตลาด',
          'name': 'เนื้อไก่สด',
          'catalogType': 'เนื้อสัตว์',
        }),
        'ของสด',
      );
      expect(
        catalogTypeForProductDataForRegressionTest(<String, dynamic>{
          'serviceType': 'ตลาด',
          'name': 'หมูสด',
        }),
        'ของสด',
      );
    });

    test('processed dried squid stays processed seafood', () {
      expect(
        catalogTypeForProductDataForRegressionTest(<String, dynamic>{
          'serviceType': 'ตลาด',
          'name': 'ปลาหมึกแห้ง',
        }),
        'อาหารทะเลแปรรูป',
      );
    });

    test(
      'market and pharmacy taxonomy do not override restaurant products',
      () {
        expect(
          catalogTypeForProductDataForRegressionTest(<String, dynamic>{
            'serviceType': 'ร้านอาหาร',
            'name': 'ยำสมุนไพร',
          }),
          'อื่นๆ',
        );
        expect(
          catalogHeadingForProductDataForRegressionTest(<String, dynamic>{
            'serviceType': 'ร้านอาหาร',
            'name': 'ปลาหมึกผัดไข่เค็ม',
          }),
          'อื่นๆ',
        );
      },
    );

    test('pharmacy taxonomy only applies to pharmacy service type', () {
      expect(
        catalogTypeForProductDataForRegressionTest(<String, dynamic>{
          'serviceType': 'ร้านขายยา',
          'name': 'ยาแก้ปวดพารา',
        }),
        'ยาและเวชภัณฑ์',
      );
      expect(
        catalogTypeForProductDataForRegressionTest(<String, dynamic>{
          'serviceType': 'ร้านค้า',
          'name': 'ยาแก้ปวดพารา',
        }),
        'อื่นๆ',
      );
    });
  });
}
