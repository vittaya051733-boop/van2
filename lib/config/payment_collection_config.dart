import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentChannelType {
  promptPayPhone,
  promptPayNationalId,
  merchantQrPayload,
  bankTransfer,
}

class PaymentCollectionSettings {
  const PaymentCollectionSettings({
    required this.recipientDisplayName,
    required this.bankName,
    required this.bankAccountNumber,
    required this.promptPayPhoneNumber,
    required this.promptPayNationalIdOrTaxId,
    required this.merchantQrPayload,
    required this.slipProviderLabel,
  });

  final String recipientDisplayName;
  final String bankName;
  final String bankAccountNumber;
  final String? promptPayPhoneNumber;
  final String? promptPayNationalIdOrTaxId;
  final String? merchantQrPayload;
  final String slipProviderLabel;

  static const PaymentCollectionSettings defaults = PaymentCollectionSettings(
    recipientDisplayName: '',
    bankName: '',
    bankAccountNumber: '',
    promptPayPhoneNumber: null,
    promptPayNationalIdOrTaxId: null,
    merchantQrPayload: null,
    slipProviderLabel: 'Slip OK',
  );

  bool get isConfigured =>
      recipientDisplayName.trim().isNotEmpty &&
      bankAccountNumber.trim().isNotEmpty;

  factory PaymentCollectionSettings.fromFirestore(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    return normalizePromptPayFields(
      PaymentCollectionSettings(
        recipientDisplayName: _readString(
          source['recipientDisplayName'],
          defaults.recipientDisplayName,
        ),
        bankName: _readString(source['bankName'], defaults.bankName),
        bankAccountNumber: _readString(
          source['bankAccountNumber'],
          defaults.bankAccountNumber,
        ),
        promptPayPhoneNumber: _readOptionalString(source['promptPayPhoneNumber']),
        promptPayNationalIdOrTaxId: _readOptionalString(
          source['promptPayNationalIdOrTaxId'],
        ),
        merchantQrPayload: _readOptionalString(source['merchantQrPayload']),
        slipProviderLabel: _readString(
          source['slipProviderLabel'],
          defaults.slipProviderLabel,
        ),
      ),
    );
  }

  /// Aligns with [normalizePaymentCollectionSettings] in Cloud Functions.
  /// Moves 9–10 digit values stored in the national-id field to phone.
  static PaymentCollectionSettings normalizePromptPayFields(
    PaymentCollectionSettings source,
  ) {
    final phoneDigits = _normalizedPhoneDigits(source.promptPayPhoneNumber);
    var nationalIdDigits = _normalizedNationalIdDigits(
      source.promptPayNationalIdOrTaxId,
    );

    var resolvedPhone = phoneDigits;
    if (resolvedPhone == null &&
        nationalIdDigits == null &&
        source.promptPayNationalIdOrTaxId != null) {
      final rawNationalDigits = _digitsOnly(source.promptPayNationalIdOrTaxId!);
      if (_isPromptPayPhoneDigits(rawNationalDigits)) {
        resolvedPhone = rawNationalDigits;
      }
    }

    return PaymentCollectionSettings(
      recipientDisplayName: source.recipientDisplayName,
      bankName: source.bankName,
      bankAccountNumber: source.bankAccountNumber,
      promptPayPhoneNumber: resolvedPhone,
      promptPayNationalIdOrTaxId: nationalIdDigits,
      merchantQrPayload: source.merchantQrPayload,
      slipProviderLabel: source.slipProviderLabel,
    );
  }

  static String _digitsOnly(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }

  static bool _isPromptPayPhoneDigits(String digits) {
    return digits.length >= 9 && digits.length <= 10;
  }

  static String? _normalizedPhoneDigits(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final digits = _digitsOnly(value);
    return _isPromptPayPhoneDigits(digits) ? digits : null;
  }

  static String? _normalizedNationalIdDigits(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final digits = _digitsOnly(value);
    return digits.length == 13 ? digits : null;
  }

  static String _readString(Object? value, String fallback) {
    final normalized = _readOptionalString(value);
    return normalized ?? fallback;
  }

  static String? _readOptionalString(Object? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }
}

class PaymentCollectionConfigService {
  PaymentCollectionConfigService._();

  static final PaymentCollectionConfigService instance = PaymentCollectionConfigService._();

  static const String collectionPath = 'payment_config';
  static const String documentId = 'collection';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _documentRef =>
      _firestore.collection(collectionPath).doc(documentId);

  Future<PaymentCollectionSettings> loadOnce() async {
    try {
      final snapshot = await _documentRef.get().timeout(const Duration(seconds: 5));
      return PaymentCollectionSettings.fromFirestore(snapshot.data());
    } catch (_) {
      return PaymentCollectionSettings.defaults;
    }
  }

  Stream<PaymentCollectionSettings> watch() {
    return _watchWithResubscribe();
  }

  Stream<PaymentCollectionSettings> _watchWithResubscribe() async* {
    while (true) {
      try {
        await for (final snapshot in _documentRef.snapshots()) {
          yield PaymentCollectionSettings.fromFirestore(snapshot.data());
        }
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }
}

class PaymentChannelDefinition {
  const PaymentChannelDefinition({
    required this.type,
    required this.title,
    required this.description,
    required this.isConfigured,
    this.qrPayload,
    this.destinationLabel,
  });

  final PaymentChannelType type;
  final String title;
  final String description;
  final bool isConfigured;
  final String? qrPayload;
  final String? destinationLabel;
}