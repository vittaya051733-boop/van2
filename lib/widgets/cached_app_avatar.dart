import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/app_image_cache.dart';
import 'cached_app_image.dart';

/// Circular profile/shop avatar using the shared app image disk cache.
class CachedAppAvatar extends StatelessWidget {
  const CachedAppAvatar({
    super.key,
    this.imageUrl,
    this.radius = 20,
    this.backgroundColor = const Color(0xFFE5E7EB),
    this.fallback,
    this.maxCachePx = kAppImageCacheMaxPx,
  });

  final String? imageUrl;
  final double radius;
  final Color backgroundColor;
  final Widget? fallback;
  final int maxCachePx;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: fallback,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: kIsWeb
          ? CachedAppImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              lightweight: true,
              maxCachePx: maxCachePx,
              borderRadius: BorderRadius.circular(radius),
              errorWidget: fallback ?? const Icon(Icons.person_outline),
            )
          : ClipOval(
              child: SizedBox(
                width: size,
                height: size,
                child: CachedAppImage(
                  imageUrl: url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  lightweight: true,
                  maxCachePx: maxCachePx,
                  errorWidget: fallback ?? const Icon(Icons.person_outline),
                ),
              ),
            ),
    );
  }
}
