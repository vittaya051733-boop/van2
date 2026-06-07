class AdminSupportTopic {
  const AdminSupportTopic({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;

  static const String customKey = 'custom';
}

class AdminSupportConfig {
  const AdminSupportConfig({
    required this.sourceApp,
    required this.sourceLabel,
    required this.topics,
  });

  final String sourceApp;
  final String sourceLabel;
  final List<AdminSupportTopic> topics;
}

/// UID แอดมินสำหรับโทรในแอป (fallback ถ้า ticket ยังไม่มี assignedAdminUid)
const String kAdminSupportCalleeUid = '';

const AdminSupportConfig kVan2AdminSupportConfig = AdminSupportConfig(
  sourceApp: 'van2',
  sourceLabel: 'ลูกค้า',
  topics: <AdminSupportTopic>[
    AdminSupportTopic(
      key: 'order_issue',
      label: 'ปัญหาการสั่งซื้อ / สถานะออเดอร์',
    ),
    AdminSupportTopic(
      key: 'payment_refund',
      label: 'การชำระเงิน / ขอคืนเงิน',
    ),
    AdminSupportTopic(
      key: 'delivery_rider',
      label: 'ปัญหาการจัดส่ง / ไรเดอร์',
    ),
    AdminSupportTopic(
      key: 'product_shop',
      label: 'คุณภาพสินค้า / ร้านค้า',
    ),
    AdminSupportTopic(
      key: 'account_login',
      label: 'บัญชี / เข้าสู่ระบบ',
    ),
    AdminSupportTopic(
      key: 'app_bug',
      label: 'แจ้งข้อผิดพลาดแอป',
    ),
    AdminSupportTopic(
      key: AdminSupportTopic.customKey,
      label: 'อื่นๆ (พิมพ์หัวข้อเอง)',
    ),
  ],
);
