/// สลับช่องทางชำระเงิน van2 (client-side)
///
/// - [omiseGatewayEnabled] — PromptPay/บัตร/Mobile Banking/TrueMoney ผ่าน Omise
/// - [embeddedPromptPayScanEnabled] — สแกน QR พร้อมเพย์ + ส่งสลิป (แบบ van3 / nationwide)
///
/// เมื่อสมัคร Omise ผ่านแล้ว: ตั้ง `omiseGatewayEnabled = true` และปิด embedded ได้ตามต้องการ
class PaymentGatewayConfig {
  PaymentGatewayConfig._();

  static const bool omiseGatewayEnabled = false;

  static const bool embeddedPromptPayScanEnabled = true;
}
