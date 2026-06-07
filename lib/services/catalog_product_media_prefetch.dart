import 'dart:async';

import '../public_catalog_service.dart';
import '../utils/catalog_product_image_url.dart';
import 'app_image_prefetch.dart';
import 'video_prefetch_service.dart';

/// Prefetches images (all slots) and nearby videos for smooth catalog browsing.
void prefetchCatalogProductMedia({
  required List<PublicCatalogProduct> products,
  required int selectedIndex,
  int maxNeighborVideos = VideoPrefetchService.maxNeighborPrefetch,
}) {
  if (selectedIndex < 0 || selectedIndex >= products.length) {
    return;
  }

  final imageUrls = <String>{};
  final videoUrls = <String>{};

  final current = products[selectedIndex].data;
  imageUrls.addAll(readCatalogProductImageUrls(current));
  final currentVideo = readCatalogProductVideoUrl(current);
  if (currentVideo != null) {
    videoUrls.add(currentVideo);
  }

  var offset = 1;
  var neighborCount = 0;
  while (neighborCount < maxNeighborVideos &&
      (selectedIndex - offset >= 0 || selectedIndex + offset < products.length)) {
    final prevIndex = selectedIndex - offset;
    if (prevIndex >= 0) {
      final prevData = products[prevIndex].data;
      imageUrls.addAll(readCatalogProductImageUrls(prevData));
      final prevVideo = readCatalogProductVideoUrl(prevData);
      if (prevVideo != null && videoUrls.add(prevVideo)) {
        neighborCount++;
      }
    }

    final nextIndex = selectedIndex + offset;
    if (nextIndex < products.length) {
      final nextData = products[nextIndex].data;
      imageUrls.addAll(readCatalogProductImageUrls(nextData));
      final nextVideo = readCatalogProductVideoUrl(nextData);
      if (nextVideo != null && videoUrls.add(nextVideo)) {
        neighborCount++;
      }
    }

    offset++;
  }

  if (imageUrls.isNotEmpty) {
    unawaited(
      AppImagePrefetch.prefetchUrls(
        imageUrls.toList(growable: false),
        awaitPriority: false,
      ),
    );
  }
  if (videoUrls.isNotEmpty) {
    VideoPrefetchService.instance.preloadVideos(videoUrls);
  }
}

void prefetchSingleProductMedia(Map<String, dynamic> data) {
  final imageUrls = readCatalogProductImageUrls(data);
  if (imageUrls.isNotEmpty) {
    unawaited(
      AppImagePrefetch.prefetchUrls(imageUrls, awaitPriority: true, parallel: 4),
    );
  }
  final videoUrl = readCatalogProductVideoUrl(data);
  if (videoUrl != null) {
    VideoPrefetchService.instance.preloadVideo(videoUrl);
  }
}
