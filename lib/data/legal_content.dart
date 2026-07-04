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
    updatedAtLabel: '1 มิ.ย. 2026',
    bodyTh: '''แอป VANTALAD (van2) ให้บริการสั่งซื้อสินค้าและบริการจัดส่ง

ผู้ควบคุมข้อมูล
• ผู้ให้บริการแพลตฟอร์ม VANTALAD (Van Market)

ข้อมูลที่เราเก็บ
• บัญชีผู้ใช้ (อีเมล, เบอร์โทร, ชื่อ, รูปโปรไฟล์จาก Google)
• ตำแหน่ง GPS เพื่อคำนวณค่าส่ง ค้นหาร้านใกล้เคียง และติดตามการจัดส่ง
• ประวัติออเดอร์ ตะกร้า การชำระเงิน (รวมรูปสลิป) และบัญชีรับคืนเงิน
• ข้อความแชท/โทรกับไรเดอร์ แอดมิน และรูปแนบ
• โทเคนแจ้งเตือน (FCM) เมื่อคุณ opt-in
• การตั้งค่าแอป (เช่น ภาษา)

ฐานทางกฎหมาย (PDPA)
• สัญญา — ให้บริการสั่งซื้อ จัดส่ง ชำระเงิน
• ความยินยอม — การตลาด/โปรโมชัน และการแจ้งเตือน (ถ้าเลือกเปิด)
• ประโยชน์โดยชอบด้วยกฎหมาย — ความปลอดภัย ป้องกันทุจริต

ผู้ประมวลผลภายนอก
• Google Firebase (Auth, Firestore, Storage, Functions, FCM)
• SlipOK — ตรวจสอบสลิปชำระเงิน
• Agora — โทร/วิดีโอคอลผ่านแอป
• ผู้ให้บริการแผนที่/พิกัด (ตามที่ระบบเรียกใช้)

การโอนข้อมูลต่างประเทศ
• ข้อมูลอาจถูกประมวลผลบนเซิร์ฟเวอร์ของ Google/Firebase ในต่างประเทศ ตามมาตรฐานความปลอดภัยของผู้ให้บริการ

การเก็บรักษา
• บัญชีและออเดอร์: ตามระยะเวลาที่จำเป็นต่อบริการ ภาษี และข้อพิพาท
• สลิป/หลักฐานชำระเงิน: ตามนโยบายตรวจสอบการเงิน
• บันทึกความยินยอม: เก็บเพื่อพิสูจน์การยอมรับนโยบาย

สิทธิของคุณ (PDPA)
• เข้าถึง ส่งออก แก้ไข ลบ คัดค้าน หรือถอนความยินยอม
• ใช้เมนู ตั้งค่า → ความเป็นส่วนตัวและความปลอดภัย

ติดต่อ
• ตั้งค่า → ความเป็นส่วนตัว → ขอใช้สิทธิข้อมูล หรือ ติดต่อแอดมิน''',
    bodyEn: '''VANTALAD (van2) provides ordering and delivery services.

Data controller
• VANTALAD platform operator (Van Market)

Data we collect
• Account (email, phone, name, Google profile photo)
• GPS for delivery fees, nearby shops, and order tracking
• Orders, cart, payment proofs, refund account details
• Chat/calls with riders and admin, attachments
• FCM token when you opt in
• App preferences (e.g. language)

Legal bases (PDPA)
• Contract — ordering, delivery, payments
• Consent — marketing and push notifications (if enabled)
• Legitimate interest — security and fraud prevention

Processors
• Google Firebase (Auth, Firestore, Storage, Functions, FCM)
• SlipOK — payment slip verification
• Agora — in-app voice/video calls
• Map/location providers as used by the app

Cross-border transfer
• Data may be processed on Google/Firebase servers abroad under their security standards.

Retention
• Accounts and orders: as needed for service, tax, and disputes
• Payment proofs: per financial review policy
• Consent records: kept to prove policy acceptance

Your rights (PDPA)
• Access, export, correct, delete, object, or withdraw consent
• Settings → Privacy & security

Contact
• Settings → Privacy → exercise your rights or Contact admin''',
  );

  static const termsOfService = LegalDocument(
    titleTh: 'ข้อกำหนดการใช้งาน',
    titleEn: 'Terms of Service',
    updatedAtLabel: '1 มิ.ย. 2026',
    bodyTh: '''การใช้แอป VANTALAD ถือว่าคุณยอมรับข้อกำหนดนี้และนโยบายความเป็นส่วนตัว

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
    bodyEn: '''By using VANTALAD you agree to these terms and the Privacy Policy.

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
    updatedAtLabel: '1 มิ.ย. 2026',
    bodyTh: '''สรุปข้อมูลหลัก
• ข้อมูลบัญชีและการยืนยันตัวตน
• ตำแหน่งที่อยู่และที่อยู่จัดส่ง
• รายการสั่งซื้อและหลักฐานการชำระเงิน
• การสนทนากับไรเดอร์/แอดมิน และการโทรผ่านแอป
• การตั้งค่าแอปและความยินยอม (push/การตลาด)

ดูรายละเอียดเพิ่มในนโยบายความเป็นส่วนตัว''',
    bodyEn: '''Summary
• Account and authentication data
• Location and delivery addresses
• Orders and payment proofs
• Rider/admin conversations and in-app calls
• App preferences and consents (push/marketing)

See Privacy Policy for full details.''',
  );
}
