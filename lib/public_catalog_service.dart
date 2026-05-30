import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'public_catalog_local_cache.dart';

class PublicCatalogProduct {
  const PublicCatalogProduct({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.shopImageUrl,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.data,
  });

  final String id;
  final String shopId;
  final String? shopName;
  final String? shopImageUrl;
  final double? shopLatitude;
  final double? shopLongitude;
  final Map<String, dynamic> data;
}

class PublicCatalogSection {
  const PublicCatalogSection({
    required this.shopId,
    required this.shopName,
    required this.shopImageUrl,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.products,
    this.shopUpdatedAt,
    this.shopDescription,
  });

  final String shopId;
  final String? shopName;
  final String? shopImageUrl;
  final double? shopLatitude;
  final double? shopLongitude;
  final List<PublicCatalogProduct> products;
  final DateTime? shopUpdatedAt;
  final String? shopDescription;
}

class PublicCatalogService {
  PublicCatalogService._();

  static const Duration _publicShopsNetworkTtl = Duration(minutes: 30);
  static Map<String, Map<String, dynamic>>? _cachedPublicShops;
  static DateTime? _publicShopsCachedAt;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _publicShopsSubscription;

  static Stream<List<PublicCatalogSection>> streamAllSections() {
    return _streamActiveProducts('', '');
  }

  static Stream<List<PublicCatalogSection>> streamSectionsByServiceType(
    String serviceType,
  ) {
    final normalized = _normalizeServiceType(serviceType);
    return _streamActiveProducts(normalized, '');
  }

  static Stream<List<PublicCatalogSection>> streamNationwideShippingSections() {
    final query = FirebaseFirestore.instance
        .collection('products')
        .where('isActive', isEqualTo: true);

    return _streamFromProductQuery(
      query,
      requiredServiceType: '',
      requiredShopId: '',
      nationwideShippingOnly: true,
    );
  }

  static Stream<List<PublicCatalogSection>> streamSectionsByShopId(
    String shopId,
  ) {
    final normalizedShopId = shopId.trim();
    if (normalizedShopId.isEmpty) {
      return Stream<List<PublicCatalogSection>>.value(
        const <PublicCatalogSection>[],
      );
    }

    final query = FirebaseFirestore.instance
        .collection('products')
        .where('ownerUid', isEqualTo: normalizedShopId)
        .where('isActive', isEqualTo: true);

    return _streamFromProductQuery(
      query,
      requiredServiceType: '',
      requiredShopId: normalizedShopId,
    );
  }

  static Stream<List<PublicCatalogSection>> _streamActiveProducts(
    String requiredServiceType,
    String requiredShopId,
  ) {
    final query = FirebaseFirestore.instance
        .collection('products')
        .where('isActive', isEqualTo: true);

    return _streamFromProductQuery(
      query,
      requiredServiceType: requiredServiceType,
      requiredShopId: requiredShopId,
    );
  }

  static Stream<List<PublicCatalogSection>> _streamFromProductQuery(
    Query<Map<String, dynamic>> query, {
    required String requiredServiceType,
    required String requiredShopId,
    bool nationwideShippingOnly = false,
  }) {
    return Stream<List<PublicCatalogSection>>.multi((controller) async {
      await _ensureCatalogAuth();
      await PublicCatalogLocalCache.ensureProductsHydrated();
      await PublicCatalogLocalCache.ensurePublicShopsHydrated();

      final diskShops = PublicCatalogLocalCache.publicShopsById;
      if (diskShops.isNotEmpty) {
        _cachedPublicShops = diskShops;
      }

      if (PublicCatalogLocalCache.productsById.isNotEmpty) {
        controller.add(
          _buildSectionsFromCachedProducts(
            requiredServiceType,
            requiredShopId,
            _resolvePublicShops(),
            nationwideShippingOnly: nationwideShippingOnly,
          ),
        );
      }

      final subscription = query.snapshots().listen(
        (snapshot) async {
          PublicCatalogLocalCache.applyProductSnapshot(snapshot);
          final publicShops = await _getPublicShops();
          if (!controller.isClosed) {
            controller.add(
              _buildSectionsFromCachedProducts(
                requiredServiceType,
                requiredShopId,
                publicShops,
                nationwideShippingOnly: nationwideShippingOnly,
              ),
            );
          }
        },
        onError: controller.addError,
      );

      controller.onCancel = () => subscription.cancel();
    });
  }

  static Map<String, Map<String, dynamic>> _resolvePublicShops() {
    return _cachedPublicShops ?? PublicCatalogLocalCache.publicShopsById;
  }

  static List<PublicCatalogSection> _buildSectionsFromCachedProducts(
    String requiredServiceType,
    String requiredShopId,
    Map<String, Map<String, dynamic>> publicShops, {
    bool nationwideShippingOnly = false,
  }) {
    return _buildSectionsFromDocs(
      PublicCatalogLocalCache.productsById.entries.map(
        (entry) => _CatalogProductEntry(id: entry.key, data: entry.value),
      ),
      requiredServiceType,
      requiredShopId,
      publicShops,
      nationwideShippingOnly: nationwideShippingOnly,
    );
  }

  static Future<void> _ensureCatalogAuth() async {
    try {
      var user = FirebaseAuth.instance.currentUser;
      user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
      if (user != null) {
        await user.getIdToken(true);
      }
    } catch (_) {
      // UI surfaces Firestore errors if auth is unavailable.
    }
  }

  static Future<Map<String, Map<String, dynamic>>> _getPublicShops() async {
    await PublicCatalogLocalCache.ensurePublicShopsHydrated();

    final cachedAt = _publicShopsCachedAt;
    final cached = _cachedPublicShops;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _publicShopsNetworkTtl) {
      return cached;
    }

    final diskShops = PublicCatalogLocalCache.publicShopsById;
    if (diskShops.isNotEmpty && cached == null) {
      _cachedPublicShops = diskShops;
      return diskShops;
    }

    try {
      await _ensureCatalogAuth();
      final snapshot = await FirebaseFirestore.instance
          .collection('public_shops')
          .get();
      final shops = <String, Map<String, dynamic>>{
        for (final doc in snapshot.docs) doc.id: doc.data(),
      };
      _cachedPublicShops = shops;
      _publicShopsCachedAt = DateTime.now();
      PublicCatalogLocalCache.replacePublicShops(shops);
      _ensurePublicShopsListener();
      return shops;
    } catch (_) {
      if (cached != null) {
        return cached;
      }
      if (diskShops.isNotEmpty) {
        return diskShops;
      }
      return const <String, Map<String, dynamic>>{};
    }
  }

  static void _ensurePublicShopsListener() {
    if (_publicShopsSubscription != null) {
      return;
    }

    _publicShopsSubscription = FirebaseFirestore.instance
        .collection('public_shops')
        .snapshots()
        .listen(
          (snapshot) {
            final shops = {
              for (final doc in snapshot.docs) doc.id: doc.data(),
            };
            _cachedPublicShops = shops;
            _publicShopsCachedAt = DateTime.now();
            PublicCatalogLocalCache.replacePublicShops(shops);
          },
          onError: (_) {},
        );
  }

  static List<PublicCatalogSection> _buildSectionsFromDocs(
    Iterable<_CatalogProductEntry> docs,
    String requiredServiceType,
    String requiredShopId,
    Map<String, Map<String, dynamic>> publicShops, {
    bool nationwideShippingOnly = false,
  }) {
    final grouped = <String, List<PublicCatalogProduct>>{};
    final normalizedTargetServiceType = requiredServiceType.trim().isEmpty
        ? null
        : _normalizeServiceType(requiredServiceType);
    final normalizedTargetShopId = requiredShopId.trim();

    for (final doc in docs) {
      final rawData = doc.data;
      if (!_isProductActive(rawData)) {
        continue;
      }

      final shopId = _readShopId(rawData);
      if (shopId.isEmpty) {
        continue;
      }

      if (normalizedTargetShopId.isNotEmpty && shopId != normalizedTargetShopId) {
        continue;
      }

      if (nationwideShippingOnly && !_isEligibleForNationwideShipping(rawData)) {
        continue;
      }

      final mergedData = _mergeShopMetadata(rawData, publicShops[shopId]);
      final serviceType = _readServiceType(mergedData);
      if (normalizedTargetServiceType != null &&
          normalizedTargetServiceType.isNotEmpty &&
          _normalizeServiceType(serviceType) != normalizedTargetServiceType) {
        continue;
      }

      grouped.putIfAbsent(shopId, () => <PublicCatalogProduct>[]).add(
            PublicCatalogProduct(
              id: doc.id,
              shopId: shopId,
              shopName: _readShopName(mergedData),
              shopImageUrl: _readShopImage(mergedData),
              shopLatitude: _extractLatitude(mergedData),
              shopLongitude: _extractLongitude(mergedData),
              data: mergedData,
            ),
          );
    }

    return grouped.entries
        .map((entry) {
          final products = entry.value;
          if (products.isEmpty) {
            return null;
          }

          final first = products.first;
          final publicShopImage = publicShops[entry.key]?['shopImageUrl'];
          final shopImageUrl = _preferRegistrationImage(
            publicShopImage is String ? publicShopImage : null,
            first.shopImageUrl,
          );

          return PublicCatalogSection(
            shopId: entry.key,
            shopName: first.shopName,
            shopImageUrl: shopImageUrl,
            shopLatitude: first.shopLatitude,
            shopLongitude: first.shopLongitude,
            shopUpdatedAt: _readShopTimestamp(publicShops[entry.key]),
            shopDescription: _readShopDescription(publicShops[entry.key]),
            products: products
                .map(
                  (product) => PublicCatalogProduct(
                    id: product.id,
                    shopId: product.shopId,
                    shopName: product.shopName,
                    shopImageUrl: shopImageUrl,
                    shopLatitude: product.shopLatitude,
                    shopLongitude: product.shopLongitude,
                    data: product.data,
                  ),
                )
                .toList(growable: false),
          );
        })
        .whereType<PublicCatalogSection>()
        .toList(growable: false)
      ..sort(_compareCatalogSections);
  }

  static int _compareCatalogSections(
    PublicCatalogSection left,
    PublicCatalogSection right,
  ) {
    final leftAt = left.shopUpdatedAt;
    final rightAt = right.shopUpdatedAt;
    if (leftAt != null && rightAt != null) {
      final newestFirst = rightAt.compareTo(leftAt);
      if (newestFirst != 0) {
        return newestFirst;
      }
    } else if (leftAt != null) {
      return -1;
    } else if (rightAt != null) {
      return 1;
    }

    return (left.shopName ?? left.shopId).compareTo(
      right.shopName ?? right.shopId,
    );
  }

  static const String homeShelvesDocPath = 'platform_catalog/home_shelves';
  static const int homeShelfTargetCount = 12;

  static Stream<List<String>> streamFeaturedProductIds() {
    return FirebaseFirestore.instance
        .collection('platform_catalog')
        .doc('home_shelves')
        .snapshots()
        .map((snapshot) => _readFeaturedProductIds(snapshot.data()));
  }

  static List<String> _readFeaturedProductIds(Map<String, dynamic>? data) {
    final raw = data?['featuredProductIds'];
    if (raw is! List) {
      return const <String>[];
    }

    return raw
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  static Future<List<PublicCatalogProduct>> resolveProductsByIds(
    List<String> productIds, {
    Set<String> excludeIds = const <String>{},
  }) async {
    if (productIds.isEmpty) {
      return const <PublicCatalogProduct>[];
    }

    await _ensureCatalogAuth();
    await PublicCatalogLocalCache.ensureProductsHydrated();
    await PublicCatalogLocalCache.ensurePublicShopsHydrated();
    final publicShops = await _getPublicShops();

    final orderedIds = <String>[];
    final seen = <String>{};
    for (final id in productIds) {
      final normalized = id.trim();
      if (normalized.isEmpty ||
          seen.contains(normalized) ||
          excludeIds.contains(normalized)) {
        continue;
      }
      seen.add(normalized);
      orderedIds.add(normalized);
    }

    final productDataById = <String, Map<String, dynamic>>{};
    final missingIds = <String>[];

    for (final id in orderedIds) {
      final cached = PublicCatalogLocalCache.productsById[id];
      if (cached != null) {
        productDataById[id] = cached;
      } else {
        missingIds.add(id);
      }
    }

    for (var index = 0; index < missingIds.length; index += 30) {
      final chunk = missingIds.sublist(
        index,
        index + 30 > missingIds.length ? missingIds.length : index + 30,
      );
      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        productDataById[doc.id] = doc.data();
        PublicCatalogLocalCache.applyProductDoc(doc.id, doc.data());
      }
    }

    final results = <PublicCatalogProduct>[];
    for (final id in orderedIds) {
      final rawData = productDataById[id];
      if (rawData == null ||
          !_isProductActive(rawData) ||
          !_productHasDisplayImage(rawData)) {
        continue;
      }

      final product = _buildCatalogProduct(id, rawData, publicShops);
      if (product != null) {
        results.add(product);
      }
    }

    return results;
  }

  static Future<List<PublicCatalogProduct>> listRecentActiveProducts({
    int limit = 24,
    Set<String> excludeIds = const <String>{},
  }) async {
    await _ensureCatalogAuth();
    await PublicCatalogLocalCache.ensureProductsHydrated();
    await PublicCatalogLocalCache.ensurePublicShopsHydrated();
    final publicShops = await _getPublicShops();

    final candidates = PublicCatalogLocalCache.productsById.entries
        .where(
          (entry) =>
              !excludeIds.contains(entry.key) &&
              _isProductActive(entry.value) &&
              _productHasDisplayImage(entry.value),
        )
        .map(
          (entry) => _CatalogProductEntry(id: entry.key, data: entry.value),
        )
        .toList(growable: true)
      ..sort((left, right) {
        final leftAt = _readProductUpdatedAt(left.data);
        final rightAt = _readProductUpdatedAt(right.data);
        if (leftAt != null && rightAt != null) {
          return rightAt.compareTo(leftAt);
        }
        if (leftAt != null) {
          return -1;
        }
        if (rightAt != null) {
          return 1;
        }
        return left.id.compareTo(right.id);
      });

    final results = <PublicCatalogProduct>[];
    for (final candidate in candidates) {
      if (results.length >= limit) {
        break;
      }
      final product = _buildCatalogProduct(
        candidate.id,
        candidate.data,
        publicShops,
      );
      if (product != null) {
        results.add(product);
      }
    }

    return results;
  }

  static Future<List<PublicCatalogProduct>> listBestSellingProducts({
    int limit = 12,
    Set<String> excludeIds = const <String>{},
  }) async {
    await _ensureCatalogAuth();

    try {
      final statsSnapshot = await FirebaseFirestore.instance
          .collection('product_stats')
          .orderBy('soldCount', descending: true)
          .limit(limit * 3)
          .get();

      if (statsSnapshot.docs.isNotEmpty) {
        final ids = statsSnapshot.docs
            .map((doc) => doc.id)
            .where((id) => !excludeIds.contains(id))
            .toList(growable: false);
        final resolved = await resolveProductsByIds(ids, excludeIds: excludeIds);
        if (resolved.isNotEmpty) {
          return resolved.take(limit).toList(growable: false);
        }
      }
    } catch (_) {
      // Fall back to recently updated products when stats/index are unavailable.
    }

    return listRecentActiveProducts(limit: limit, excludeIds: excludeIds);
  }

  static Future<List<PublicCatalogProduct>> listActiveProductsForShop(
    String shopId,
  ) async {
    final normalizedShopId = shopId.trim();
    if (normalizedShopId.isEmpty) {
      return const <PublicCatalogProduct>[];
    }

    await _ensureCatalogAuth();
    await PublicCatalogLocalCache.ensureProductsHydrated();
    await PublicCatalogLocalCache.ensurePublicShopsHydrated();
    final publicShops = await _getPublicShops();

    final cached = PublicCatalogLocalCache.productsById.entries
        .where(
          (entry) =>
              _readShopId(entry.value) == normalizedShopId &&
              _isProductActive(entry.value) &&
              _productHasDisplayImage(entry.value),
        )
        .map(
          (entry) => _buildCatalogProduct(entry.key, entry.value, publicShops),
        )
        .whereType<PublicCatalogProduct>()
        .toList(growable: true);

    if (cached.isNotEmpty) {
      cached.sort((left, right) {
        final leftAt = _readProductUpdatedAt(left.data);
        final rightAt = _readProductUpdatedAt(right.data);
        if (leftAt != null && rightAt != null) {
          return rightAt.compareTo(leftAt);
        }
        if (leftAt != null) {
          return -1;
        }
        if (rightAt != null) {
          return 1;
        }
        return left.id.compareTo(right.id);
      });
      return cached;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('ownerUid', isEqualTo: normalizedShopId)
          .where('isActive', isEqualTo: true)
          .get();

      final results = <PublicCatalogProduct>[];
      for (final doc in snapshot.docs) {
        PublicCatalogLocalCache.applyProductDoc(doc.id, doc.data());
        final product = _buildCatalogProduct(doc.id, doc.data(), publicShops);
        if (product != null && _productHasDisplayImage(doc.data())) {
          results.add(product);
        }
      }

      results.sort((left, right) {
        final leftAt = _readProductUpdatedAt(left.data);
        final rightAt = _readProductUpdatedAt(right.data);
        if (leftAt != null && rightAt != null) {
          return rightAt.compareTo(leftAt);
        }
        return left.id.compareTo(right.id);
      });
      return results;
    } catch (_) {
      return const <PublicCatalogProduct>[];
    }
  }

  static PublicCatalogProduct? _buildCatalogProduct(
    String id,
    Map<String, dynamic> rawData,
    Map<String, Map<String, dynamic>> publicShops,
  ) {
    final shopId = _readShopId(rawData);
    if (shopId.isEmpty) {
      return null;
    }

    final mergedData = _mergeShopMetadata(rawData, publicShops[shopId]);
    final publicShopImage = publicShops[shopId]?['shopImageUrl'];
    final shopImageUrl = _preferRegistrationImage(
      publicShopImage is String ? publicShopImage : null,
      _readShopImage(mergedData),
    );

    return PublicCatalogProduct(
      id: id,
      shopId: shopId,
      shopName: _readShopName(mergedData),
      shopImageUrl: shopImageUrl,
      shopLatitude: _extractLatitude(mergedData),
      shopLongitude: _extractLongitude(mergedData),
      data: mergedData,
    );
  }

  static DateTime? _readProductUpdatedAt(Map<String, dynamic> data) {
    for (final key in <String>['updatedAt', 'createdAt']) {
      final raw = data[key];
      if (raw is Timestamp) {
        return raw.toDate();
      }
    }
    return null;
  }

  static const Set<String> homeRetailServiceTypes = <String>{
    'ร้านอาหาร',
    'ตลาด',
    'ร้านค้า',
    'ร้านขายยา',
  };

  static bool isHomeRetailCatalogProduct(PublicCatalogProduct product) {
    final normalized = _normalizeServiceType(_readServiceType(product.data));
    return homeRetailServiceTypes.contains(normalized);
  }

  static List<PublicCatalogProduct> filterHomeRetailProducts(
    List<PublicCatalogProduct> products,
  ) {
    return products
        .where(isHomeRetailCatalogProduct)
        .toList(growable: false);
  }

  static bool _productHasDisplayImage(Map<String, dynamic> data) {
    final thumbnails = data['thumbnailUrls'];
    if (thumbnails is List &&
        thumbnails.any((entry) => entry.toString().trim().isNotEmpty)) {
      return true;
    }

    final images = data['imageUrls'];
    if (images is List &&
        images.any((entry) => entry.toString().trim().isNotEmpty)) {
      return true;
    }

    for (final key in <String>['imageUrl', 'photoUrl', 'productImage']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return true;
      }
    }

    return false;
  }
}

DateTime? _readShopTimestamp(Map<String, dynamic>? publicShop) {
  if (publicShop == null || publicShop.isEmpty) {
    return null;
  }

  for (final key in <String>['updatedAt', 'createdAt']) {
    final raw = publicShop[key];
    if (raw is Timestamp) {
      return raw.toDate();
    }
  }

  return null;
}

String? _readShopDescription(Map<String, dynamic>? publicShop) {
  if (publicShop == null || publicShop.isEmpty) {
    return null;
  }

  for (final key in <String>[
    'description',
    'shopDescription',
    'about',
    'bio',
  ]) {
    final value = publicShop[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}

class _CatalogProductEntry {
  const _CatalogProductEntry({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

Map<String, dynamic> _mergeShopMetadata(
  Map<String, dynamic> productData,
  Map<String, dynamic>? publicShop,
) {
  if (publicShop == null || publicShop.isEmpty) {
    return productData;
  }

  final merged = Map<String, dynamic>.from(productData);

  void fillIfMissing(String key, dynamic value) {
    final current = merged[key];
    if (current == null || current.toString().trim().isEmpty) {
      if (value != null && value.toString().trim().isNotEmpty) {
        merged[key] = value;
      }
    }
  }

  fillIfMissing('serviceType', publicShop['serviceType']);
  fillIfMissing('service_type', publicShop['service_type']);
  fillIfMissing('shopName', publicShop['shopName']);
  fillIfMissing('name', publicShop['name']);
  fillIfMissing('shopImageUrl', publicShop['shopImageUrl']);
  fillIfMissing('imageUrl', publicShop['imageUrl']);
  fillIfMissing('shopLatitude', publicShop['shopLatitude']);
  fillIfMissing('shopLongitude', publicShop['shopLongitude']);
  fillIfMissing('latitude', publicShop['latitude']);
  fillIfMissing('longitude', publicShop['longitude']);
  fillIfMissing('location', publicShop['location']);
  fillIfMissing('shopLocation', publicShop['shopLocation']);

  return merged;
}

double? _extractLatitude(Map<String, dynamic> data) {
  final direct =
      _toDouble(data['shopLatitude']) ??
      _toDouble(data['latitude']) ??
      _toDouble(data['lat']);
  if (direct != null) {
    return direct;
  }

  final location =
      data['shopLocation'] ??
      data['location'] ??
      data['geoPoint'] ??
      data['coordinates'];
  if (location is GeoPoint) {
    return location.latitude;
  }
  if (location is Map) {
    return _toDouble(location['latitude']) ?? _toDouble(location['lat']);
  }

  return null;
}

double? _extractLongitude(Map<String, dynamic> data) {
  final direct =
      _toDouble(data['shopLongitude']) ??
      _toDouble(data['longitude']) ??
      _toDouble(data['lng']) ??
      _toDouble(data['lon']) ??
      _toDouble(data['long']);
  if (direct != null) {
    return direct;
  }

  final location =
      data['shopLocation'] ??
      data['location'] ??
      data['geoPoint'] ??
      data['coordinates'];
  if (location is GeoPoint) {
    return location.longitude;
  }
  if (location is Map) {
    return _toDouble(location['longitude']) ??
        _toDouble(location['lng']) ??
        _toDouble(location['lon']) ??
        _toDouble(location['long']);
  }

  return null;
}

double? _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

String? _preferRegistrationImage(
  String? registrationImageUrl,
  String? productImageUrl,
) {
  final registration = registrationImageUrl?.trim();
  if (registration != null && registration.isNotEmpty) {
    return registration;
  }

  final product = productImageUrl?.trim();
  if (product != null && product.isNotEmpty) {
    return product;
  }

  return null;
}

bool _isProductActive(Map<String, dynamic> data) {
  final raw = data['isActive'] ?? data['active'] ?? data['is_open'];
  if (raw is bool) {
    return raw;
  }
  if (raw is num) {
    return raw != 0;
  }
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }

  return false;
}

bool _isEligibleForNationwideShipping(Map<String, dynamic> data) {
  if (!_readBoolField(data['canShipNationwide'])) {
    return false;
  }

  final reason = (data['nationwideShippingReason'] ?? '').toString().trim();
  return reason.isNotEmpty;
}

bool _readBoolField(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

String _readShopId(Map<String, dynamic> data) {
  final candidates = <Object?>[
    data['ownerUid'],
    data['ownerId'],
    data['owner_id'],
    data['shopId'],
    data['shop_id'],
    data['shopOwnerId'],
    data['shopOwnerUid'],
    data['merchantId'],
    data['merchantUid'],
    data['owner'],
    data['uid'],
  ];

  for (final candidate in candidates) {
    final value = candidate?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

String? _readShopName(Map<String, dynamic> data) {
  final candidates = <Object?>[
    data['shopName'],
    data['name'],
    data['displayName'],
    data['businessName'],
    data['storeName'],
  ];

  for (final candidate in candidates) {
    final value = candidate?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}

String? _readShopImage(Map<String, dynamic> data) {
  final candidates = <Object?>[
    data['shopImageUrl'],
    data['imageUrl'],
    data['photoUrl'],
    data['logoUrl'],
  ];

  for (final candidate in candidates) {
    final value = candidate?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}

String _readServiceType(Map<String, dynamic> data) {
  final candidates = <Object?>[
    data['serviceType'],
    data['service_type'],
    data['shopServiceType'],
    data['shop_type'],
    data['storeType'],
    data['store_type'],
    data['businessType'],
    data['businessCategory'],
    data['business_category'],
    data['registrationType'],
    data['registration_type'],
    data['category'],
    data['productCategory'],
    data['type'],
  ];

  for (final candidate in candidates) {
    final value = candidate?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

String _normalizeServiceType(String rawServiceType) {
  final normalized = rawServiceType.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }

  if (normalized.contains('ร้านอาหาร') ||
      normalized.contains('restaurant') ||
      normalized == 'food') {
    return 'ร้านอาหาร';
  }
  if (normalized.contains('ตลาด') || normalized.contains('market')) {
    return 'ตลาด';
  }
  if (normalized.contains('ยา') ||
      normalized.contains('pharmacy') ||
      normalized.contains('drugstore') ||
      normalized.contains('drug_store')) {
    return 'ร้านขายยา';
  }
  if (normalized.contains('ร้านค้า') ||
      normalized.contains('shop') ||
      normalized.contains('store') ||
      normalized.contains('retail') ||
      normalized.contains('mini_mart') ||
      normalized.contains('mini mart') ||
      normalized.contains('ของชำ') ||
      normalized.contains('ร้านชำ')) {
    return 'ร้านค้า';
  }

  switch (normalized) {
    case 'restaurant':
    case 'food':
    case 'ร้านอาหาร':
      return 'ร้านอาหาร';
    case 'market':
    case 'fresh_market':
    case 'fresh market':
    case 'ตลาดสด':
    case 'ตลาด':
      return 'ตลาด';
    case 'shop':
    case 'store':
    case 'stores':
    case 'general store':
    case 'general_store':
    case 'mini mart':
    case 'mini_mart':
    case 'retail':
    case 'retailer':
    case 'ร้านชำ':
    case 'ของชำ':
    case 'ร้านค้า':
    case 'shop_registrations':
      return 'ร้านค้า';
    case 'pharmacy':
    case 'drugstore':
    case 'drug_store':
    case 'ร้านขายยา':
      return 'ร้านขายยา';
    default:
      return rawServiceType.trim();
  }
}
