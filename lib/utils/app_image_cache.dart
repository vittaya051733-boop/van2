import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Max edge length (px) for decoded catalog/list images in van2.
const int kAppImageCacheMaxPx = 150;

/// Long-lived on-device cache for product/shop thumbnails (shared across screens).
class AppImageCacheManager extends CacheManager {
  AppImageCacheManager._()
      : super(
          Config(
            'van2_app_images_v2',
            stalePeriod: const Duration(days: 3650),
            maxNrOfCacheObjects: 4000,
          ),
        );

  static final AppImageCacheManager instance = AppImageCacheManager._();
}

/// Limits concurrent image downloads so home prefetch does not starve visible tiles.
class AppImageDownloadCoordinator {
  AppImageDownloadCoordinator._();

  static const int maxConcurrent = 3;
  static int _active = 0;
  static final List<Completer<void>> _waiters = <Completer<void>>[];

  static Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  static Future<void> _acquire() async {
    while (_active >= maxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }
    _active += 1;
  }

  static void _release() {
    _active -= 1;
    if (_waiters.isEmpty) {
      return;
    }
    final next = _waiters.removeAt(0);
    if (!next.isCompleted) {
      next.complete();
    }
  }
}

/// In-memory hint so list tiles skip async disk lookup on repeat URLs.
class AppImageDiskHintCache {
  AppImageDiskHintCache._();

  static final Map<String, File> _filesByUrl = <String, File>{};

  static File? peek(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final file = _filesByUrl[trimmed];
    if (file == null) {
      return null;
    }
    if (!file.existsSync()) {
      _filesByUrl.remove(trimmed);
      return null;
    }
    return file;
  }

  static void remember(String url, File file) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _filesByUrl[trimmed] = file;
  }

  static Future<File?> resolve(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final hinted = peek(trimmed);
    if (hinted != null) {
      return hinted;
    }
    final fileInfo = await AppImageCacheManager.instance.getFileFromCache(trimmed);
    final file = fileInfo?.file;
    if (file != null) {
      remember(trimmed, file);
    }
    return file;
  }
}

/// Returns true when [url] is already stored in the app image disk cache.
Future<bool> isAppImageCached(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (AppImageDiskHintCache.peek(trimmed) != null) {
    return true;
  }
  final fileInfo = await AppImageCacheManager.instance.getFileFromCache(trimmed);
  if (fileInfo != null) {
    AppImageDiskHintCache.remember(trimmed, fileInfo.file);
    return true;
  }
  return false;
}

/// Picks a cache/decode size from layout, capped at [maxPx].
int resolveAppImageCachePx({
  double? width,
  double? height,
  int maxPx = kAppImageCacheMaxPx,
}) {
  final sizes = <double>[];
  if (width != null && width > 0 && width.isFinite) {
    sizes.add(width);
  }
  if (height != null && height > 0 && height.isFinite) {
    sizes.add(height);
  }
  if (sizes.isEmpty) {
    return maxPx;
  }
  final largest = sizes.reduce((a, b) => a > b ? a : b);
  return largest.ceil().clamp(1, maxPx);
}

/// One mem-cache dimension only (keeps aspect ratio — avoids broken thin renders).
({int? memCacheWidth, int? memCacheHeight}) resolveMemCacheDimensions({
  double? width,
  double? height,
  int maxPx = kAppImageCacheMaxPx,
}) {
  final cachePx = resolveAppImageCachePx(
    width: width,
    height: height,
    maxPx: maxPx,
  );
  final layoutW = width != null && width > 0 && width.isFinite ? width : null;
  final layoutH = height != null && height > 0 && height.isFinite ? height : null;

  if (layoutW != null && layoutH != null) {
    if (layoutW >= layoutH) {
      return (memCacheWidth: cachePx, memCacheHeight: null);
    }
    return (memCacheWidth: null, memCacheHeight: cachePx);
  }
  if (layoutH != null) {
    return (memCacheWidth: null, memCacheHeight: cachePx);
  }
  return (memCacheWidth: cachePx, memCacheHeight: null);
}

double? normalizeLayoutDim(double? value) {
  if (value == null || !value.isFinite || value <= 0) {
    return null;
  }
  return value;
}

bool layoutDimIsExpand(double? value) {
  return value == null || !value.isFinite || value == double.infinity;
}
