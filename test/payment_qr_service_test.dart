import 'package:flutter_test/flutter_test.dart';
import 'package:van2/config/payment_collection_config.dart';
import 'package:van2/services/payment_qr_service.dart';

void main() {
  test('builds PromptPay payload from phone number with amount', () {
    final payload = PromptPayQrPayload.fromPhoneNumber(
      phoneNumber: '081-234-5678',
      amount: 159.0,
    );

    expect(payload, startsWith('00020101021229'));
    expect(payload, contains('0066812345678'));
    expect(payload, contains('5406159.00'));
    expect(payload.length, greaterThan(40));
  });

  test('builds PromptPay payload from national id with amount', () {
    final payload = PromptPayQrPayload.fromNationalIdOrTaxId(
      nationalIdOrTaxId: '1234567890123',
      amount: 89.5,
    );

    expect(payload, startsWith('00020101021229'));
    expect(payload, contains('02131234567890123'));
    expect(payload, contains('540589.50'));
  });

  test('falls back to default QR settings when remote config is malformed', () {
    const malformed = PaymentCollectionSettings(
      recipientDisplayName: 'ร้านทดสอบ',
      bankName: 'ธนาคารทดสอบ',
      bankAccountNumber: '1234567890',
      promptPayPhoneNumber: 'abc',
      promptPayNationalIdOrTaxId: '1234',
      merchantQrPayload: '   ',
      slipProviderLabel: 'Slip OK',
    );

    final resolved = PaymentQrService.resolveSettingsForQr(malformed);
    final channel = PaymentQrService.pickDefaultChannel(
      amount: 159.0,
      config: malformed,
    );

    expect(
      resolved.promptPayNationalIdOrTaxId,
      PaymentCollectionSettings.defaults.promptPayNationalIdOrTaxId,
    );
    expect(channel.qrPayload, isNotNull);
    expect(channel.type, PaymentChannelType.promptPayNationalId);
  });
}