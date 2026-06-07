import 'dart:async';

import 'package:better_player/better_player.dart';
import 'package:flutter/foundation.dart';

import 'video_source_helper.dart';

/// Manages background video precaching so playback can start instantly.
class VideoPrefetchService {
  VideoPrefetchService._();

  static final VideoPrefetchService instance = VideoPrefetchService._();

  static const int maxNeighborPrefetch = 5;

  final Set<String> _inFlight = <String>{};

  void preloadVideo(String? url) {
    if (url == null) return;
    final normalized = url.trim();
    if (normalized.isEmpty || _inFlight.contains(normalized)) {
      return;
    }
    _inFlight.add(normalized);
    unawaited(_prefetch(normalized));
  }

  void preloadVideos(Iterable<String?> urls) {
    for (final url in urls) {
      preloadVideo(url);
    }
  }

  Future<void> _prefetch(String url) async {
    BetterPlayerController? controller;
    try {
      final resolvedUrl = await VideoSourceHelper.resolveMediaUrl(url);
      if (!VideoSourceHelper.isNetworkUrl(resolvedUrl)) {
        return;
      }
      final dataSource = VideoSourceHelper.buildDataSource(resolvedUrl);
      controller = BetterPlayerController(
        const BetterPlayerConfiguration(autoPlay: false),
      );
      await controller.preCache(dataSource);
    } catch (error, stack) {
      debugPrint('VideoPrefetchService: Failed to prefetch $url -> $error\n$stack');
    } finally {
      controller?.dispose(forceDispose: true);
      _inFlight.remove(url);
    }
  }
}
