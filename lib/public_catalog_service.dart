import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'utils/shop_profile_resolver.dart';

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
  });

  final String shopId;
  final String? shopName;
  final String? shopImageUrl;
  final double? shopLatitude;
  final double? shopLongitude;
  final List<PublicCatalogProduct> products;
}

class _ResolvedShopProfile {
  const _ResolvedShopProfile({
    this.name,
    this.imageUrl,
  });

  final String? name;
  final String? imageUrl;
}

class PublicCatalogService {
  PublicCatalogService._();

  static const List<String> _allRegistrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
  ];

  static Stream<List<PublicCatalogSection>> streamAllSections() {
    final query = FirebaseFirestore.instance
        .collection('products')
        .where('isActive', isEqualTo: true);

    return _streamSectionsFromQuery(query).map(
      (sections) => sections.toList()
        ..sort(
          (left, right) => (left.shopName ?? left.shopId).compareTo(
            right.shopName ?? right.shopId,
          ),
        ),
    );
  }

  static Stream<List<PublicCatalogSection>> streamSectionsByServiceType(String serviceType) {
    final query = FirebaseFirestore.instance
        .collection('products')
        .where('serviceType', isEqualTo: serviceType)
        .where('isActive', isEqualTo: true);

    return _streamSectionsFromQuery(query);
  }

  static Stream<List<PublicCatalogSection>> streamSectionsByShopId(String shopId) {
    final normalizedShopId = shopId.trim();
    if (normalizedShopId.isEmpty) {
      return Stream<List<PublicCatalogSection>>.value(const <PublicCatalogSection>[]);
    }

    final query = FirebaseFirestore.instance
        .collection('products')
        .where('ownerUid', isEqualTo: normalizedShopId)
        .where('isActive', isEqualTo: true);

    return _streamSectionsFromQuery(query);
  }

  static Stream<List<PublicCatalogSection>> _streamSectionsFromQuery(
    Query<Map<String, dynamic>> query,
  ) {
    return query.snapshots().asyncMap((snapshot) async {
      final Map<String, List<PublicCatalogProduct>> grouped = <String, List<PublicCatalogProduct>>{};
      final Map<String, String> serviceTypeByShopId = <String, String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final shopId = ((data['ownerUid'] as String?) ?? '').trim();
        if (shopId.isEmpty) continue;

        final serviceType = (data['serviceType'] as String?)?.trim();
        if (serviceType != null && serviceType.isNotEmpty) {
          serviceTypeByShopId.putIfAbsent(shopId, () => serviceType);
        }

        final product = PublicCatalogProduct(
          id: doc.id,
          shopId: shopId,
          shopName: _readShopName(data),
          shopImageUrl: _readShopImageUrl(data),
          shopLatitude: _extractLatitude(data),
          shopLongitude: _extractLongitude(data),
          data: data,
        );

        grouped.putIfAbsent(shopId, () => <PublicCatalogProduct>[]).add(product);
      }

      final registrationProfiles = await _fetchRegistrationProfiles(serviceTypeByShopId);

      return grouped.entries
          .map((entry) {
            final products = entry.value;
            if (products.isEmpty) return null;
            final first = products.first;
            final registrationProfile = registrationProfiles[entry.key];
            final shopName = _preferResolvedValue(
              registrationProfile?.name,
              first.shopName,
            );
            final shopImageUrl = _preferResolvedValue(
              registrationProfile?.imageUrl,
              first.shopImageUrl,
            );
            final mappedProducts = products
                .map(
                  (product) => PublicCatalogProduct(
                    id: product.id,
                    shopId: product.shopId,
                    shopName: shopName,
                    shopImageUrl: shopImageUrl,
                    shopLatitude: product.shopLatitude,
                    shopLongitude: product.shopLongitude,
                    data: product.data,
                  ),
                )
                .toList(growable: false);

            return PublicCatalogSection(
              shopId: entry.key,
              shopName: shopName,
              shopImageUrl: shopImageUrl,
              shopLatitude: first.shopLatitude,
              shopLongitude: first.shopLongitude,
              products: mappedProducts,
            );
          })
          .whereType<PublicCatalogSection>()
          .toList(growable: false);
    });
  }

  static Future<Map<String, _ResolvedShopProfile>> _fetchRegistrationProfiles(
    Map<String, String> serviceTypeByShopId,
  ) async {
    if (serviceTypeByShopId.isEmpty) {
      return const <String, _ResolvedShopProfile>{};
    }

    final Map<String, Set<String>> shopIdsByCollection = <String, Set<String>>{};
    for (final entry in serviceTypeByShopId.entries) {
      final collection = _registrationCollectionForServiceType(entry.value);
      if (collection != null) {
        shopIdsByCollection.putIfAbsent(collection, () => <String>{}).add(entry.key);
      } else {
        for (final fallbackCollection in _allRegistrationCollections) {
          shopIdsByCollection.putIfAbsent(fallbackCollection, () => <String>{}).add(entry.key);
        }
      }
    }

    final List<Future<Map<String, _ResolvedShopProfile>>> tasks = shopIdsByCollection.entries
        .map(
          (entry) => _fetchProfilesFromCollection(
            collection: entry.key,
            shopIds: entry.value.toList(growable: false),
          ),
        )
        .toList(growable: false);

    final results = await Future.wait(tasks);
    final merged = <String, _ResolvedShopProfile>{};
    for (final result in results) {
      for (final entry in result.entries) {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return merged;
  }

  static Future<Map<String, _ResolvedShopProfile>> _fetchProfilesFromCollection({
    required String collection,
    required List<String> shopIds,
  }) async {
    if (shopIds.isEmpty) {
      return const <String, _ResolvedShopProfile>{};
    }

    final ref = FirebaseFirestore.instance.collection(collection);
    final results = <String, _ResolvedShopProfile>{};

    for (final chunk in _chunkIds(shopIds, 10)) {
      final ownerQuery = await ref.where('ownerId', whereIn: chunk).get();
      for (final doc in ownerQuery.docs) {
        final ownerId = (doc.data()['ownerId'] as String?)?.trim();
        if (ownerId == null || ownerId.isEmpty) {
          continue;
        }
        final profile = _buildResolvedShopProfile(doc.data());
        if (profile == null) {
          continue;
        }
        results.putIfAbsent(ownerId, () => profile);
      }

      final docIdQuery = await ref.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in docIdQuery.docs) {
        final shopId = doc.id.trim();
        if (shopId.isEmpty) {
          continue;
        }
        final profile = _buildResolvedShopProfile(doc.data());
        if (profile == null) {
          continue;
        }
        results.putIfAbsent(shopId, () => profile);
      }
    }

    return results;
  }

  static Iterable<List<String>> _chunkIds(List<String> values, int size) sync* {
    for (var index = 0; index < values.length; index += size) {
      final end = index + size > values.length ? values.length : index + size;
      yield values.sublist(index, end);
    }
  }

  static List<PublicCatalogProduct> _mapProducts({
    required String shopId,
    required String? shopName,
    required String? shopImageUrl,
    required double? shopLatitude,
    required double? shopLongitude,
    required List<String> orderedIds,
    required Map<String, Map<String, dynamic>> docsById,
  }) {
    if (orderedIds.isEmpty || docsById.isEmpty) {
      return const <PublicCatalogProduct>[];
    }

    return orderedIds
        .map((id) {
          final data = docsById[id];
          if (data == null) return null;
          final ownerUid = (data['ownerUid'] as String?)?.trim();
          if (ownerUid != shopId) return null;

          return PublicCatalogProduct(
            id: id,
            shopId: shopId,
            shopName: shopName,
            shopImageUrl: shopImageUrl,
            shopLatitude: shopLatitude,
            shopLongitude: shopLongitude,
            data: data,
          );
        })
        .whereType<PublicCatalogProduct>()
        .toList(growable: false);
  }
}

_ResolvedShopProfile? _buildResolvedShopProfile(Map<String, dynamic> data) {
  final imageUrl = _readShopImageUrl(data);
  final name = _readShopName(data);
  if (imageUrl == null && name == null) {
    return null;
  }
  return _ResolvedShopProfile(name: name, imageUrl: imageUrl);
}

String? _readShopName(Map<String, dynamic>? data) {
  final resolved = ShopProfileResolver.resolveName(data);
  if (resolved != null && resolved.trim().isNotEmpty) {
    return resolved.trim();
  }

  final shopName = (data?['shopName'] as String?)?.trim();
  if (shopName != null && shopName.isNotEmpty) {
    return shopName;
  }

  return null;
}

String? _readShopImageUrl(Map<String, dynamic>? data) {
  final resolved = ShopProfileResolver.resolveImageUrl(data);
  if (resolved != null && resolved.trim().isNotEmpty) {
    return resolved.trim();
  }

  final shopImageUrl = (data?['shopImageUrl'] as String?)?.trim();
  if (shopImageUrl != null && shopImageUrl.isNotEmpty) {
    return shopImageUrl;
  }

  return null;
}

double? _extractLatitude(Map<String, dynamic> data) {
  final direct = _toDouble(data['shopLatitude']) ?? _toDouble(data['latitude']) ?? _toDouble(data['lat']);
  if (direct != null) {
    return direct;
  }

  final location = data['shopLocation'] ?? data['location'] ?? data['geoPoint'] ?? data['coordinates'];
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

  final location = data['shopLocation'] ?? data['location'] ?? data['geoPoint'] ?? data['coordinates'];
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

String? _registrationCollectionForServiceType(String serviceType) {
  final normalized = serviceType.trim();
  switch (normalized) {
    case 'ตลาด':
      return 'market_registrations';
    case 'ร้านค้า':
      return 'shop_registrations';
    case 'ร้านอาหาร':
      return 'restaurant_registrations';
    case 'ร้านขายยา':
      return 'pharmacy_registrations';
    default:
      return null;
  }
}

String? _preferResolvedValue(String? primary, String? fallback) {
  final primaryValue = primary?.trim();
  if (primaryValue != null && primaryValue.isNotEmpty) {
    return primaryValue;
  }

  final fallbackValue = fallback?.trim();
  if (fallbackValue != null && fallbackValue.isNotEmpty) {
    return fallbackValue;
  }

  return null;
}