import 'help_pricing_summary.dart';

import '../pricing_config_service.dart';

class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.categoryKey,
    required this.titleTh,
    required this.titleEn,
    required this.bodyTh,
    required this.bodyEn,
    this.popular = false,
  });

  final String id;
  final String categoryKey;
  final String titleTh;
  final String titleEn;
  final String bodyTh;
  final String bodyEn;
  final bool popular;

  String title(bool english) => english ? titleEn : titleTh;
  String body(bool english) => english ? bodyEn : bodyTh;
}

class HelpCategory {
  const HelpCategory({
    required this.key,
    required this.labelTh,
    required this.labelEn,
    required this.iconName,
  });

  final String key;
  final String labelTh;
  final String labelEn;
  final String iconName;

  String label(bool english) => english ? labelEn : labelTh;
}

class HelpCenterContent {
  HelpCenterContent._();

  static const List<HelpCategory> categories = <HelpCategory>[
    HelpCategory(
      key: 'order_issue',
      labelTh: 'การสั่งซื้อ / สถานะออเดอร์',
      labelEn: 'Orders & status',
      iconName: 'receipt',
    ),
    HelpCategory(
      key: 'payment_refund',
      labelTh: 'ชำระเงิน / ขอคืนเงิน',
      labelEn: 'Payment & refunds',
      iconName: 'payment',
    ),
    HelpCategory(
      key: 'delivery_rider',
      labelTh: 'จัดส่ง / ไรเดอร์',
      labelEn: 'Delivery & riders',
      iconName: 'delivery',
    ),
    HelpCategory(
      key: 'product_shop',
      labelTh: 'สินค้า / ร้านค้า',
      labelEn: 'Products & shops',
      iconName: 'store',
    ),
    HelpCategory(
      key: 'account_login',
      labelTh: 'บัญชี / เข้าสู่ระบบ',
      labelEn: 'Account & sign-in',
      iconName: 'account',
    ),
    HelpCategory(
      key: 'app_bug',
      labelTh: 'แจ้งปัญหาแอป',
      labelEn: 'App issues',
      iconName: 'bug',
    ),
  ];

  static const List<HelpArticle> articles = <HelpArticle>[
    HelpArticle(
      id: 'how_to_order',
      categoryKey: 'order_issue',
      titleTh: 'สั่งซื้ออย่างไร?',
      titleEn: 'How do I place an order?',
      bodyTh:
          '1) เลือกสินค้าจากหน้าแรกหรือหมวดร้าน\n2) กดเพิ่มลงตะกร้าและเลือกท็อปปิ้ง (ถ้ามี)\n3) เปิดตะกร้า ตรวจสอบยอดและค่าส่ง\n4) ยืนยันสั่งซื้อและชำระเงินตามช่องทางที่ร้านรองรับ\n5) ติดตามสถานะได้ที่แท็บ "เส้นทาง" หรือ "ประวัติ"',
      bodyEn:
          '1) Browse products from home or shop categories\n2) Add items to cart and pick toppings if available\n3) Open cart, review subtotal and delivery fee\n4) Confirm the order and pay using supported methods\n5) Track status in the Roadmap or History tab',
      popular: true,
    ),
    HelpArticle(
      id: 'track_order',
      categoryKey: 'order_issue',
      titleTh: 'ดูสถานะออเดอร์ที่ไหน?',
      titleEn: 'Where can I track my order?',
      bodyTh:
          'ไปที่แท็บ "เส้นทาง" เพื่อดูออเดอร์ที่กำลังดำเนินการ\nออเดอร์ที่เสร็จ/ยกเลิก/คืนเงินแล้วอยู่ใน "ประวัติ" ภายในเส้นทางเดียวกัน',
      bodyEn:
          'Open the Roadmap tab for active orders.\nCompleted, cancelled, and refunded orders appear under History in the same area.',
      popular: true,
    ),
    HelpArticle(
      id: 'cancel_order',
      categoryKey: 'order_issue',
      titleTh: 'ยกเลิกออเดอร์ได้เมื่อไหร่?',
      titleEn: 'When can I cancel an order?',
      bodyTh:
          'ยกเลิกได้ก่อนร้านหรือไรเดอร์เริ่มเตรียม/รับงาน หากสถานะเปลี่ยนแล้ว กรุณาติดต่อแอดมินผ่าน "ติดต่อแอดมิน"',
      bodyEn:
          'You can cancel before the shop or rider starts preparing/picking up. After status changes, contact admin via Contact admin.',
      popular: true,
    ),
    HelpArticle(
      id: 'payment_methods',
      categoryKey: 'payment_refund',
      titleTh: 'ชำระเงินด้วยวิธีใดได้บ้าง?',
      titleEn: 'What payment methods are supported?',
      bodyTh:
          'ขึ้นกับร้านและประเภทออเดอร์ เช่น PromptPay/โอน/เงินสด\nหลังชำระ อาจต้องอัปโหลดสลิปในแอปเพื่อยืนยัน',
      bodyEn:
          'Depends on shop and order type (PromptPay, transfer, cash, etc.).\nYou may need to upload a payment slip in the app for confirmation.',
      popular: true,
    ),
    HelpArticle(
      id: 'refund_request',
      categoryKey: 'payment_refund',
      titleTh: 'ขอคืนเงินอย่างไร?',
      titleEn: 'How do I request a refund?',
      bodyTh:
          'เปิด "ติดต่อแอดมิน" เลือกหัวข้อ "การชำระเงิน / ขอคืนเงิน" แนบรูปและรายละเอียดออเดอร์\nแอดมินจะตรวจสอบและตอบกลับใน "ข้อความถึงแอดมิน"',
      bodyEn:
          'Open Contact admin, choose Payment / refund, attach photos and order details.\nAdmin replies appear in Messages to admin.',
      popular: true,
    ),
    HelpArticle(
      id: 'delivery_fee',
      categoryKey: 'delivery_rider',
      titleTh: 'ค่าส่งคำนวณอย่างไร?',
      titleEn: 'How is the delivery fee calculated?',
      bodyTh:
          'ค่าส่งและราคาบวกเพิ่มถูกกำหนดโดยแอดมินระบบ\nแอปจะคำนวณตามระยะทาง/น้ำหนักและอัตราที่แอดมินตั้งไว้\nหากสั่งหลายร้านในรัศมีตลาด (ตามที่แอดมินกำหนด) อาจมีค่ารวบรวมสินค้าและค่าบริการเพิ่ม — ดูในตะกร้าก่อนยืนยัน',
      bodyEn:
          'Delivery fees and markups are set by platform admin.\nMulti-shop orders near the market hub may include collection and service fees configured by admin — shown in cart before checkout.',
      popular: true,
    ),
    HelpArticle(
      id: 'rider_tracking',
      categoryKey: 'delivery_rider',
      titleTh: 'ติดตามไรเดอร์ได้ไหม?',
      titleEn: 'Can I track the rider?',
      bodyTh:
          'เมื่อไรเดอร์รับงานแล้ว สถานะและความคืบหน้าจะอัปเดตในแท็บเส้นทาง\nหากล่าช้า ติดต่อแอดมินพร้อมรหัสออเดอร์',
      bodyEn:
          'After a rider accepts, progress updates appear in Roadmap.\nIf delayed, contact admin with your order ID.',
    ),
    HelpArticle(
      id: 'nationwide_shipping',
      categoryKey: 'delivery_rider',
      titleTh: 'ส่งทั่วประเทศทำอย่างไร?',
      titleEn: 'How does nationwide shipping work?',
      bodyTh:
          'เลือกหมวดส่งทั่วประเทศ กรอกที่อยู่ผู้รับ\nค่าส่งประมาณการคำนวณจากน้ำหนักและอัตราที่แอดมินกำหนด',
      bodyEn:
          'Choose nationwide shipping, enter recipient address.\nEstimated fee uses weight and admin-configured rates.',
    ),
    HelpArticle(
      id: 'product_quality',
      categoryKey: 'product_shop',
      titleTh: 'สินค้าไม่ตรงปกหรือมีปัญหา',
      titleEn: 'Product not as described?',
      bodyTh:
          'ถ่ายรูปสินค้าและแจ้งแอดมินภายใน 24 ชม.\nเลือกหัวข้อ "คุณภาพสินค้า / ร้านค้า" พร้อมรหัสออเดอร์',
      bodyEn:
          'Take photos and contact admin within 24 hours.\nChoose Product / shop quality with your order ID.',
    ),
    HelpArticle(
      id: 'login_google',
      categoryKey: 'account_login',
      titleTh: 'เข้าสู่ระบบด้วย Google',
      titleEn: 'Sign in with Google',
      bodyTh:
          'ใช้บัญชี Google ที่ผูกกับอีเมลของคุณ\nหากเข้าไม่ได้ ลองออกจากระบบแล้วเข้าใหม่ หรือติดต่อแอดมิน',
      bodyEn:
          'Use the Google account linked to your email.\nIf sign-in fails, sign out and retry or contact admin.',
    ),
    HelpArticle(
      id: 'location_permission',
      categoryKey: 'app_bug',
      titleTh: 'แอปขอตำแหน่งทำไม?',
      titleEn: 'Why does the app need location?',
      bodyTh:
          'ใช้คำนวณค่าส่ง แสดงร้านใกล้คุณ และติดตามการจัดส่ง\nเปิดสิทธิ์ได้ที่ ตั้งค่า → ความเป็นส่วนตัว → จัดการสิทธิ์แอป',
      bodyEn:
          'Location is used for delivery fees, nearby shops, and tracking.\nEnable it in Settings → Privacy → App permissions.',
      popular: true,
    ),
    HelpArticle(
      id: 'notifications',
      categoryKey: 'app_bug',
      titleTh: 'ไม่ได้รับแจ้งเตือน',
      titleEn: 'Not receiving notifications?',
      bodyTh:
          'ตรวจสอบการอนุญาตแจ้งเตือนในระบบ\nและเปิดการแจ้งเตือนของแอป VANTALAD',
      bodyEn:
          'Check notification permission in system settings\nand ensure VANTALAD notifications are enabled.',
    ),
  ];

  static List<HelpArticle> forCategory(String categoryKey) {
    return articles
        .where((article) => article.categoryKey == categoryKey)
        .toList(growable: false);
  }

  static String resolveBody(
    HelpArticle article,
    bool english, {
    GlobalPricingConfig? pricing,
  }) {
    final config = pricing ?? PricingConfigService.instance.current;
    if (HelpPricingSummary.isDynamicArticle(article.id)) {
      return HelpPricingSummary.bodyForArticle(article, config, english);
    }
    return article.body(english);
  }

  static List<HelpArticle> search(
    String query,
    bool english, {
    GlobalPricingConfig? pricing,
  }) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return articles;
    }
    return articles
        .where((article) {
          final title = article.title(english).toLowerCase();
          final body = resolveBody(article, english, pricing: pricing).toLowerCase();
          return title.contains(normalized) || body.contains(normalized);
        })
        .toList(growable: false);
  }

  static List<HelpArticle> popularArticles() {
    return articles.where((article) => article.popular).toList(growable: false);
  }
}
