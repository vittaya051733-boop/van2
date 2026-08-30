/// Merchant apps allow up to 10 product images per item.
const int kCatalogProductMaxImages = 10;

/// Resolves all display image URLs for a catalog product (max [kCatalogProductMaxImages]).
///
/// Uses [imageUrls] when present; otherwise falls back to [thumbnailUrls] so the
/// same photo is not shown twice (thumbnail + full-size).
List<String> readCatalogProductImageUrls(
  Map<String, dynamic> data, {
  int maxCount = kCatalogProductMaxImages,
}) {
  final seen = <String>{};
  final urls = <String>[];

  void addUrl(String? raw) {
    if (urls.length >= maxCount) {
      return;
    }
    final url = raw?.trim();
    if (url == null || url.isEmpty || !seen.add(url)) {
      return;
    }
    urls.add(url);
  }

  void addFromList(Object? raw) {
    if (raw is! List) {
      return;
    }
    for (final entry in raw) {
      if (urls.length >= maxCount) {
        return;
      }
      addUrl(entry.toString());
    }
  }

  final originals = data['imageUrls'];
  final hasOriginals = originals is List &&
      originals.any((entry) => entry.toString().trim().isNotEmpty);

  if (hasOriginals) {
    addFromList(originals);
  } else {
    addFromList(data['thumbnailUrls']);
  }

  for (final key in <String>['imageUrl', 'photoUrl', 'productImage']) {
    if (urls.length >= maxCount) {
      break;
    }
    addUrl(data[key]?.toString());
  }

  final videoUrl = readCatalogProductVideoUrl(data);
  final videoThumb = readCatalogProductVideoThumbnailUrl(data);
  if (videoUrl == null && videoThumb == null) {
    return urls;
  }

  return urls
      .where((url) => url != videoUrl && url != videoThumb)
      .toList(growable: false);
}

/// Resolves the primary display image URL for a catalog product map.
String? readCatalogProductImageUrl(Map<String, dynamic> data) {
  final urls = readCatalogProductImageUrls(data, maxCount: 1);
  return urls.isEmpty ? null : urls.first;
}

/// Best image URL to attach when sharing (full image first for photo attachment).
String? readCatalogProductShareAttachmentUrl(Map<String, dynamic> data) {
  final imageUrl = readCatalogProductImageUrl(data);
  if (imageUrl != null && imageUrl.isNotEmpty) {
    return imageUrl;
  }
  return readCatalogProductShareImageUrl(data);
}

/// Best image URL to attach when sharing (thumbnail first, then poster for video-only items).
String? readCatalogProductShareImageUrl(Map<String, dynamic> data) {
  final thumbnails = data['thumbnailUrls'];
  if (thumbnails is List) {
    for (final entry in thumbnails) {
      final url = entry.toString().trim();
      if (url.isNotEmpty) {
        return url;
      }
    }
  }

  final imageUrl = readCatalogProductImageUrl(data);
  if (imageUrl != null && imageUrl.isNotEmpty) {
    return imageUrl;
  }

  return readCatalogProductVideoThumbnailUrl(data);
}

String? readCatalogProductVideoUrl(Map<String, dynamic> data) {
  final url = data['videoUrl']?.toString().trim();
  if (url == null || url.isEmpty) {
    return null;
  }
  return url;
}

String? readCatalogProductVideoThumbnailUrl(Map<String, dynamic> data) {
  final url = data['videoThumbnailUrl']?.toString().trim();
  if (url == null || url.isEmpty) {
    return null;
  }
  return url;
}
