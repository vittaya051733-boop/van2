import 'dart:math' as math;

import 'pricing_config_service.dart';

class MarketShopLocation {
  const MarketShopLocation({
    required this.shopId,
    required this.latitude,
    required this.longitude,
  });

  final String shopId;
  final double? latitude;
  final double? longitude;
}

class MarketCheckoutFees {
  const MarketCheckoutFees({
    required this.applies,
    required this.qualifyingShopCount,
    required this.collectionFee,
    required this.serviceFeePerOrder,
    required this.serviceFeeTotal,
    required this.totalFees,
    required this.qualifyingShopIds,
  });

  final bool applies;
  final int qualifyingShopCount;
  final double collectionFee;
  final double serviceFeePerOrder;
  final double serviceFeeTotal;
  final double totalFees;
  final Set<String> qualifyingShopIds;

  static const MarketCheckoutFees zero = MarketCheckoutFees(
    applies: false,
    qualifyingShopCount: 0,
    collectionFee: 0,
    serviceFeePerOrder: 0,
    serviceFeeTotal: 0,
    totalFees: 0,
    qualifyingShopIds: <String>{},
  );

  bool shopQualifies(String shopId) => qualifyingShopIds.contains(shopId);

  double feesForShop(String shopId, {required bool collectionAssigned}) {
    if (!applies || !shopQualifies(shopId)) {
      return 0;
    }
    var total = serviceFeePerOrder;
    if (collectionAssigned) {
      total += collectionFee;
    }
    return total;
  }
}

class MarketPricingPolicy {
  MarketPricingPolicy._();

  static const double defaultHubLatitude = 17.279915312140325;
  static const double defaultHubLongitude = 102.87070264132565;
  static const double defaultHubRadiusMeters = 150;
  static const int defaultMultiShopMinShops = 2;
  static const double defaultCollectionFee = 5;
  static const double defaultServiceFeePerOrder = 5;

  static double _hubLatitude = defaultHubLatitude;
  static double _hubLongitude = defaultHubLongitude;
  static double _hubRadiusMeters = defaultHubRadiusMeters;
  static int _multiShopMinShops = defaultMultiShopMinShops;
  static double _collectionFee = defaultCollectionFee;
  static double _serviceFeePerOrder = defaultServiceFeePerOrder;

  static void configure({
    required double marketHubLatitude,
    required double marketHubLongitude,
    required double marketHubRadiusMeters,
    required int marketMultiShopMinShops,
    required double marketMultiShopCollectionFee,
    required double marketServiceFeePerOrder,
  }) {
    _hubLatitude = _sanitizeLatitude(marketHubLatitude, defaultHubLatitude);
    _hubLongitude = _sanitizeLongitude(marketHubLongitude, defaultHubLongitude);
    _hubRadiusMeters = _sanitizeRadius(marketHubRadiusMeters, defaultHubRadiusMeters);
    _multiShopMinShops = _sanitizeMinShops(
      marketMultiShopMinShops,
      defaultMultiShopMinShops,
    );
    _collectionFee = _sanitizeMoney(
      marketMultiShopCollectionFee,
      defaultCollectionFee,
    );
    _serviceFeePerOrder = _sanitizeMoney(
      marketServiceFeePerOrder,
      defaultServiceFeePerOrder,
    );
  }

  static void configureFrom(GlobalPricingConfig config) {
    configure(
      marketHubLatitude: config.marketHubLatitude,
      marketHubLongitude: config.marketHubLongitude,
      marketHubRadiusMeters: config.marketHubRadiusMeters,
      marketMultiShopMinShops: config.marketMultiShopMinShops,
      marketMultiShopCollectionFee: config.marketMultiShopCollectionFee,
      marketServiceFeePerOrder: config.marketServiceFeePerOrder,
    );
  }

  static bool isShopNearHub({
    required double? latitude,
    required double? longitude,
  }) {
    if (latitude == null || longitude == null) {
      return false;
    }
    return distanceMeters(
          fromLatitude: latitude,
          fromLongitude: longitude,
          toLatitude: _hubLatitude,
          toLongitude: _hubLongitude,
        ) <=
        _hubRadiusMeters;
  }

  static MarketCheckoutFees computeCheckoutFees(
    Iterable<MarketShopLocation> shops,
  ) {
    final qualifyingIds = <String>{};
    for (final shop in shops) {
      final shopId = shop.shopId.trim();
      if (shopId.isEmpty) {
        continue;
      }
      if (isShopNearHub(
        latitude: shop.latitude,
        longitude: shop.longitude,
      )) {
        qualifyingIds.add(shopId);
      }
    }

    if (qualifyingIds.length < _multiShopMinShops) {
      return MarketCheckoutFees.zero;
    }

    final serviceTotal = _serviceFeePerOrder * qualifyingIds.length;
    final total = _collectionFee + serviceTotal;
    return MarketCheckoutFees(
      applies: true,
      qualifyingShopCount: qualifyingIds.length,
      collectionFee: _collectionFee,
      serviceFeePerOrder: _serviceFeePerOrder,
      serviceFeeTotal: serviceTotal,
      totalFees: total,
      qualifyingShopIds: qualifyingIds,
    );
  }

  static double distanceMeters({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    const earthRadiusMeters = 6371000;
    final dLat = _toRadians(toLatitude - fromLatitude);
    final dLng = _toRadians(toLongitude - fromLongitude);
    final lat1 = _toRadians(fromLatitude);
    final lat2 = _toRadians(toLatitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static double _sanitizeLatitude(double value, double fallback) {
    if (value.isNaN || value.isInfinite || value < -90 || value > 90) {
      return fallback;
    }
    return value;
  }

  static double _sanitizeLongitude(double value, double fallback) {
    if (value.isNaN || value.isInfinite || value < -180 || value > 180) {
      return fallback;
    }
    return value;
  }

  static double _sanitizeRadius(double value, double fallback) {
    if (value.isNaN || value.isInfinite || value <= 0 || value > 10000) {
      return fallback;
    }
    return value;
  }

  static int _sanitizeMinShops(int value, int fallback) {
    if (value < 2 || value > 20) {
      return fallback;
    }
    return value;
  }

  static double _sanitizeMoney(double value, double fallback) {
    if (value.isNaN || value.isInfinite || value < 0 || value > 100000) {
      return fallback;
    }
    return value;
  }
}
