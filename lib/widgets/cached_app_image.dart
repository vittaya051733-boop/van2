import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Centralized network image widget with disk caching, placeholder, and error UI.
class CachedAppImage extends StatelessWidget {
  const CachedAppImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  Widget _defaultPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  Widget _defaultError(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: borderRadius,
      ),
      child: const Icon(Icons.broken_image_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final placeholderWidget = placeholder ?? _defaultPlaceholder(context);
    final error = errorWidget ?? _defaultError(context);

    Widget buildImage(Widget child) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius ?? BorderRadius.zero, child: child);
      }
      return child;
    }

    if (url == null || url.isEmpty) {
      return buildImage(error);
    }

    return buildImage(
      CachedNetworkImage(
        width: width,
        height: height,
        fit: fit,
        imageUrl: url,
        placeholder: (_, __) => placeholderWidget,
        errorWidget: (_, __, ___) => error,
        fadeInDuration: const Duration(milliseconds: 200),
        memCacheWidth: (width != null && width! > 0) ? width!.toInt() * 2 : null,
        memCacheHeight: (height != null && height! > 0) ? height!.toInt() * 2 : null,
      ),
    );
  }
}
