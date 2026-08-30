import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'models/home_quick_action_config.dart';
import 'services/home_catalog_bootstrap.dart';
import 'services/home_product_image_prefetch.dart';
import 'services/home_quick_action_config_service.dart';
import 'services/promotion_catalog_service.dart';
import 'public_catalog_service.dart';
import 'models/promotion_models.dart';
import 'models/product_variant.dart';
import 'widgets/product_discount_display.dart';

class HomeProductDiscoveryService {
  HomeProductDiscoveryService._();

  static const int shelfLimit = 12;
  static const int discountFeedScanLimit = 300;

  static HomeQuickActionConfig get _homeActions =>
      HomeQuickActionConfigService.instance.currentQuickActions;

  static List<PublicCatalogProduct> _filterHomeProducts(
    List<PublicCatalogProduct> products,
  ) {
    return PublicCatalogService.filterHomeRetailProducts(
      products,
      enabledServiceTypes: _homeActions.enabledRetailServiceTypes,
    );
  }

  static List<PublicCatalogProduct> _applyExcludeIds(
    List<PublicCatalogProduct> products,
    Set<String> excludeIds,
  ) {
    if (excludeIds.isEmpty) {
      return products;
    }
    return products
        .where((product) => !excludeIds.contains(product.id))
        .toList(growable: false);
  }

  static ({
    List<PublicCatalogProduct> bestSelling,
    List<PublicCatalogProduct> personalized,
  })?
  peekCachedSecondaryShelves({Set<String> excludeIds = const <String>{}}) {
    final bestSelling = _applyExcludeIds(
      _filterHomeProducts(
        HomeCatalogBootstrap.peekBestSellingShelf() ??
            const <PublicCatalogProduct>[],
      ),
      excludeIds,
    ).take(shelfLimit).toList(growable: false);
    final personalized = _applyExcludeIds(
      _filterHomeProducts(
        HomeCatalogBootstrap.peekPersonalizedShelf() ??
            const <PublicCatalogProduct>[],
      ),
      excludeIds,
    ).take(shelfLimit).toList(growable: false);

    if (bestSelling.isEmpty && personalized.isEmpty) {
      return null;
    }
    return (bestSelling: bestSelling, personalized: personalized);
  }

  static Future<List<PublicCatalogProduct>> loadDiscountFeed() async {
    List<PromotionOffer> promotions = const <PromotionOffer>[];
    try {
      promotions = await PromotionCatalogService.instance
          .watchActivePromotions()
          .first
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      promotions = const <PromotionOffer>[];
    }

    final candidates = _filterHomeProducts(
      await PublicCatalogService.listRecentActiveProducts(
        limit: discountFeedScanLimit,
      ),
    );

    final scored = <({PublicCatalogProduct product, double discount})>[];
    for (final product in candidates) {
      final pricingData = ProductVariantSupport.catalogListPricingData(
        product.data,
      );
      final promotion = PromotionCatalogService.instance.promotionForProduct(
        promotions,
        productId: product.id,
        shopId: product.shopId,
      );
      final display = ProductDiscountDisplay.resolve(
        productData: pricingData,
        promotion: promotion,
      );
      final discount = ProductDiscountDisplay.effectiveDiscountPercent(display);
      if (discount <= 0) {
        continue;
      }
      scored.add((product: product, discount: discount));
    }

    scored.sort((left, right) {
      final byDiscount = right.discount.compareTo(left.discount);
      if (byDiscount != 0) {
        return byDiscount;
      }
      return left.product.id.compareTo(right.product.id);
    });

    return scored.map((entry) => entry.product).toList(growable: false);
  }

  static Stream<List<PublicCatalogProduct>> streamFeaturedShelf({
    Set<String> excludeIds = const <String>{},
  }) async* {
    final cached = _filterHomeProducts(
      HomeCatalogBootstrap.peekFeaturedShelf() ?? const <PublicCatalogProduct>[],
    );
    if (cached.isNotEmpty) {
      yield cached;
    }

    await for (final featuredIds in PublicCatalogService.streamFeaturedProductIds()) {
      final fresh = await _buildFeaturedShelf(
        featuredIds,
        excludeIds: excludeIds,
      );
      HomeCatalogBootstrap.updateFeaturedShelf(fresh);
      if (fresh.isNotEmpty) {
        HomeProductImagePrefetch.scheduleShelfPrefetch(
          fresh,
          limit: shelfLimit,
        );
      }
      yield fresh;
    }
  }

  static Future<List<PublicCatalogProduct>> loadBestSellingShelf({
    Set<String> excludeIds = const <String>{},
  }) async {
    final cached = _filterHomeProducts(
      HomeCatalogBootstrap.peekBestSellingShelf() ??
          const <PublicCatalogProduct>[],
    )
        .where((product) => !excludeIds.contains(product.id))
        .toList(growable: false);

    final networkFuture = _fetchBestSellingShelf(excludeIds: excludeIds);
    if (cached.isNotEmpty) {
      unawaited(
        networkFuture.then((products) {
          if (products.isNotEmpty) {
            HomeCatalogBootstrap.updateBestSellingShelf(products);
          }
        }),
      );
      return cached.take(shelfLimit).toList(growable: false);
    }

    final products = await networkFuture;
    if (products.isNotEmpty) {
      HomeCatalogBootstrap.updateBestSellingShelf(products);
    }
    return products;
  }

  static Future<List<PublicCatalogProduct>> _fetchBestSellingShelf({
    required Set<String> excludeIds,
  }) async {
    final products = await PublicCatalogService.listBestSellingProducts(
      limit: shelfLimit * 3,
      excludeIds: excludeIds,
    );
    return _ensureRetailShelfProducts(
      _filterHomeProducts(products),
      excludeIds: excludeIds,
    );
  }

  static Future<
    ({
      List<PublicCatalogProduct> bestSelling,
      List<PublicCatalogProduct> personalized,
    })
  >
  loadSecondaryShelves({
    required double? customerLatitude,
    required double? customerLongitude,
    Set<String> excludeIds = const <String>{},
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = peekCachedSecondaryShelves(excludeIds: excludeIds);
      if (cached != null) {
        unawaited(
          _refreshSecondaryShelves(
            customerLatitude: customerLatitude,
            customerLongitude: customerLongitude,
            excludeIds: excludeIds,
          ).catchError((_) {
            return (
              bestSelling: const <PublicCatalogProduct>[],
              personalized: const <PublicCatalogProduct>[],
            );
          }),
        );
        return cached;
      }
    }

    try {
      return await _refreshSecondaryShelves(
        customerLatitude: customerLatitude,
        customerLongitude: customerLongitude,
        excludeIds: excludeIds,
      );
    } catch (_) {
      return (
        bestSelling: const <PublicCatalogProduct>[],
        personalized: const <PublicCatalogProduct>[],
      );
    }
  }

  static Future<
    ({
      List<PublicCatalogProduct> bestSelling,
      List<PublicCatalogProduct> personalized,
    })
  >
  _refreshSecondaryShelves({
    required double? customerLatitude,
    required double? customerLongitude,
    required Set<String> excludeIds,
  }) async {
    List<PublicCatalogProduct> bestSelling = const <PublicCatalogProduct>[];
    List<PublicCatalogProduct> personalized = const <PublicCatalogProduct>[];

    try {
      bestSelling = await _fetchBestSellingShelf(excludeIds: excludeIds);
      if (bestSelling.isNotEmpty) {
        HomeCatalogBootstrap.updateBestSellingShelf(bestSelling);
      }
    } catch (_) {}

    try {
      final combinedExclude = <String>{
        ...excludeIds,
        ...bestSelling.map((product) => product.id),
      };
      personalized = await _fetchPersonalizedShelf(
        customerLatitude: customerLatitude,
        customerLongitude: customerLongitude,
        excludeIds: combinedExclude,
      );
      if (personalized.isEmpty) {
        personalized = await _fetchPersonalizedShelf(
          customerLatitude: customerLatitude,
          customerLongitude: customerLongitude,
          excludeIds: excludeIds,
        );
      }
      if (personalized.isNotEmpty) {
        HomeCatalogBootstrap.updatePersonalizedShelf(personalized);
      }
    } catch (_) {}

    return (bestSelling: bestSelling, personalized: personalized);
  }

  static Future<List<PublicCatalogProduct>> loadPersonalizedShelf({
    required double? customerLatitude,
    required double? customerLongitude,
    Set<String> excludeIds = const <String>{},
  }) async {
    final cached = _applyExcludeIds(
      _filterHomeProducts(
        HomeCatalogBootstrap.peekPersonalizedShelf() ??
            const <PublicCatalogProduct>[],
      ),
      excludeIds,
    );

    final networkFuture = _fetchPersonalizedShelf(
      customerLatitude: customerLatitude,
      customerLongitude: customerLongitude,
      excludeIds: excludeIds,
    );
    if (cached.isNotEmpty) {
      unawaited(
        networkFuture.then((products) {
          if (products.isNotEmpty) {
            HomeCatalogBootstrap.updatePersonalizedShelf(products);
          }
        }),
      );
      return cached.take(shelfLimit).toList(growable: false);
    }

    final products = await networkFuture;
    if (products.isNotEmpty) {
      HomeCatalogBootstrap.updatePersonalizedShelf(products);
    }
    return products;
  }

  static Future<List<PublicCatalogProduct>> _fetchPersonalizedShelf({
    required double? customerLatitude,
    required double? customerLongitude,
    required Set<String> excludeIds,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    List<PublicCatalogProduct> products;
    if (user != null && !user.isAnonymous) {
      try {
        products = await _loadFromOrderHistory(
          customerId: user.uid,
          excludeIds: excludeIds,
        ).timeout(const Duration(seconds: 3));
      } catch (_) {
        products = const <PublicCatalogProduct>[];
      }
      if (products.isEmpty) {
        products = await _loadNearbyPopularShelf(
          customerLatitude: customerLatitude,
          customerLongitude: customerLongitude,
          excludeIds: excludeIds,
        );
      }
    } else {
      products = await _loadNearbyPopularShelf(
        customerLatitude: customerLatitude,
        customerLongitude: customerLongitude,
        excludeIds: excludeIds,
      );
    }

    return _ensureRetailShelfProducts(
      _filterHomeProducts(products),
      excludeIds: excludeIds,
    );
  }

  static Future<List<PublicCatalogProduct>> _ensureRetailShelfProducts(
    List<PublicCatalogProduct> products, {
    required Set<String> excludeIds,
  }) async {
    if (products.length >= shelfLimit) {
      return products.take(shelfLimit).toList(growable: false);
    }

    final usedIds = <String>{
      ...excludeIds,
      ...products.map((product) => product.id),
    };
    final filler = _filterHomeProducts(
      await PublicCatalogService.listRecentActiveProducts(
        limit: shelfLimit * 4,
        excludeIds: usedIds,
      ),
    );

    return <PublicCatalogProduct>[
      ...products,
      ...filler,
    ].take(shelfLimit).toList(growable: false);
  }

  static Future<List<PublicCatalogProduct>> _buildFeaturedShelf(
    List<String> featuredIds, {
    Set<String> excludeIds = const <String>{},
  }) async {
    final resolved = _filterHomeProducts(
      await PublicCatalogService.resolveProductsByIds(
        featuredIds,
        excludeIds: excludeIds,
      ),
    );

    if (resolved.length >= PublicCatalogService.homeShelfTargetCount) {
      return resolved.take(shelfLimit).toList(growable: false);
    }

    final usedIds = <String>{
      ...excludeIds,
      ...resolved.map((product) => product.id),
    };
    final filler = _filterHomeProducts(
      await PublicCatalogService.listRecentActiveProducts(
        limit: shelfLimit * 3,
        excludeIds: usedIds,
      ),
    );

    return <PublicCatalogProduct>[
      ...resolved,
      ...filler,
    ].take(shelfLimit).toList(growable: false);
  }

  static Future<List<PublicCatalogProduct>> _loadFromOrderHistory({
    required String customerId,
    Set<String> excludeIds = const <String>{},
  }) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('orders')
        .where('customerId', isEqualTo: customerId)
        .limit(50)
        .get();

    final scores = <String, double>{};
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (_isTravelPassengerOrder(data)) {
        continue;
      }

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'cancelled' || status == 'canceled') {
        continue;
      }

      final orderedAt = _readOrderCreatedAt(data);
      final ageDays = orderedAt == null
          ? 365.0
          : max(
              1.0,
              (nowMs - orderedAt.millisecondsSinceEpoch) / Duration.millisecondsPerDay,
            );
      final recencyWeight = 1 / ageDays;

      final productLines = _readOrderProductLines(data);
      for (final line in productLines) {
        final productId = line.productId;
        if (productId == null || productId.isEmpty || excludeIds.contains(productId)) {
          continue;
        }

        final quantity = max(1, line.quantity);
        scores[productId] = (scores[productId] ?? 0) + (quantity * recencyWeight);
      }
    }

    if (scores.isEmpty) {
      return const <PublicCatalogProduct>[];
    }

    final rankedIds = scores.entries.toList(growable: false)
      ..sort((left, right) => right.value.compareTo(left.value));

    return PublicCatalogService.resolveProductsByIds(
      rankedIds.map((entry) => entry.key).take(shelfLimit * 2).toList(growable: false),
      excludeIds: excludeIds,
    ).then((products) => products.take(shelfLimit).toList(growable: false));
  }

  static Future<List<PublicCatalogProduct>> _loadNearbyPopularShelf({
    required double? customerLatitude,
    required double? customerLongitude,
    Set<String> excludeIds = const <String>{},
  }) async {
    final recent = await PublicCatalogService.listRecentActiveProducts(
      limit: shelfLimit * 4,
      excludeIds: excludeIds,
    );

    if (recent.isEmpty) {
      return recent;
    }

    if (customerLatitude == null ||
        customerLongitude == null ||
        !customerLatitude.isFinite ||
        !customerLongitude.isFinite) {
      return recent.take(shelfLimit).toList(growable: false);
    }

    final scored = recent
        .map((product) {
          final lat = product.shopLatitude;
          final lng = product.shopLongitude;
          if (lat == null || lng == null) {
            return (product: product, score: double.maxFinite);
          }

          final distanceMeters = Geolocator.distanceBetween(
            customerLatitude,
            customerLongitude,
            lat,
            lng,
          );
          return (product: product, score: distanceMeters);
        })
        .toList(growable: true)
      ..sort((left, right) => left.score.compareTo(right.score));

    return scored
        .map((entry) => entry.product)
        .take(shelfLimit)
        .toList(growable: false);
  }

  static bool _isTravelPassengerOrder(Map<String, dynamic> data) {
    final serviceType = (data['serviceType'] ?? data['orderType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return serviceType.contains('travel') || serviceType.contains('passenger');
  }

  static DateTime? _readOrderCreatedAt(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      return createdAt.toDate();
    }
    if (createdAt is DateTime) {
      return createdAt;
    }
    return null;
  }

  static List<_OrderProductLine> _readOrderProductLines(Map<String, dynamic> data) {
    final rawProducts = data['products'] ?? data['items'];
    if (rawProducts is! List) {
      return const <_OrderProductLine>[];
    }

    final results = <_OrderProductLine>[];
    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }

      final productMap = Map<String, dynamic>.from(rawProduct);
      final productId = _readFirstNonEmptyValue(
        productMap,
        const <String>['productId', 'product_id', 'id', 'docId', 'documentId'],
      );
      final quantityRaw = productMap['quantity'];
      final quantity = quantityRaw is num
          ? quantityRaw.toInt()
          : int.tryParse('${quantityRaw ?? ''}'.trim()) ?? 1;

      results.add(_OrderProductLine(productId: productId, quantity: quantity));
    }

    return results;
  }

  static String? _readFirstNonEmptyValue(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

class _OrderProductLine {
  const _OrderProductLine({required this.productId, required this.quantity});

  final String? productId;
  final int quantity;
}
