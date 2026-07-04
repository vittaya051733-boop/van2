class ShippingPricingPolicy {
  ShippingPricingPolicy._();

  static const double defaultBaseFee = 25;
  static const double defaultPerKmFee = 12.5;
  static const double defaultMinBillableKm = 1;
  static const double defaultMaxBillableKm = 50;
  static const double defaultMissingCoordsFee = 25;

  static const double defaultNationwideBaseFee = 45;
  static const double defaultNationwidePerKgFee = 18;
  static const double defaultNationwideRemoteSurcharge = 30;

  static double _shippingBaseFee = defaultBaseFee;
  static double _shippingPerKmFee = defaultPerKmFee;
  static double _shippingMinBillableKm = defaultMinBillableKm;
  static const double _shippingMaxBillableKm = defaultMaxBillableKm;
  static double _shippingMissingCoordsFee = defaultMissingCoordsFee;

  static double _travelBaseFee = defaultBaseFee;
  static double _travelPerKmFee = defaultPerKmFee;
  static double _travelMinBillableKm = defaultMinBillableKm;

  static double _nationwideBaseFee = defaultNationwideBaseFee;
  static double _nationwidePerKgFee = defaultNationwidePerKgFee;
  static double _nationwideRemoteSurcharge = defaultNationwideRemoteSurcharge;

  static double get shippingBaseFee => _shippingBaseFee;
  static double get shippingPerKmFee => _shippingPerKmFee;
  static double get shippingMinBillableKm => _shippingMinBillableKm;
  static double get shippingMissingCoordsFee => _shippingMissingCoordsFee;

  static double get travelBaseFee => _travelBaseFee;
  static double get travelPerKmFee => _travelPerKmFee;
  static double get travelMinBillableKm => _travelMinBillableKm;

  static double get nationwideBaseFee => _nationwideBaseFee;
  static double get nationwidePerKgFee => _nationwidePerKgFee;
  static double get nationwideRemoteSurcharge => _nationwideRemoteSurcharge;

  static void configure({
    required double shippingBaseFee,
    required double shippingPerKmFee,
    required double shippingMinBillableKm,
    required double shippingMissingCoordsFee,
    required double travelBaseFee,
    required double travelPerKmFee,
    required double travelMinBillableKm,
    required double nationwideBaseFee,
    required double nationwidePerKgFee,
    required double nationwideRemoteSurcharge,
  }) {
    _shippingBaseFee = _sanitizeMoney(shippingBaseFee, defaultBaseFee);
    _shippingPerKmFee = _sanitizeMoney(shippingPerKmFee, defaultPerKmFee);
    _shippingMinBillableKm = _sanitizeKm(shippingMinBillableKm, defaultMinBillableKm);
    _shippingMissingCoordsFee = _sanitizeMoney(
      shippingMissingCoordsFee,
      defaultMissingCoordsFee,
    );

    _travelBaseFee = _sanitizeMoney(travelBaseFee, defaultBaseFee);
    _travelPerKmFee = _sanitizeMoney(travelPerKmFee, defaultPerKmFee);
    _travelMinBillableKm = _sanitizeKm(travelMinBillableKm, defaultMinBillableKm);

    _nationwideBaseFee = _sanitizeMoney(nationwideBaseFee, defaultNationwideBaseFee);
    _nationwidePerKgFee = _sanitizeMoney(nationwidePerKgFee, defaultNationwidePerKgFee);
    _nationwideRemoteSurcharge = _sanitizeMoney(
      nationwideRemoteSurcharge,
      defaultNationwideRemoteSurcharge,
    );
  }

  static double computeLocalShippingFee(double distanceKm) {
    return _computeDistanceFee(
      distanceKm: distanceKm,
      baseFee: _shippingBaseFee,
      perKmFee: _shippingPerKmFee,
      minBillableKm: _shippingMinBillableKm,
      maxBillableKm: _shippingMaxBillableKm,
    );
  }

  static double computeTravelFare(double distanceKm) {
    return _computeDistanceFee(
      distanceKm: distanceKm,
      baseFee: _travelBaseFee,
      perKmFee: _travelPerKmFee,
      minBillableKm: _travelMinBillableKm,
    );
  }

  static double computeNationwideFee({
    required int weightGrams,
    required bool remoteArea,
  }) {
    final weightKg = (weightGrams / 1000).ceil().clamp(1, 30);
    var fee = _nationwideBaseFee + (weightKg * _nationwidePerKgFee);
    if (remoteArea) {
      fee += _nationwideRemoteSurcharge;
    }
    return fee;
  }

  static double _computeDistanceFee({
    required double distanceKm,
    required double baseFee,
    required double perKmFee,
    required double minBillableKm,
    double? maxBillableKm,
  }) {
    final normalizedKm = distanceKm.isNaN || distanceKm.isInfinite || distanceKm < 0
        ? 0
        : distanceKm;
    final cappedKm = maxBillableKm != null && normalizedKm > maxBillableKm
        ? maxBillableKm
        : normalizedKm;
    final billableKm = cappedKm < minBillableKm ? minBillableKm : cappedKm;
    final fee = baseFee + ((billableKm - minBillableKm) * perKmFee);
    return double.parse(fee.toStringAsFixed(2));
  }

  static double _sanitizeMoney(double value, double fallback) {
    if (value.isNaN || value.isInfinite || value < 0 || value > 100000) {
      return fallback;
    }
    return value;
  }

  static double _sanitizeKm(double value, double fallback) {
    if (value.isNaN || value.isInfinite || value <= 0 || value > 100) {
      return fallback;
    }
    return value;
  }
}
