class LegalDocument {
  const LegalDocument({
    required this.titleTh,
    required this.titleEn,
    required this.bodyTh,
    required this.bodyEn,
    required this.updatedAtLabel,
  });

  final String titleTh;
  final String titleEn;
  final String bodyTh;
  final String bodyEn;
  final String updatedAtLabel;

  String title(bool english) => english ? titleEn : titleTh;
  String body(bool english) => english ? bodyEn : bodyTh;
}

class LegalContent {
  LegalContent._();

  static const privacyPolicy = LegalDocument(
    titleTh: 'นโยบายความเป็นส่วนตัว',
    titleEn: 'Privacy Policy',
    updatedAtLabel: '31 พ.ค. 2026',
    bodyTh: '''แอป VANTALAD (van2) ให้บริการสั่งซื้อสินค้าและบริการจัดส่ง

ข้อมูลที่เราเก็บ
• บัญชีผู้ใช้ (อีเมล, ชื่อ, รูปโปรไฟล์จาก Google)
• ตำแหน่ง GPS เพื่อคำนวณค่าส่งและติดตามการจัดส่ง
• ประวัติออเดอร์ ตะกร้า และการชำระเงิน (รวมรูปสลิป)
• ข้อความติดต่อแอดมินและรูปแนบ
• โทเคนแจ้งเตือน (FCM) เพื่อส่งสถานะออเดอร์

การใช้ข้อมูล
• ให้บริการสั่งซื้อ จัดส่ง และซัพพอร์ตลูกค้า
• ปรับปรุงความปลอดภัยและประสบการณ์ใช้งาน
• ไม่ขายข้อมูลส่วนบุคคลให้บุคคลที่สาม

การเก็บรักษา
• เก็บตามระยะเวลาที่จำเป็นต่อบริการและข้อกำหนดทางกฎหมาย

สิทธิของคุณ (PDPA)
• ขอเข้าถึง แก้ไข หรือลบข้อมูล — ติดต่อแอดมินผ่านแอป

ติดต่อ
• ใช้เมนู ตั้งค่า → ติดต่อแอดมิน''',
    bodyEn: '''VANTALAD (van2) provides ordering and delivery services.

Data we collect
• Account info (email, name, Google profile photo)
• GPS location for delivery fees and tracking
• Order history, cart, and payment proof images
• Admin support messages and attachments
• Push notification token (FCM)

How we use data
• To fulfill orders, delivery, and customer support
• To improve security and user experience
• We do not sell personal data to third parties

Retention
• Kept as long as needed for service and legal requirements

Your rights (PDPA)
• Request access, correction, or deletion via Contact admin

Contact
• Settings → Contact admin''',
  );

  static const termsOfService = LegalDocument(
    titleTh: 'ข้อกำหนดการใช้งาน',
    titleEn: 'Terms of Service',
    updatedAtLabel: '31 พ.ค. 2026',
    bodyTh: '''การใช้แอป VANTALAD ถือว่าคุณยอมรับข้อกำหนดนี้

บัญชีผู้ใช้
• คุณต้องให้ข้อมูลที่ถูกต้องและรักษาความปลอดภัยบัญชี

การสั่งซื้อ
• ราคา ค่าส่ง และอัตราบวกเพิ่มอาจถูกปรับโดยแอดมินระบบ
• ยอดที่แสดงในตะกร้าก่อนยืนยันถือเป็นยอดที่ตกลง

การชำระเงินและคืนเงิน
• เป็นไปตามนโยบายร้านและการพิจารณาของแอดมิน
• ขอคืนเงินผ่านช่องทางซัพพอร์ตพร้อมหลักฐาน

พฤติกรรมต้องห้าม
• ใช้แอปในทางที่ผิดกฎหมาย ฉ้อโกง หรือรบกวนผู้อื่น

การระงับบริการ
• แพลตฟอร์มอาจระงับบัญชีที่ละเมิดข้อกำหนด''',
    bodyEn: '''By using VANTALAD you agree to these terms.

Account
• Provide accurate information and keep your account secure

Orders
• Prices, delivery fees, and markups may be set by platform admin
• Totals shown in cart before checkout are binding

Payments & refunds
• Subject to shop policies and admin review
• Request refunds via support with evidence

Prohibited conduct
• Illegal use, fraud, or harassment

Suspension
• Accounts violating terms may be suspended''',
  );

  static const dataSummary = LegalDocument(
    titleTh: 'ข้อมูลที่เราเก็บ',
    titleEn: 'Data we collect',
    updatedAtLabel: '31 พ.ค. 2026',
    bodyTh: '''สรุปข้อมูลหลัก
• ข้อมูลบัญชีและการยืนยันตัวตน
• ตำแหน่งที่อยู่และที่อยู่จัดส่ง
• รายการสั่งซื้อและหลักฐานการชำระเงิน
• การสนทนากับแอดมิน
• การตั้งค่าแอป (เช่น ภาษา)

ดูรายละเอียดเพิ่มในนโยบายความเป็นส่วนตัว''',
    bodyEn: '''Summary
• Account and authentication data
• Location and delivery addresses
• Orders and payment proofs
• Admin support conversations
• App preferences (e.g. language)

See Privacy Policy for full details.''',
  );
}
