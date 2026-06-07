import 'package:better_player/better_player.dart';

import 'media_cache_service.dart';

/// Shared helpers for building BetterPlayer data sources and resolving URLs.
class VideoSourceHelper {
  const VideoSourceHelper._();

  static const BetterPlayerCacheConfiguration cacheConfiguration =
      BetterPlayerCacheConfiguration(
    useCache: true,
    maxCacheSize: 50 * 1024 * 1024,
    maxCacheFileSize: 30 * 1024 * 1024,
    preCacheSize: 10 * 1024 * 1024,
  );

  static bool isNetworkUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static Future<String> resolveMediaUrl(String url) async {
    if (!isNetworkUrl(url)) {
      return url;
    }
    final cachedPath = await MediaCacheService.instance.getCachedPath(url);
    return cachedPath ?? url;
  }

  static BetterPlayerDataSource buildDataSource(String url) {
    if (isNetworkUrl(url)) {
      return BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        url,
        cacheConfiguration: cacheConfiguration,
      );
    }
    return BetterPlayerDataSource(BetterPlayerDataSourceType.file, url);
  }
}
