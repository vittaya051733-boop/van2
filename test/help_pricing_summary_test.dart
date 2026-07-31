import 'package:flutter_test/flutter_test.dart';

import 'package:van2/data/help_center_content.dart';
import 'package:van2/data/help_pricing_summary.dart';
import 'package:van2/pricing_config_service.dart';

void main() {
  test('delivery fee help body reflects admin pricing config', () {
    const config = GlobalPricingConfig(
      taxableMarkupRate: 0.08,
      nonTaxableMarkupRate: 0.05,
      toppingMarkupRate: 0.07,
      shippingBaseFee: 30,
      shippingPerKmFee: 15,
      shippingMinBillableKm: 2,
      shippingMissingCoordsFee: 35,
      travelBaseFee: 28,
      travelPerKmFee: 14,
      travelMinBillableKm: 1.5,
      nationwideBaseFee: 50,
      nationwidePerKgFee: 20,
      nationwideRemoteSurcharge: 40,
      marketHubLatitude: 17.28,
      marketHubLongitude: 102.87,
      marketHubRadiusMeters: 200,
      marketMultiShopMinShops: 3,
      marketMultiShopCollectionFee: 8,
      marketServiceFeePerOrder: 6,
    );

    final article = HelpCenterContent.articles
        .firstWhere((item) => item.id == 'delivery_fee');

    final thai = HelpPricingSummary.bodyForArticle(article, config, false);
    expect(thai, contains('฿30'));
    expect(thai, isNot(contains('8%')));
    expect(thai, contains('3 ร้าน'));

    final english = HelpPricingSummary.bodyForArticle(article, config, true);
    expect(english, contains('฿30'));
    expect(english, isNot(contains('8%')));
    expect(english, contains('at least 3 shops'));
  });
}
