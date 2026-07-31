class SavedPaymentCard {
  const SavedPaymentCard({
    required this.omiseCardId,
    required this.brand,
    required this.lastDigits,
    required this.expMonth,
    required this.expYear,
    this.name,
  });

  final String omiseCardId;
  final String brand;
  final String lastDigits;
  final int expMonth;
  final int expYear;
  final String? name;

  factory SavedPaymentCard.fromMap(Map<String, dynamic> map) {
    return SavedPaymentCard(
      omiseCardId: map['omiseCardId']?.toString() ?? '',
      brand: map['brand']?.toString().toLowerCase() ?? '',
      lastDigits: map['lastDigits']?.toString() ?? '',
      expMonth: (map['expMonth'] as num?)?.toInt() ?? 0,
      expYear: (map['expYear'] as num?)?.toInt() ?? 0,
      name: map['name']?.toString(),
    );
  }

  String get brandLabel {
    switch (brand) {
      case 'visa':
        return 'Visa';
      case 'mastercard':
      case 'master':
        return 'Mastercard';
      case 'jcb':
        return 'JCB';
      default:
        return 'บัตร';
    }
  }

  String get maskedNumber => '**** **** **** ${lastDigits.padLeft(4, '•')}';

  String get expiryLabel {
    final month = expMonth.toString().padLeft(2, '0');
    final year = expYear >= 100 ? expYear % 100 : expYear;
    return '$month/${year.toString().padLeft(2, '0')}';
  }
}
