import 'help_center_content.dart';
import '../pricing_config_service.dart';
import '../tax_pricing_policy.dart';

/// สรุปอัตราจาก `pricing_config/global` สำหรับศูนย์ช่วยเหลือ (ฟังแอดมินแบบ real-time)
class HelpPricingSummary {
  HelpPricingSummary._();

  static const Set<String> dynamicArticleIds = <String>{
    'delivery_fee',
    'nationwide_shipping',
  };

  static bool isDynamicArticle(String id) => dynamicArticleIds.contains(id);

  static String bodyForArticle(
    HelpArticle article,
    GlobalPricingConfig config,
    bool english,
  ) {
    return switch (article.id) {
      'delivery_fee' => deliveryFeeBody(config, english),
      'nationwide_shipping' => nationwideShippingBody(config, english),
      _ => article.body(english),
    };
  }

  static String deliveryFeeBody(GlobalPricingConfig config, bool english) {
    if (english) {
      return '''
Current rates set by platform admin (updated automatically)

Local delivery
• Base fee: ${_fmtBaht(config.shippingBaseFee)}
• After ${_fmtKm(config.shippingMinBillableKm)} km: ${_fmtBaht(config.shippingPerKmFee)} per km
• Shop without map coordinates: ${_fmtBaht(config.shippingMissingCoordsFee)}

Ride-hailing service
• Base fee: ${_fmtBaht(config.travelBaseFee)}
• After ${_fmtKm(config.travelMinBillableKm)} km: ${_fmtBaht(config.travelPerKmFee)} per km

Multi-shop market orders (within ${_fmtMeters(config.marketHubRadiusMeters)} m, at least ${config.marketMultiShopMinShops} shops)
• Collection fee: ${_fmtBaht(config.marketMultiShopCollectionFee)} per checkout
• Service fee: ${_fmtBaht(config.marketServiceFeePerOrder)} per shop order

The exact amount in your cart depends on distance, weight, and items — review before confirming.''';
    }

    return '''
อัตราปัจจุบันที่แอดมินกำหนด (อัปเดตอัตโนมัติ)

ค่าส่งท้องถิ่น
• ค่าส่งฐาน: ${_fmtBaht(config.shippingBaseFee)}
• หลังระยะขั้นต่ำ ${_fmtKm(config.shippingMinBillableKm)} กม.: ${_fmtBaht(config.shippingPerKmFee)} ต่อกม.
• ร้านไม่มีพิกัด: ${_fmtBaht(config.shippingMissingCoordsFee)}

บริการโดยสาร
• ค่าโดยสารฐาน: ${_fmtBaht(config.travelBaseFee)}
• หลังระยะขั้นต่ำ ${_fmtKm(config.travelMinBillableKm)} กม.: ${_fmtBaht(config.travelPerKmFee)} ต่อกม.

สั่งหลายร้านในตลาด (รัศมี ${_fmtMeters(config.marketHubRadiusMeters)} ม., อย่างน้อย ${config.marketMultiShopMinShops} ร้าน)
• ค่ารวบรวมสินค้า: ${_fmtBaht(config.marketMultiShopCollectionFee)} ต่างร้าน
• ค่าบริการ: ${_fmtBaht(config.marketServiceFeePerOrder)} ต่อบิล

ยอดในตะกร้าคำนวณจากระยะทาง น้ำหนัก และรายการจริง — ตรวจสอบก่อนยืนยันสั่งซื้อ''';
  }

  static String nationwideShippingBody(GlobalPricingConfig config, bool english) {
    if (english) {
      return '''
Nationwide shipping rates (synced from admin)

• Base fee: ${_fmtBaht(config.nationwideBaseFee)}
• Per kg: ${_fmtBaht(config.nationwidePerKgFee)}
• Remote area surcharge: ${_fmtBaht(config.nationwideRemoteSurcharge)}

Enter the recipient address in the nationwide category. The cart shows the estimated fee before checkout.''';
    }

    return '''
อัตราส่งทั่วประเทศ (อัปเดตจากแอดมินอัตโนมัติ)

• ค่าฐาน: ${_fmtBaht(config.nationwideBaseFee)}
• ต่อกก.: ${_fmtBaht(config.nationwidePerKgFee)}
• ส่วนเพิ่มพื้นที่ห่างไกล: ${_fmtBaht(config.nationwideRemoteSurcharge)}

เลือกหมวดส่งทั่วประเทศและกรอกที่อยู่ผู้รับ แอปจะแสดงค่าส่งประมาณการในตะกร้าก่อนยืนยัน''';
  }

  static String _fmtBaht(double value) => '฿${TaxPricingPolicy.formatPrice(value)}';

  static String _fmtKm(double km) {
    return km % 1 == 0 ? km.toInt().toString() : km.toStringAsFixed(1);
  }

  static String _fmtMeters(double meters) {
    return meters % 1 == 0
        ? meters.toInt().toString()
        : meters.toStringAsFixed(0);
  }
}
