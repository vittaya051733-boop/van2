import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'market_pricing_policy.dart';
import 'shipping_pricing_policy.dart';
import 'tax_pricing_policy.dart';

class GlobalPricingConfig {
  const GlobalPricingConfig({
    required this.taxableMarkupRate,
    required this.nonTaxableMarkupRate,
    required this.toppingMarkupRate,
    required this.shippingBaseFee,
    required this.shippingPerKmFee,
    required this.shippingMinBillableKm,
    required this.shippingMissingCoordsFee,
    required this.travelBaseFee,
    required this.travelPerKmFee,
    required this.travelMinBillableKm,
    required this.nationwideBaseFee,
    required this.nationwidePerKgFee,
    required this.nationwideRemoteSurcharge,
    required this.marketHubLatitude,
    required this.marketHubLongitude,
    required this.marketHubRadiusMeters,
    required this.marketMultiShopMinShops,
    required this.marketMultiShopCollectionFee,
    required this.marketServiceFeePerOrder,
  });

  final double taxableMarkupRate;
  final double nonTaxableMarkupRate;
  final double toppingMarkupRate;
  final double shippingBaseFee;
  final double shippingPerKmFee;
  final double shippingMinBillableKm;
  final double shippingMissingCoordsFee;
  final double travelBaseFee;
  final double travelPerKmFee;
  final double travelMinBillableKm;
  final double nationwideBaseFee;
  final double nationwidePerKgFee;
  final double nationwideRemoteSurcharge;
  final double marketHubLatitude;
  final double marketHubLongitude;
  final double marketHubRadiusMeters;
  final int marketMultiShopMinShops;
  final double marketMultiShopCollectionFee;
  final double marketServiceFeePerOrder;

  static const GlobalPricingConfig defaults = GlobalPricingConfig(
    taxableMarkupRate: TaxPricingPolicy.defaultTaxableMarkupRate,
    nonTaxableMarkupRate: TaxPricingPolicy.defaultNonTaxableMarkupRate,
    toppingMarkupRate: TaxPricingPolicy.defaultToppingMarkupRate,
    shippingBaseFee: ShippingPricingPolicy.defaultBaseFee,
    shippingPerKmFee: ShippingPricingPolicy.defaultPerKmFee,
    shippingMinBillableKm: ShippingPricingPolicy.defaultMinBillableKm,
    shippingMissingCoordsFee: ShippingPricingPolicy.defaultMissingCoordsFee,
    travelBaseFee: ShippingPricingPolicy.defaultBaseFee,
    travelPerKmFee: ShippingPricingPolicy.defaultPerKmFee,
    travelMinBillableKm: ShippingPricingPolicy.defaultMinBillableKm,
    nationwideBaseFee: ShippingPricingPolicy.defaultNationwideBaseFee,
    nationwidePerKgFee: ShippingPricingPolicy.defaultNationwidePerKgFee,
    nationwideRemoteSurcharge: ShippingPricingPolicy.defaultNationwideRemoteSurcharge,
    marketHubLatitude: MarketPricingPolicy.defaultHubLatitude,
    marketHubLongitude: MarketPricingPolicy.defaultHubLongitude,
    marketHubRadiusMeters: MarketPricingPolicy.defaultHubRadiusMeters,
    marketMultiShopMinShops: MarketPricingPolicy.defaultMultiShopMinShops,
    marketMultiShopCollectionFee: MarketPricingPolicy.defaultCollectionFee,
    marketServiceFeePerOrder: MarketPricingPolicy.defaultServiceFeePerOrder,
  );

  factory GlobalPricingConfig.fromFirestore(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    return GlobalPricingConfig(
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
      shippingBaseFee: _sanitizeMoney(
        source['shippingBaseFee'],
        defaults.shippingBaseFee,
      ),
      shippingPerKmFee: _sanitizeMoney(
        source['shippingPerKmFee'],
        defaults.shippingPerKmFee,
      ),
      shippingMinBillableKm: _sanitizeKm(
        source['shippingMinBillableKm'],
        defaults.shippingMinBillableKm,
      ),
      shippingMissingCoordsFee: _sanitizeMoney(
        source['shippingMissingCoordsFee'],
        defaults.shippingMissingCoordsFee,
      ),
      travelBaseFee: _sanitizeMoney(source['travelBaseFee'], defaults.travelBaseFee),
      travelPerKmFee: _sanitizeMoney(source['travelPerKmFee'], defaults.travelPerKmFee),
      travelMinBillableKm: _sanitizeKm(
        source['travelMinBillableKm'],
        defaults.travelMinBillableKm,
      ),
      nationwideBaseFee: _sanitizeMoney(
        source['nationwideBaseFee'],
        defaults.nationwideBaseFee,
      ),
      nationwidePerKgFee: _sanitizeMoney(
        source['nationwidePerKgFee'],
        defaults.nationwidePerKgFee,
      ),
      nationwideRemoteSurcharge: _sanitizeMoney(
        source['nationwideRemoteSurcharge'],
        defaults.nationwideRemoteSurcharge,
      ),
      marketHubLatitude: _sanitizeLatitude(
        source['marketHubLatitude'],
        defaults.marketHubLatitude,
      ),
      marketHubLongitude: _sanitizeLongitude(
        source['marketHubLongitude'],
        defaults.marketHubLongitude,
      ),
      marketHubRadiusMeters: _sanitizeRadius(
        source['marketHubRadiusMeters'],
        defaults.marketHubRadiusMeters,
      ),
      marketMultiShopMinShops: _sanitizeInt(
        source['marketMultiShopMinShops'],
        defaults.marketMultiShopMinShops,
        min: 2,
        max: 20,
      ),
      marketMultiShopCollectionFee: _sanitizeMoney(
        source['marketMultiShopCollectionFee'],
        defaults.marketMultiShopCollectionFee,
      ),
      marketServiceFeePerOrder: _sanitizeMoney(
        source['marketServiceFeePerOrder'],
        defaults.marketServiceFeePerOrder,
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'taxableMarkupRate': taxableMarkupRate,
      'nonTaxableMarkupRate': nonTaxableMarkupRate,
      'toppingMarkupRate': toppingMarkupRate,
      'shippingBaseFee': shippingBaseFee,
      'shippingPerKmFee': shippingPerKmFee,
      'shippingMinBillableKm': shippingMinBillableKm,
      'shippingMissingCoordsFee': shippingMissingCoordsFee,
      'travelBaseFee': travelBaseFee,
      'travelPerKmFee': travelPerKmFee,
      'travelMinBillableKm': travelMinBillableKm,
      'nationwideBaseFee': nationwideBaseFee,
      'nationwidePerKgFee': nationwidePerKgFee,
      'nationwideRemoteSurcharge': nationwideRemoteSurcharge,
      'marketHubLatitude': marketHubLatitude,
      'marketHubLongitude': marketHubLongitude,
      'marketHubRadiusMeters': marketHubRadiusMeters,
      'marketMultiShopMinShops': marketMultiShopMinShops,
      'marketMultiShopCollectionFee': marketMultiShopCollectionFee,
      'marketServiceFeePerOrder': marketServiceFeePerOrder,
    };
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

  static double _sanitizeMoney(Object? value, double fallback) {
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed >= 0 && parsed <= 100000) {
        return parsed;
      }
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed >= 0 && parsed <= 100000) {
        return parsed;
      }
    }
    return fallback;
  }

  static double _sanitizeLatitude(Object? value, double fallback) {
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed >= -90 && parsed <= 90) {
        return parsed;
      }
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed >= -90 && parsed <= 90) {
        return parsed;
      }
    }
    return fallback;
  }

  static double _sanitizeLongitude(Object? value, double fallback) {
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed >= -180 && parsed <= 180) {
        return parsed;
      }
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed >= -180 && parsed <= 180) {
        return parsed;
      }
    }
    return fallback;
  }

  static double _sanitizeRadius(Object? value, double fallback) {
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed > 0 && parsed <= 10000) {
        return parsed;
      }
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed > 0 && parsed <= 10000) {
        return parsed;
      }
    }
    return fallback;
  }

  static int _sanitizeInt(
    Object? value,
    int fallback, {
    required int min,
    required int max,
  }) {
    if (value is num) {
      final parsed = value.toInt();
      if (parsed >= min && parsed <= max) {
        return parsed;
      }
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null && parsed >= min && parsed <= max) {
        return parsed;
      }
    }
    return fallback;
  }

  static double _sanitizeKm(Object? value, double fallback) {
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed > 0 && parsed <= 100) {
        return parsed;
      }
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed > 0 && parsed <= 100) {
        return parsed;
      }
    }
    return fallback;
  }
}

/// Backward-compatible alias for markup-only callers.
typedef PricingRates = GlobalPricingConfig;

class PricingConfigService extends ChangeNotifier {
  PricingConfigService._();

  static final PricingConfigService instance = PricingConfigService._();

  static const String collectionPath = 'pricing_config';
  static const String documentId = 'global';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  bool _resubscribeScheduled = false;
  static const Duration _resubscribeDelay = Duration(seconds: 3);

  GlobalPricingConfig _current = GlobalPricingConfig.defaults;
  GlobalPricingConfig get current => _current;

  Future<GlobalPricingConfig> loadAndApplyOnce() async {
    try {
      final snapshot = await _firestore
          .collection(collectionPath)
          .doc(documentId)
          .get()
          .timeout(const Duration(seconds: 5));
      final config = GlobalPricingConfig.fromFirestore(snapshot.data());
      _apply(config);
      return config;
    } catch (_) {
      _apply(GlobalPricingConfig.defaults);
      return GlobalPricingConfig.defaults;
    }
  }

  void startRealtimeSync() {
    if (_subscription != null) {
      return;
    }
    _attachPricingListener();
  }

  void _attachPricingListener() {
    _subscription?.cancel();
    _subscription = _firestore
        .collection(collectionPath)
        .doc(documentId)
        .snapshots()
        .listen(
          (snapshot) =>
              _apply(GlobalPricingConfig.fromFirestore(snapshot.data())),
          onError: (_, __) => _schedulePricingResubscribe(),
          onDone: () {
            _subscription = null;
            _schedulePricingResubscribe();
          },
        );
  }

  void _schedulePricingResubscribe() {
    if (_resubscribeScheduled) {
      return;
    }
    _resubscribeScheduled = true;
    Future<void>.delayed(_resubscribeDelay, () {
      _resubscribeScheduled = false;
      _attachPricingListener();
    });
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  void _apply(GlobalPricingConfig config) {
    _current = config;
    TaxPricingPolicy.configureRates(
      taxableMarkupRate: config.taxableMarkupRate,
      nonTaxableMarkupRate: config.nonTaxableMarkupRate,
      toppingMarkupRate: config.toppingMarkupRate,
    );
    ShippingPricingPolicy.configure(
      shippingBaseFee: config.shippingBaseFee,
      shippingPerKmFee: config.shippingPerKmFee,
      shippingMinBillableKm: config.shippingMinBillableKm,
      shippingMissingCoordsFee: config.shippingMissingCoordsFee,
      travelBaseFee: config.travelBaseFee,
      travelPerKmFee: config.travelPerKmFee,
      travelMinBillableKm: config.travelMinBillableKm,
      nationwideBaseFee: config.nationwideBaseFee,
      nationwidePerKgFee: config.nationwidePerKgFee,
      nationwideRemoteSurcharge: config.nationwideRemoteSurcharge,
    );
    MarketPricingPolicy.configureFrom(config);
    notifyListeners();
  }
}
