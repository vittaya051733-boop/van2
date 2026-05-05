class TaxPricingPolicy {
  TaxPricingPolicy._();

  // 7% fuse defaults are used when Firestore config is missing/invalid.
  static const double defaultTaxableMarkupRate = 0.07;
  static const double defaultNonTaxableMarkupRate = 0.07;
  static const double defaultToppingMarkupRate = 0.07;

  static double _taxableMarkupRate = defaultTaxableMarkupRate;
  static double _nonTaxableMarkupRate = defaultNonTaxableMarkupRate;
  static double _toppingMarkupRate = defaultToppingMarkupRate;

  static double get taxableMarkupRate => _taxableMarkupRate;
  static double get nonTaxableMarkupRate => _nonTaxableMarkupRate;
  static double get toppingMarkupRate => _toppingMarkupRate;

  static void configureRates({
    required double taxableMarkupRate,
    required double nonTaxableMarkupRate,
    required double toppingMarkupRate,
  }) {
    _taxableMarkupRate = _sanitizeRate(
      taxableMarkupRate,
      defaultTaxableMarkupRate,
    );
    _nonTaxableMarkupRate = _sanitizeRate(
      nonTaxableMarkupRate,
      defaultNonTaxableMarkupRate,
    );
    _toppingMarkupRate = _sanitizeRate(
      toppingMarkupRate,
      defaultToppingMarkupRate,
    );
  }

  static double _sanitizeRate(double value, double fallback) {
    if (value.isNaN || value.isInfinite || value < 0 || value > 5) {
      return fallback;
    }
    return value;
  }

  static bool isTaxableProduct(Map<String, dynamic> data) {
    const boolKeys = <String>[
      'isTaxable',
      'taxable',
      'hasTax',
      'includeTax',
      'vatEnabled',
      'isVat',
      'isTaxIncluded',
    ];

    for (final key in boolKeys) {
      final value = data[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        final text = value.trim().toLowerCase();
        if (<String>['true', 'yes', '1', 'tax', 'vat', 'taxable', 'เสียภาษี'].contains(text)) {
          return true;
        }
        if (<String>['false', 'no', '0', 'notax', 'no_tax', 'ไม่เสียภาษี'].contains(text)) {
          return false;
        }
      }
    }

    const statusKeys = <String>['taxStatus', 'taxType', 'vatType'];
    for (final key in statusKeys) {
      final text = (data[key] ?? '').toString().trim().toLowerCase();
      if (text.contains('เสีย') || text.contains('tax') || text.contains('vat')) {
        return true;
      }
      if (text.contains('ไม่เสีย') || text.contains('no tax') || text.contains('notax')) {
        return false;
      }
    }

    return false;
  }

  static num parseNumber(Object? value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  static num applyProductMarkup(num amount, bool taxable) {
    final rate = taxable ? taxableMarkupRate : nonTaxableMarkupRate;
    return applyMarkup(amount, rate);
  }

  static num applyToppingMarkup(num amount) {
    return applyMarkup(amount, toppingMarkupRate);
  }

  static num applyMarkup(num amount, num rate) {
    if (amount <= 0) {
      return 0;
    }
    return roundForPayment(amount * (1 + rate));
  }

  static int roundForPayment(num value) {
    if (value <= 0) {
      return 0;
    }

    final floorValue = value.floor();
    final fraction = value - floorValue;
    if (fraction > 0.5) {
      return floorValue + 1;
    }

    return floorValue;
  }

  static String formatPrice(num value) {
    return value.toStringAsFixed(0);
  }
}
