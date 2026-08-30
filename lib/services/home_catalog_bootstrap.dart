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
  static const String _bestSellingSnapshotKey =
      'van2_home_best_selling_snapshot_v1';
  static const String _personalizedSnapshotKey =
      'van2_home_personalized_snapshot_v1';

  static List<PublicCatalogProduct>? _memoryFeatured;
  static List<PublicCatalogProduct>? _memoryBestSelling;
  static List<PublicCatalogProduct>? _memoryPersonalized;
  static bool _warmComplete = false;
  static bool _warmStarted = false;
  static bool _snapshotsHydrated = false;

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

  static List<PublicCatalogProduct>? peekBestSellingShelf() {
    final cached = _memoryBestSelling;
    if (cached == null || cached.isEmpty) {
      return null;
    }
    return List<PublicCatalogProduct>.from(cached);
  }

  static void updateBestSellingShelf(List<PublicCatalogProduct> products) {
    if (products.isEmpty) {
      return;
    }
    _memoryBestSelling = List<PublicCatalogProduct>.from(products);
    unawaited(_persistBestSellingSnapshot(products));
  }

  static List<PublicCatalogProduct>? peekPersonalizedShelf() {
    final cached = _memoryPersonalized;
    if (cached == null || cached.isEmpty) {
      return null;
    }
    return List<PublicCatalogProduct>.from(cached);
  }

  static void updatePersonalizedShelf(List<PublicCatalogProduct> products) {
    if (products.isEmpty) {
      return;
    }
    _memoryPersonalized = List<PublicCatalogProduct>.from(products);
    unawaited(_persistPersonalizedSnapshot(products));
  }

  static bool get warmComplete => _warmComplete;

  /// Load last home shelf snapshots from disk before first frame.
  static Future<void> hydrateShelfSnapshotsFromDisk() async {
    if (_snapshotsHydrated) {
      return;
    }
    _snapshotsHydrated = true;

    if (_memoryFeatured == null || _memoryFeatured!.isEmpty) {
      final featuredSnapshot = await _loadFeaturedSnapshotFromPrefs();
      if (featuredSnapshot != null && featuredSnapshot.isNotEmpty) {
        _memoryFeatured = featuredSnapshot;
      }
    }

    if (_memoryBestSelling == null || _memoryBestSelling!.isEmpty) {
      final bestSellingSnapshot = await _loadBestSellingSnapshotFromPrefs();
      if (bestSellingSnapshot != null && bestSellingSnapshot.isNotEmpty) {
        _memoryBestSelling = bestSellingSnapshot;
      }
    }

    if (_memoryPersonalized == null || _memoryPersonalized!.isEmpty) {
      final personalizedSnapshot = await _loadPersonalizedSnapshotFromPrefs();
      if (personalizedSnapshot != null && personalizedSnapshot.isNotEmpty) {
        _memoryPersonalized = personalizedSnapshot;
      }
    }

    final secondaryImages = <PublicCatalogProduct>[
      ...?_memoryBestSelling,
      ...?_memoryPersonalized,
    ];
    if (secondaryImages.isNotEmpty) {
      AppImagePrefetch.scheduleProductsPrefetch(
        secondaryImages,
        limit: 24,
        dedupeKey: 'home-secondary-snapshot',
        delayMs: 1200,
      );
    }
  }

  /// Call from [main] or splash — runs in parallel with startup.
  static Future<void> warmForHome() async {
    if (_warmStarted) {
      return;
    }
    _warmStarted = true;
    try {
      if (!_snapshotsHydrated) {
        await hydrateShelfSnapshotsFromDisk();
      }
      await PublicCatalogLocalCache.ensureProductsHydrated();
      await PublicCatalogLocalCache.ensurePublicShopsHydrated();

      if (_memoryFeatured == null || _memoryFeatured!.isEmpty) {
        final prefsSnapshot = await _loadFeaturedSnapshotFromPrefs();
        if (prefsSnapshot != null && prefsSnapshot.isNotEmpty) {
          _memoryFeatured = prefsSnapshot;
          await AppImagePrefetch.prefetchProductsImmediate(
            prefsSnapshot,
            limit: 12,
          );
        }
      }

      if (_memoryBestSelling == null || _memoryBestSelling!.isEmpty) {
        final bestSellingSnapshot = await _loadBestSellingSnapshotFromPrefs();
        if (bestSellingSnapshot != null && bestSellingSnapshot.isNotEmpty) {
          _memoryBestSelling = bestSellingSnapshot;
        }
      }

      if (_memoryPersonalized == null || _memoryPersonalized!.isEmpty) {
        final personalizedSnapshot = await _loadPersonalizedSnapshotFromPrefs();
        if (personalizedSnapshot != null && personalizedSnapshot.isNotEmpty) {
          _memoryPersonalized = personalizedSnapshot;
        }
      }

      await _ensureAuth();
      unawaited(_warmBestSellingShelf());
      unawaited(_warmPersonalizedShelf());
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

  static Future<void> _warmBestSellingShelf() async {
    try {
      final products = await PublicCatalogService.listBestSellingProducts(
        limit: PublicCatalogService.homeShelfTargetCount,
      );
      if (products.isEmpty) {
        return;
      }
      updateBestSellingShelf(products);
      await AppImagePrefetch.prefetchProductsImmediate(
        products,
        limit: 12,
      );
    } catch (_) {
      // Home shelves still load from network.
    }
  }

  static Future<void> _warmPersonalizedShelf() async {
    try {
      final products = await PublicCatalogService.listRecentActiveProducts(
        limit: PublicCatalogService.homeShelfTargetCount,
      );
      if (products.isEmpty) {
        return;
      }
      updatePersonalizedShelf(products);
      await AppImagePrefetch.prefetchProductsImmediate(
        products,
        limit: 12,
      );
    } catch (_) {
      // Home shelves still load from network.
    }
  }

  static Future<void> _ensureAuth() async {
    var user = FirebaseAuth.instance.currentUser;
    user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
    await user?.getIdToken();
  }

  static Future<List<PublicCatalogProduct>?> _loadFeaturedSnapshotFromPrefs() async {
    return _loadShelfSnapshotFromPrefs(_featuredSnapshotKey);
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

  static Future<List<PublicCatalogProduct>?> _loadBestSellingSnapshotFromPrefs() async {
    return _loadShelfSnapshotFromPrefs(_bestSellingSnapshotKey);
  }

  static Future<List<PublicCatalogProduct>?> _loadPersonalizedSnapshotFromPrefs() async {
    return _loadShelfSnapshotFromPrefs(_personalizedSnapshotKey);
  }

  static Future<void> _persistBestSellingSnapshot(
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
      await prefs.setString(_bestSellingSnapshotKey, jsonEncode(payload));
    } catch (_) {
      // Non-fatal.
    }
  }

  static Future<void> _persistPersonalizedSnapshot(
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
      await prefs.setString(_personalizedSnapshotKey, jsonEncode(payload));
    } catch (_) {
      // Non-fatal.
    }
  }

  static Future<List<PublicCatalogProduct>?> _loadShelfSnapshotFromPrefs(
    String key,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
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
}
