import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

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

class PublicCatalogService {
  PublicCatalogService._();

  static Stream<List<PublicCatalogSection>> streamAllSections() {
    final query = FirebaseFirestore.instance.collection('products');

    return _streamSectionsFromQuery(query, '', '').map(
      (sections) => sections.toList()
        ..sort(
          (left, right) => (left.shopName ?? left.shopId).compareTo(
            right.shopName ?? right.shopId,
          ),
        ),
    );
  }

  static Stream<List<PublicCatalogSection>> streamSectionsByServiceType(String serviceType) {
    final query = FirebaseFirestore.instance.collection('products');

    return _streamSectionsFromQuery(query, serviceType, '');
  }

  static Stream<List<PublicCatalogSection>> streamSectionsByShopId(String shopId) {
    final normalizedShopId = shopId.trim();
    if (normalizedShopId.isEmpty) {
      return Stream<List<PublicCatalogSection>>.value(const <PublicCatalogSection>[]);
    }

    final query = FirebaseFirestore.instance.collection('products');

    return _streamSectionsFromQuery(query, '', normalizedShopId);
  }

  static Stream<List<PublicCatalogSection>> _streamSectionsFromQuery(
    Query<Map<String, dynamic>> query,
    String requiredServiceType,
    String requiredShopId,
  ) {
    return query.snapshots().asyncMap((snapshot) async {
      final Map<String, List<PublicCatalogProduct>> grouped = <String, List<PublicCatalogProduct>>{};
      final Map<String, String> serviceTypeByShopId = <String, String>{};
      final normalizedTargetServiceType = requiredServiceType.trim().isEmpty
          ? null
          : _normalizeServiceType(requiredServiceType);
      final normalizedTargetShopId = requiredShopId.trim();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (!_isProductActive(data)) continue;

        final shopId = _readShopId(data);
        if (shopId.isEmpty) continue;

        if (normalizedTargetShopId.isNotEmpty && shopId != normalizedTargetShopId) {
          continue;
        }

        final serviceType = _readServiceType(data);
        if (normalizedTargetServiceType != null &&
            normalizedTargetServiceType.isNotEmpty &&
            _normalizeServiceType(serviceType) != normalizedTargetServiceType) {
          continue;
        }

        if (serviceType.isNotEmpty) {
          serviceTypeByShopId.putIfAbsent(shopId, () => serviceType);
        }

        final product = PublicCatalogProduct(
          id: doc.id,
          shopId: shopId,
          shopName: _readShopName(data),
          shopImageUrl: _readShopImage(data),
          shopLatitude: _extractLatitude(data),
          shopLongitude: _extractLongitude(data),
          data: data,
        );

        grouped.putIfAbsent(shopId, () => <PublicCatalogProduct>[]).add(product);
      }

      const registrationImages = <String, String>{};

      return grouped.entries
          .map((entry) {
            final products = entry.value;
            if (products.isEmpty) return null;
            final first = products.first;
            final shopImageUrl = _preferRegistrationImage(
              registrationImages[entry.key],
              first.shopImageUrl,
            );
            final mappedProducts = products
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
                .toList(growable: false);

            return PublicCatalogSection(
              shopId: entry.key,
              shopName: first.shopName,
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

String? _preferRegistrationImage(String? registrationImageUrl, String? productImageUrl) {
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

  // Require explicit active=true for customer catalog visibility.
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
    data['business_type'],
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

  if (normalized.contains('ร้านอาหาร') || normalized.contains('restaurant') || normalized == 'food') {
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