import '../config/payment_collection_config.dart';

class PromptPayQrPayload {
  PromptPayQrPayload._();

  static String fromPhoneNumber({
    required String phoneNumber,
    required double amount,
  }) {
    final normalizedDigits = _digitsOnly(phoneNumber);
    if (normalizedDigits.length < 9 || normalizedDigits.length > 10) {
      throw ArgumentError('PromptPay phone number must have 9-10 digits.');
    }

    final local = normalizedDigits.startsWith('0')
        ? normalizedDigits.substring(1)
        : normalizedDigits;
    final proxyValue = '0066$local';
    return _buildPayload(proxyType: '01', proxyValue: proxyValue, amount: amount);
  }

  static String fromNationalIdOrTaxId({
    required String nationalIdOrTaxId,
    required double amount,
  }) {
    final digits = _digitsOnly(nationalIdOrTaxId);
    if (digits.length != 13) {
      throw ArgumentError('PromptPay national ID or tax ID must have 13 digits.');
    }

    return _buildPayload(proxyType: '02', proxyValue: digits, amount: amount);
  }

  static String? build({
    required String promptPayId,
    required double amount,
  }) {
    final digits = _digitsOnly(promptPayId);
    if (digits.length == 13) {
      return fromNationalIdOrTaxId(nationalIdOrTaxId: digits, amount: amount);
    }
    if (digits.length >= 9 && digits.length <= 10) {
      return fromPhoneNumber(phoneNumber: digits, amount: amount);
    }
    return null;
  }

  static String maskedLastFour(String promptPayId) {
    final digits = _digitsOnly(promptPayId);
    if (digits.length >= 4) {
      return digits.substring(digits.length - 4);
    }
    return '';
  }

  static String maskedDisplayLabel(String promptPayId) {
    final suffix = maskedLastFour(promptPayId);
    if (suffix.isEmpty) {
      return 'PromptPay';
    }
    return 'PromptPay ••••$suffix';
  }

  static String _buildPayload({
    required String proxyType,
    required String proxyValue,
    required double amount,
  }) {
    final normalizedAmount = amount <= 0 ? '' : amount.toStringAsFixed(2);
    final merchantAccountInfo = _field(
      '29',
      _field('00', 'A000000677010111') + _field(proxyType, proxyValue),
    );

    final payloadWithoutCrc = <String>[
      _field('00', '01'),
      _field('01', normalizedAmount.isEmpty ? '11' : '12'),
      merchantAccountInfo,
      _field('52', '0000'),
      _field('53', '764'),
      if (normalizedAmount.isNotEmpty) _field('54', normalizedAmount),
      _field('58', 'TH'),
      _field('59', 'VAN MARKET'),
      _field('60', 'BANGKOK'),
      '6304',
    ].join();

    final crc = _crc16CcittFalse(payloadWithoutCrc);
    return '$payloadWithoutCrc$crc';
  }

  static String _field(String id, String value) {
    final length = value.length.toString().padLeft(2, '0');
    return '$id$length$value';
  }

  static String _digitsOnly(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }

  static String _crc16CcittFalse(String value) {
    var crc = 0xFFFF;
    for (final codeUnit in value.codeUnits) {
      crc ^= codeUnit << 8;
      for (var bit = 0; bit < 8; bit += 1) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}

class PaymentQrService {
  PaymentQrService._();

  static PaymentCollectionSettings resolveSettingsForQr(
    PaymentCollectionSettings config,
  ) {
    final merchantQrPayload = _normalizedMerchantPayload(config.merchantQrPayload);
    final promptPayPhoneNumber = _normalizedPhoneNumber(config.promptPayPhoneNumber);
    final promptPayNationalIdOrTaxId = _normalizedNationalId(
      config.promptPayNationalIdOrTaxId,
    );

    final hasValidConfiguredQr =
        merchantQrPayload != null ||
        promptPayPhoneNumber != null ||
        promptPayNationalIdOrTaxId != null;

    return PaymentCollectionSettings(
      recipientDisplayName: config.recipientDisplayName,
      bankName: config.bankName,
      bankAccountNumber: config.bankAccountNumber,
      promptPayPhoneNumber: hasValidConfiguredQr
          ? promptPayPhoneNumber
          : _normalizedPhoneNumber(
              PaymentCollectionSettings.defaults.promptPayPhoneNumber,
            ),
      promptPayNationalIdOrTaxId: hasValidConfiguredQr
          ? promptPayNationalIdOrTaxId
          : _normalizedNationalId(
              PaymentCollectionSettings.defaults.promptPayNationalIdOrTaxId,
            ),
      merchantQrPayload: hasValidConfiguredQr
          ? merchantQrPayload
          : _normalizedMerchantPayload(
              PaymentCollectionSettings.defaults.merchantQrPayload,
            ),
      slipProviderLabel: config.slipProviderLabel,
    );
  }

  static List<PaymentChannelDefinition> buildChannels({
    required double amount,
    required PaymentCollectionSettings config,
  }) {
    final channels = <PaymentChannelDefinition>[
      PaymentChannelDefinition(
        type: PaymentChannelType.promptPayPhone,
        title: '1. PromptPay ผ่านเบอร์โทร',
        description: 'สร้าง QR ตามยอดจากเบอร์ที่ผูก PromptPay',
        isConfigured: _hasText(config.promptPayPhoneNumber),
        qrPayload: _hasText(config.promptPayPhoneNumber)
            ? PromptPayQrPayload.fromPhoneNumber(
                phoneNumber: config.promptPayPhoneNumber!,
                amount: amount,
              )
            : null,
        destinationLabel: _hasText(config.promptPayPhoneNumber)
            ? 'PromptPay: ${config.promptPayPhoneNumber}'
            : null,
      ),
      PaymentChannelDefinition(
        type: PaymentChannelType.promptPayNationalId,
        title: '2. PromptPay ผ่านเลขบัตร/นิติบุคคล',
        description: 'สร้าง QR ตามยอดจากเลขบัตรประชาชนหรือเลขผู้เสียภาษี',
        isConfigured: _hasText(config.promptPayNationalIdOrTaxId),
        qrPayload: _hasText(config.promptPayNationalIdOrTaxId)
            ? PromptPayQrPayload.fromNationalIdOrTaxId(
                nationalIdOrTaxId: config.promptPayNationalIdOrTaxId!,
                amount: amount,
              )
            : null,
        destinationLabel: _hasText(config.promptPayNationalIdOrTaxId)
            ? 'PromptPay ID: ${config.promptPayNationalIdOrTaxId}'
            : null,
      ),
      PaymentChannelDefinition(
        type: PaymentChannelType.merchantQrPayload,
        title: '3. Merchant QR Payload',
        description: 'ใช้ payload จากธนาคารหรือ provider โดยตรง',
        isConfigured: _hasText(config.merchantQrPayload),
        qrPayload: _hasText(config.merchantQrPayload)
            ? config.merchantQrPayload!.trim()
            : null,
        destinationLabel: _hasText(config.merchantQrPayload)
            ? 'ใช้ merchant payload ที่ตั้งค่าไว้'
            : null,
      ),
      PaymentChannelDefinition(
        type: PaymentChannelType.bankTransfer,
        title: '4. โอนเข้าบัญชีแล้วแนบสลิป',
        description: 'ใช้เลขบัญชีธนาคารโดยตรง และส่งสลิปให้ระบบตรวจภายหลัง',
        isConfigured: true,
        destinationLabel: '${config.bankName} ${config.bankAccountNumber}',
      ),
    ];

    return channels;
  }

  static PaymentChannelDefinition pickDefaultChannel({
    required double amount,
    required PaymentCollectionSettings config,
  }) {
    final channels = buildChannels(
      amount: amount,
      config: resolveSettingsForQr(config),
    );
    for (final channel in channels) {
      if (channel.isConfigured && channel.qrPayload != null) {
        return channel;
      }
    }
    return channels.last;
  }

  static bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  static String? _normalizedMerchantPayload(String? value) {
    if (!_hasText(value)) {
      return null;
    }
    return value!.trim();
  }

  static String? _normalizedPhoneNumber(String? value) {
    if (!_hasText(value)) {
      return null;
    }
    final digits = value!.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9 || digits.length > 10) {
      return null;
    }
    return digits;
  }

  static String? _normalizedNationalId(String? value) {
    if (!_hasText(value)) {
      return null;
    }
    final digits = value!.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 13) {
      return null;
    }
    return digits;
  }
}