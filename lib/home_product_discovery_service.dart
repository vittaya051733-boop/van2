import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'services/home_catalog_bootstrap.dart';
import 'services/home_product_image_prefetch.dart';
import 'public_catalog_service.dart';

class HomeProductDiscoveryService {
  HomeProductDiscoveryService._();

  static const int shelfLimit = 12;

  static Stream<List<PublicCatalogProduct>> streamFeaturedShelf({
    Set<String> excludeIds = const <String>{},
  }) async* {
    final cached = HomeCatalogBootstrap.peekFeaturedShelf();
    if (cached != null && cached.isNotEmpty) {
      yield cached;
    }

    await for (final featuredIds in PublicCatalogService.streamFeaturedProductIds()) {
      final fresh = await _buildFeaturedShelf(
        featuredIds,
        excludeIds: excludeIds,
      );
      if (fresh.isEmpty) {
        continue;
      }
      HomeCatalogBootstrap.updateFeaturedShelf(fresh);
      HomeProductImagePrefetch.scheduleShelfPrefetch(
        fresh,
        limit: shelfLimit,
      );
      final cachedIds =
          cached?.map((product) => product.id).join(',') ?? '';
      final freshIds = fresh.map((product) => product.id).join(',');
      if (cachedIds != freshIds) {
        yield fresh;
      }
    }
  }

  static Future<List<PublicCatalogProduct>> loadBestSellingShelf({
    Set<String> excludeIds = const <String>{},
  }) async {
    final products = await PublicCatalogService.listBestSellingProducts(
      limit: shelfLimit * 3,
      excludeIds: excludeIds,
    );
    return _ensureRetailShelfProducts(
      PublicCatalogService.filterHomeRetailProducts(products),
      excludeIds: excludeIds,
    );
  }

  static Future<List<PublicCatalogProduct>> loadPersonalizedShelf({
    required double? customerLatitude,
    required double? customerLongitude,
    Set<String> excludeIds = const <String>{},
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    List<PublicCatalogProduct> products;
    if (user != null && !user.isAnonymous) {
      products = await _loadFromOrderHistory(
        customerId: user.uid,
        excludeIds: excludeIds,
      );
    } else {
      products = await _loadNearbyPopularShelf(
        customerLatitude: customerLatitude,
        customerLongitude: customerLongitude,
        excludeIds: excludeIds,
      );
    }

    return _ensureRetailShelfProducts(
      PublicCatalogService.filterHomeRetailProducts(products),
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
    final filler = PublicCatalogService.filterHomeRetailProducts(
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
    final resolved = await PublicCatalogService.resolveProductsByIds(
      featuredIds,
      excludeIds: excludeIds,
    );

    if (resolved.length >= PublicCatalogService.homeShelfTargetCount) {
      return resolved.take(shelfLimit).toList(growable: false);
    }

    final usedIds = <String>{
      ...excludeIds,
      ...resolved.map((product) => product.id),
    };
    final filler = await PublicCatalogService.listRecentActiveProducts(
      limit: shelfLimit - resolved.length,
      excludeIds: usedIds,
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
