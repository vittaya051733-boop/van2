import 'dart:async';

import '../public_catalog_local_cache.dart';
import '../public_catalog_service.dart';
import '../utils/app_image_cache.dart';
import '../utils/catalog_product_image_url.dart';
import 'video_prefetch_service.dart';

/// Warms catalog/list thumbnails on disk (shared cache across all van2 screens).
class AppImagePrefetch {
  AppImagePrefetch._();

  static const int defaultPrefetchCount = 24;
  static const int priorityPrefetchCount = 16;
  static const int catalogImmediatePrefetchCount = 20;
  static const int bootstrapImagesPerQuickAction = 10;
  static const int onTapPrefetchBatch = 24;

  static const List<String> quickActionServiceTypes = <String>[
    'ร้านอาหาร',
    'ตลาด',
    'ร้านค้า',
    'ร้านขายยา',
  ];

  static final Set<String> _completedUrls = <String>{};
  static final Set<String> _inFlight = <String>{};
  static bool _warmStarted = false;
  static bool _bootstrapWarmDone = false;
  static bool _quickActionsBootstrapDone = false;
  static final Set<String> _scheduledKeys = <String>{};
  static final Map<String, int> _categoryPrefetchOffsets = <String, int>{};

  static void markBootstrapWarmDone() {
    _bootstrapWarmDone = true;
  }

  static String serviceTypeKey(String serviceType) => 'service:$serviceType';

  static const String nationwideKey = 'nationwide';

  static List<PublicCatalogProduct> collectProductsFromSections(
    List<PublicCatalogSection> sections, {
    int limit = defaultPrefetchCount,
  }) {
    final products = <PublicCatalogProduct>[];
    for (final section in sections) {
      for (final product in section.products) {
        products.add(product);
        if (products.length >= limit) {
          return products;
        }
      }
    }
    return products;
  }

  static List<String> collectProductImageUrls(
    List<PublicCatalogProduct> products, {
    int limit = defaultPrefetchCount,
    int offset = 0,
  }) {
    final urls = <String>[];
    final seen = <String>{};
    var skipped = 0;
    for (final product in products) {
      final productUrls = readCatalogProductImageUrls(product.data);
      if (productUrls.isEmpty) {
        continue;
      }
      if (skipped < offset) {
        skipped += 1;
        for (final url in productUrls) {
          seen.add(url);
        }
        continue;
      }
      for (final raw in productUrls) {
        final url = raw.trim();
        if (url.isEmpty || seen.contains(url)) {
          continue;
        }
        seen.add(url);
        urls.add(url);
        if (urls.length >= limit) {
          return urls;
        }
      }
    }
    return urls;
  }

  static List<String> collectImageUrls(
    Iterable<String?> candidates, {
    int limit = defaultPrefetchCount,
  }) {
    final urls = <String>[];
    final seen = <String>{};
    for (final raw in candidates) {
      if (urls.length >= limit) {
        break;
      }
      final url = raw?.trim();
      if (url == null || url.isEmpty || seen.contains(url)) {
        continue;
      }
      seen.add(url);
      urls.add(url);
    }
    return urls;
  }

  static Future<void> prefetchProductsImmediate(
    List<PublicCatalogProduct> products, {
    int limit = priorityPrefetchCount,
    int parallel = 6,
    int offset = 0,
  }) {
    return prefetchUrls(
      collectProductImageUrls(products, limit: limit, offset: offset),
      awaitPriority: true,
      parallel: parallel,
    );
  }

  /// 10 thumbnails per quick-action category before first screen paints.
  static Future<void> warmBootstrapQuickActionCategories() async {
    if (_quickActionsBootstrapDone) {
      return;
    }
    _quickActionsBootstrapDone = true;
    await PublicCatalogLocalCache.ensureProductsHydrated();
    await PublicCatalogLocalCache.ensurePublicShopsHydrated();

    await Future.wait<void>(<Future<void>>[
      for (final serviceType in quickActionServiceTypes)
        _warmBootstrapCategory(
          key: serviceTypeKey(serviceType),
          sectionsLoader: () => PublicCatalogService.sectionsFromLocalCache(
            serviceType: serviceType,
          ),
        ),
      _warmBootstrapCategory(
        key: nationwideKey,
        sectionsLoader: () => PublicCatalogService.sectionsFromLocalCache(
          nationwideShippingOnly: true,
        ),
      ),
    ], eagerError: false);
  }

  static Future<void> _warmBootstrapCategory({
    required String key,
    required Future<List<PublicCatalogSection>> Function() sectionsLoader,
  }) async {
    try {
      final sections = await sectionsLoader();
      if (sections.isEmpty) {
        return;
      }
      final products = collectProductsFromSections(
        sections,
        limit: bootstrapImagesPerQuickAction * 3,
      );
      await prefetchProductsImmediate(
        products,
        limit: bootstrapImagesPerQuickAction,
        parallel: 4,
      );
      _categoryPrefetchOffsets[key] = bootstrapImagesPerQuickAction;

      final shopUrl = sections.first.shopImageUrl?.trim();
      if (shopUrl != null && shopUrl.isNotEmpty) {
        await prefetchUrls(<String>[shopUrl], awaitPriority: true, parallel: 1);
      }
    } catch (_) {
      // UI still loads images on demand.
    }
  }

  static Future<void> continueWarmForServiceType(String serviceType) async {
    await _continueWarmCategory(
      key: serviceTypeKey(serviceType),
      sectionsLoader: () => PublicCatalogService.sectionsFromLocalCache(
        serviceType: serviceType,
      ),
    );
  }

  static Future<void> continueWarmNationwide() async {
    await _continueWarmCategory(
      key: nationwideKey,
      sectionsLoader: () => PublicCatalogService.sectionsFromLocalCache(
        nationwideShippingOnly: true,
      ),
    );
  }

  static Future<void> _continueWarmCategory({
    required String key,
    required Future<List<PublicCatalogSection>> Function() sectionsLoader,
  }) async {
    try {
      final sections = await sectionsLoader();
      if (sections.isEmpty) {
        return;
      }
      final products = collectProductsFromSections(sections, limit: 200);
      final offset =
          _categoryPrefetchOffsets[key] ?? bootstrapImagesPerQuickAction;

      await prefetchProductsImmediate(
        products,
        limit: onTapPrefetchBatch,
        offset: offset,
        parallel: 6,
      );
      final nextOffset = offset + onTapPrefetchBatch;
      _categoryPrefetchOffsets[key] = nextOffset;

      final remaining = products.length - nextOffset;
      if (remaining > 0) {
        scheduleProductsPrefetch(
          products,
          limit: remaining.clamp(1, defaultPrefetchCount),
          dedupeKey: '$key:continue:$nextOffset',
          delayMs: 0,
          offset: nextOffset,
        );
      }

      unawaited(
        prefetchCatalogSectionsImmediate(
          sections,
          productLimit: catalogImmediatePrefetchCount,
        ),
      );
    } catch (_) {
      // Catalog stream still loads on demand.
    }
  }

  static void startHomeWarmOnce({
    required Future<List<PublicCatalogProduct>> featuredFuture,
    required Future<
      ({
        List<PublicCatalogProduct> bestSelling,
        List<PublicCatalogProduct> personalized,
      })
    > secondaryFuture,
  }) {
    if (_warmStarted) {
      return;
    }
    _warmStarted = true;
    unawaited(_runHomeWarm(featuredFuture, secondaryFuture));
  }

  static Future<void> _runHomeWarm(
    Future<List<PublicCatalogProduct>> featuredFuture,
    Future<
      ({
        List<PublicCatalogProduct> bestSelling,
        List<PublicCatalogProduct> personalized,
      })
    > secondaryFuture,
  ) async {
    try {
      final featured = await featuredFuture;
      if (!_bootstrapWarmDone) {
        await prefetchUrls(
          collectProductImageUrls(
            featured,
            limit: priorityPrefetchCount,
          ),
          awaitPriority: true,
          parallel: 3,
        );
      }

      final secondary = await secondaryFuture;
      final all = <PublicCatalogProduct>[
        ...featured,
        ...secondary.bestSelling,
        ...secondary.personalized,
      ];
      await prefetchUrls(
        collectProductImageUrls(all),
        awaitPriority: false,
      );
    } catch (_) {
      // UI still loads images on demand.
    }
  }

  static void scheduleShelfPrefetch(
    List<PublicCatalogProduct> products, {
    int limit = defaultPrefetchCount,
  }) {
    if (_bootstrapWarmDone) {
      return;
    }
    scheduleProductsPrefetch(products, limit: limit, delayMs: 800);
  }

  static void scheduleProductsPrefetch(
    List<PublicCatalogProduct> products, {
    int limit = defaultPrefetchCount,
    String? dedupeKey,
    int delayMs = 300,
    int offset = 0,
  }) {
    final key =
        dedupeKey ?? products.map((product) => product.id).take(limit).join(',');
    if (key.isEmpty || !_scheduledKeys.add('products:$key')) {
      return;
    }
    final urls = collectProductImageUrls(products, limit: limit, offset: offset);
    if (urls.isEmpty) {
      return;
    }
    final videoUrls = <String>[];
    for (final product in products.skip(offset)) {
      if (videoUrls.length >= VideoPrefetchService.maxNeighborPrefetch) {
        break;
      }
      final video = readCatalogProductVideoUrl(product.data);
      if (video != null) {
        videoUrls.add(video);
      }
    }
    unawaited(
      Future<void>.delayed(
        Duration(milliseconds: delayMs),
        () async {
          await prefetchUrls(urls, awaitPriority: false);
          VideoPrefetchService.instance.preloadVideos(videoUrls);
        },
      ),
    );
  }

  static void scheduleCatalogSectionsPrefetch(
    List<PublicCatalogSection> sections, {
    int productLimit = defaultPrefetchCount,
    String? categoryKey,
  }) {
    if (sections.isEmpty) {
      return;
    }
    unawaited(
      prefetchCatalogSectionsImmediate(
        sections,
        productLimit: catalogImmediatePrefetchCount,
      ),
    );

    final products = collectProductsFromSections(sections, limit: productLimit);
    final offset = categoryKey == null
        ? 0
        : (_categoryPrefetchOffsets[categoryKey] ??
            bootstrapImagesPerQuickAction);
    final dedupeKey =
        'catalog:${categoryKey ?? 'generic'}:${sections.map((s) => s.shopId).join('|')}:${products.map((p) => p.id).join(',')}:$offset';
    scheduleProductsPrefetch(
      products,
      limit: productLimit,
      dedupeKey: dedupeKey,
      delayMs: 0,
      offset: offset,
    );
    if (categoryKey != null) {
      _categoryPrefetchOffsets[categoryKey] = offset + productLimit;
    }

    scheduleImageUrlsPrefetch(
      sections.map((section) => section.shopImageUrl),
      limit: sections.length.clamp(1, 12),
      dedupeKey: 'shops:$dedupeKey',
      delayMs: 0,
    );
  }

  static Future<void> prefetchCatalogSectionsImmediate(
    List<PublicCatalogSection> sections, {
    int productLimit = catalogImmediatePrefetchCount,
  }) async {
    if (sections.isEmpty) {
      return;
    }
    final first = sections.first;
    final shopUrls = sections
        .take(3)
        .map((section) => section.shopImageUrl?.trim())
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    await Future.wait<void>(<Future<void>>[
      prefetchProductsImmediate(
        first.products,
        limit: productLimit,
        parallel: 6,
      ),
      if (shopUrls.isNotEmpty)
        prefetchUrls(shopUrls, awaitPriority: true, parallel: 3),
    ], eagerError: false);
  }

  static void scheduleImageUrlsPrefetch(
    Iterable<String?> urls, {
    int limit = defaultPrefetchCount,
    String? dedupeKey,
    int delayMs = 300,
  }) {
    final collected = collectImageUrls(urls, limit: limit);
    if (collected.isEmpty) {
      return;
    }
    final key = dedupeKey ?? collected.join('|');
    if (!_scheduledKeys.add('urls:$key')) {
      return;
    }
    unawaited(
      Future<void>.delayed(
        Duration(milliseconds: delayMs),
        () => prefetchUrls(collected, awaitPriority: false),
      ),
    );
  }

  static Future<void> prefetchProducts(
    List<PublicCatalogProduct> products, {
    int limit = defaultPrefetchCount,
    int offset = 0,
  }) {
    return prefetchUrls(
      collectProductImageUrls(products, limit: limit, offset: offset),
      awaitPriority: false,
    );
  }

  static Future<void> prefetchUrls(
    List<String> urls, {
    bool awaitPriority = false,
    int parallel = 2,
  }) async {
    if (urls.isEmpty) {
      return;
    }

    final pending = urls
        .where(
          (url) =>
              url.isNotEmpty &&
              !_completedUrls.contains(url) &&
              !_inFlight.contains(url),
        )
        .toList(growable: false);
    if (pending.isEmpty) {
      return;
    }

    if (awaitPriority) {
      await _prefetchBatch(pending, parallel: parallel);
      return;
    }
    unawaited(_prefetchBatch(pending, parallel: parallel));
  }

  static Future<void> _prefetchBatch(
    List<String> urls, {
    required int parallel,
  }) async {
    final chunkSize = parallel < 1 ? 1 : parallel;
    for (var index = 0; index < urls.length; index += chunkSize) {
      final chunk = urls
          .skip(index)
          .take(chunkSize)
          .map(_prefetchUrl)
          .toList(growable: false);
      await Future.wait<void>(chunk, eagerError: false);
    }
  }

  static Future<void> _prefetchUrl(String url) async {
    if (_completedUrls.contains(url) || _inFlight.contains(url)) {
      return;
    }
    _inFlight.add(url);
    try {
      if (await isAppImageCached(url)) {
        _completedUrls.add(url);
        return;
      }
      final fileInfo = await AppImageDownloadCoordinator.run(
        () => AppImageCacheManager.instance.downloadFile(url),
      );
      AppImageDiskHintCache.remember(url, fileInfo.file);
      _completedUrls.add(url);
    } catch (_) {
      // UI will retry via CachedAppImage.
    } finally {
      _inFlight.remove(url);
    }
  }
}

typedef HomeProductImagePrefetch = AppImagePrefetch;
