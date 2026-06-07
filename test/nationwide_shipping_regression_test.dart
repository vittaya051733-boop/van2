import 'package:flutter_test/flutter_test.dart';
import 'package:van2/public_catalog_service.dart';

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
}
