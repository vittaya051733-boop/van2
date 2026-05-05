import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'tax_pricing_policy.dart';

class PricingRates {
  const PricingRates({
    required this.taxableMarkupRate,
    required this.nonTaxableMarkupRate,
    required this.toppingMarkupRate,
  });

  final double taxableMarkupRate;
  final double nonTaxableMarkupRate;
  final double toppingMarkupRate;

  static const PricingRates defaults = PricingRates(
    taxableMarkupRate: TaxPricingPolicy.defaultTaxableMarkupRate,
    nonTaxableMarkupRate: TaxPricingPolicy.defaultNonTaxableMarkupRate,
    toppingMarkupRate: TaxPricingPolicy.defaultToppingMarkupRate,
  );

  factory PricingRates.fromFirestore(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    return PricingRates(
      taxableMarkupRate: _sanitizeRate(
        source['taxableMarkupRate'],
        defaults.taxableMarkupRate,
      ),
      nonTaxableMarkupRate: _sanitizeRate(
        source['nonTaxableMarkupRate'],
        defaults.nonTaxableMarkupRate,
      ),
      toppingMarkupRate: _sanitizeRate(
        source['toppingMarkupRate'],
        defaults.toppingMarkupRate,
      ),
    );
  }

  static double _sanitizeRate(Object? value, double fallback) {
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed >= 0 && parsed <= 5) {
        return parsed;
      }
    }

    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed >= 0 && parsed <= 5) {
        return parsed;
      }
    }

    return fallback;
  }
}

class PricingConfigService {
  PricingConfigService._();

  static final PricingConfigService instance = PricingConfigService._();

  static const String collectionPath = 'pricing_config';
  static const String documentId = 'global';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  Future<PricingRates> loadAndApplyOnce() async {
    try {
      final snapshot = await _firestore
          .collection(collectionPath)
          .doc(documentId)
          .get()
          .timeout(const Duration(seconds: 5));
      final rates = PricingRates.fromFirestore(snapshot.data());
      _applyRates(rates);
      return rates;
    } catch (_) {
      _applyRates(PricingRates.defaults);
      return PricingRates.defaults;
    }
  }

  void startRealtimeSync() {
    _subscription ??= _firestore
        .collection(collectionPath)
        .doc(documentId)
        .snapshots()
        .listen(
          (snapshot) => _applyRates(PricingRates.fromFirestore(snapshot.data())),
          onError: (_) {},
        );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _applyRates(PricingRates rates) {
    TaxPricingPolicy.configureRates(
      taxableMarkupRate: rates.taxableMarkupRate,
      nonTaxableMarkupRate: rates.nonTaxableMarkupRate,
      toppingMarkupRate: rates.toppingMarkupRate,
    );
  }
}
