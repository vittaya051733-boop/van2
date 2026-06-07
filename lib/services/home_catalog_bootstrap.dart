import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../public_catalog_service.dart';
import '../public_catalog_local_cache.dart';
import 'app_image_prefetch.dart';

/// Preloads featured home shelf + thumbnails during splash so home paints faster.
class HomeCatalogBootstrap {
  HomeCatalogBootstrap._();

  static const String _featuredSnapshotKey = 'van2_home_featured_snapshot_v1';

  static List<PublicCatalogProduct>? _memoryFeatured;
  static bool _warmComplete = false;
  static bool _warmStarted = false;

  static List<PublicCatalogProduct>? peekFeaturedShelf() {
    final cached = _memoryFeatured;
    if (cached == null || cached.isEmpty) {
      return null;
    }
    return List<PublicCatalogProduct>.from(cached);
  }

  static void updateFeaturedShelf(List<PublicCatalogProduct> products) {
    if (products.isEmpty) {
      return;
    }
    _memoryFeatured = List<PublicCatalogProduct>.from(products);
    unawaited(_persistFeaturedSnapshot(products));
  }

  static bool get warmComplete => _warmComplete;

  /// Call from [main] or splash — runs in parallel with startup.
  static Future<void> warmForHome() async {
    if (_warmStarted) {
      return;
    }
    _warmStarted = true;
    try {
      await PublicCatalogLocalCache.ensureProductsHydrated();
      await PublicCatalogLocalCache.ensurePublicShopsHydrated();

      final prefsSnapshot = await _loadFeaturedSnapshotFromPrefs();
      if (prefsSnapshot != null && prefsSnapshot.isNotEmpty) {
        _memoryFeatured = prefsSnapshot;
        await AppImagePrefetch.prefetchProductsImmediate(
          prefsSnapshot,
          limit: 12,
        );
      }

      await _ensureAuth();
      final featuredIds = await PublicCatalogService.fetchFeaturedProductIds();
      if (featuredIds.isEmpty) {
        _warmComplete = true;
        return;
      }

      final resolved = await PublicCatalogService.resolveProductsByIds(
        featuredIds,
      );
      if (resolved.isEmpty) {
        _warmComplete = true;
        return;
      }

      final shelf = resolved
          .take(PublicCatalogService.homeShelfTargetCount)
          .toList(growable: false);
      _memoryFeatured = shelf;
      await _persistFeaturedSnapshot(shelf);
      await AppImagePrefetch.prefetchProductsImmediate(
        shelf,
        limit: 12,
      );
    } catch (_) {
      // Home stream still loads from network.
    } finally {
      _warmComplete = true;
      AppImagePrefetch.markBootstrapWarmDone();
    }
  }

  static Future<void> _ensureAuth() async {
    var user = FirebaseAuth.instance.currentUser;
    user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
    await user?.getIdToken();
  }

  static Future<List<PublicCatalogProduct>?> _loadFeaturedSnapshotFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_featuredSnapshotKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      final products = <PublicCatalogProduct>[];
      for (final entry in decoded) {
        if (entry is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(entry);
        final id = (map['id'] ?? '').toString();
        final shopId = (map['shopId'] ?? '').toString();
        if (id.isEmpty || shopId.isEmpty) {
          continue;
        }
        final dataRaw = map['data'];
        products.add(
          PublicCatalogProduct(
            id: id,
            shopId: shopId,
            shopName: map['shopName']?.toString(),
            shopImageUrl: map['shopImageUrl']?.toString(),
            shopLatitude: (map['shopLatitude'] as num?)?.toDouble(),
            shopLongitude: (map['shopLongitude'] as num?)?.toDouble(),
            data: dataRaw is Map
                ? Map<String, dynamic>.from(dataRaw)
                : <String, dynamic>{},
          ),
        );
      }
      return products.isEmpty ? null : products;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persistFeaturedSnapshot(
    List<PublicCatalogProduct> products,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = products
          .map(
            (product) => <String, dynamic>{
              'id': product.id,
              'shopId': product.shopId,
              'shopName': product.shopName,
              'shopImageUrl': product.shopImageUrl,
              'shopLatitude': product.shopLatitude,
              'shopLongitude': product.shopLongitude,
              'data': product.data,
            },
          )
          .toList(growable: false);
      await prefs.setString(_featuredSnapshotKey, jsonEncode(payload));
    } catch (_) {
      // Non-fatal.
    }
  }
}
