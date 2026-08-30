import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'video_source_helper.dart';

/// Warms network video URLs with a partial range request instead of downloading
/// the entire file before playback.
class VideoPrefetchService {
  VideoPrefetchService._();

  static final VideoPrefetchService instance = VideoPrefetchService._();

  static const int maxNeighborPrefetch = 5;
  static const int headerPrefetchBytes = 5 * 1024 * 1024;

  final Set<String> _inFlight = <String>{};
  final Set<String> _completed = <String>{};

  void preloadVideo(String? url) {
    if (url == null) return;
    final normalized = url.trim();
    if (normalized.isEmpty ||
        _inFlight.contains(normalized) ||
        _completed.contains(normalized)) {
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
    try {
      final resolvedUrl = await VideoSourceHelper.resolveMediaUrl(url);
      if (!VideoSourceHelper.isNetworkUrl(resolvedUrl)) {
        _completed.add(url);
        return;
      }

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(resolvedUrl))
          ..headers['Range'] = 'bytes=0-${headerPrefetchBytes - 1}';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        await response.stream.drain<void>();
      } finally {
        client.close();
      }
      _completed.add(url);
    } catch (error, stack) {
      debugPrint('VideoPrefetchService: Failed to prefetch $url -> $error\n$stack');
    } finally {
      _inFlight.remove(url);
    }
  }
}
