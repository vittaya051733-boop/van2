import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/app_image_cache.dart';
import 'web_dom_image.dart';

/// Network image with on-device disk cache and decode capped at 150px edge.
class CachedAppImage extends StatefulWidget {
  const CachedAppImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.maxCachePx = kAppImageCacheMaxPx,
    this.lightweight = false,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int maxCachePx;
  final bool lightweight;

  @override
  State<CachedAppImage> createState() => _CachedAppImageState();
}

class _CachedAppImageState extends State<CachedAppImage> {
  File? _diskFile;

  @override
  void initState() {
    super.initState();
    final url = widget.imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      _diskFile = AppImageDiskHintCache.peek(url);
    }
    _resolveDiskCache();
  }

  @override
  void didUpdateWidget(CachedAppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _diskFile = null;
      _resolveDiskCache();
    }
  }

  Future<void> _resolveDiskCache() async {
    if (kIsWeb) {
      return;
    }

    final url = widget.imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return;
    }

    try {
      final file = await AppImageDiskHintCache.resolve(url);
      if (!mounted || file == null || identical(file, _diskFile)) {
        return;
      }
      setState(() => _diskFile = file);
    } catch (_) {
      // CachedNetworkImage still loads on demand.
    }
  }

  Widget _defaultPlaceholder({double? w, double? h}) {
    if (widget.lightweight) {
      return Container(width: w, height: h, color: const Color(0xFFF3F4F6));
    }
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: widget.borderRadius,
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _defaultError({double? w, double? h}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: widget.borderRadius,
      ),
      child: const Icon(Icons.broken_image_outlined),
    );
  }

  Widget _wrap(Widget child) {
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }

  Widget _buildDiskImage({double? boxWidth, double? boxHeight}) {
    final file = _diskFile!;
    final image = Image.file(
      file,
      width: boxWidth,
      height: boxHeight,
      fit: widget.fit,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          widget.errorWidget ?? _defaultError(w: boxWidth, h: boxHeight),
    );
    if (widget.lightweight) {
      return RepaintBoundary(child: image);
    }
    return image;
  }

  Widget _buildWebNetworkImage({
    required String url,
    double? boxWidth,
    double? boxHeight,
    required Widget placeholderWidget,
    required Widget error,
  }) {
    return buildWebDomImage(
      url: url,
      width: boxWidth,
      height: boxHeight,
      fit: widget.fit,
      borderRadius: widget.borderRadius,
      errorBuilder: (_) => error,
    );
  }

  Widget _buildNetworkImage({
    required String url,
    required BoxConstraints constraints,
    double? layoutWidth,
    double? layoutHeight,
  }) {
    final boxWidth = layoutWidth ??
        (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
    final boxHeight = layoutHeight ??
        (constraints.maxHeight.isFinite ? constraints.maxHeight : null);

    final mem = resolveMemCacheDimensions(
      width: boxWidth,
      height: boxHeight,
      maxPx: widget.maxCachePx,
    );

    final placeholderWidget = widget.placeholder ??
        _defaultPlaceholder(w: boxWidth, h: boxHeight);
    final error =
        widget.errorWidget ?? _defaultError(w: boxWidth, h: boxHeight);

    if (kIsWeb) {
      final webImage = _buildWebNetworkImage(
        url: url,
        boxWidth: boxWidth,
        boxHeight: boxHeight,
        placeholderWidget: placeholderWidget,
        error: error,
      );
      final expandWidth = layoutDimIsExpand(widget.width) && boxWidth == null;
      final expandHeight = layoutDimIsExpand(widget.height) && boxHeight == null;
      if (expandWidth || expandHeight) {
        return SizedBox(
          width: boxWidth ??
              (constraints.maxWidth.isFinite ? constraints.maxWidth : null),
          height: boxHeight ??
              (constraints.maxHeight.isFinite ? constraints.maxHeight : null),
          child: webImage,
        );
      }
      return webImage;
    }

    final networkImage = CachedNetworkImage(
      imageUrl: url,
      width: boxWidth,
      height: boxHeight,
      fit: widget.fit,
      filterQuality: widget.lightweight ? FilterQuality.low : FilterQuality.medium,
      cacheManager: AppImageCacheManager.instance,
      useOldImageOnUrlChange: true,
      placeholder: widget.lightweight ? null : (_, __) => placeholderWidget,
      progressIndicatorBuilder: widget.lightweight
          ? (context, _, __) => placeholderWidget
          : null,
      errorWidget: (_, __, ___) => error,
      fadeInDuration:
          widget.lightweight ? Duration.zero : const Duration(milliseconds: 80),
      fadeOutDuration: Duration.zero,
      memCacheWidth: mem.memCacheWidth,
      memCacheHeight: mem.memCacheHeight,
    );

    final expandWidth = layoutDimIsExpand(widget.width) && boxWidth == null;
    final expandHeight = layoutDimIsExpand(widget.height) && boxHeight == null;
    if (expandWidth || expandHeight) {
      return SizedBox(
        width: boxWidth ??
            (constraints.maxWidth.isFinite ? constraints.maxWidth : null),
        height: boxHeight ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : null),
        child: networkImage,
      );
    }

    final child = widget.lightweight ? RepaintBoundary(child: networkImage) : networkImage;
    return child;
  }

  Widget _buildContent({
    required BoxConstraints constraints,
    double? layoutWidth,
    double? layoutHeight,
  }) {
    final url = widget.imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return widget.errorWidget ??
          _defaultError(w: layoutWidth, h: layoutHeight);
    }

    if (!kIsWeb && _diskFile != null) {
      final boxWidth = layoutWidth ??
          (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
      final boxHeight = layoutHeight ??
          (constraints.maxHeight.isFinite ? constraints.maxHeight : null);
      return _buildDiskImage(boxWidth: boxWidth, boxHeight: boxHeight);
    }

    return _buildNetworkImage(
      url: url,
      constraints: constraints,
      layoutWidth: layoutWidth,
      layoutHeight: layoutHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layoutWidth = normalizeLayoutDim(widget.width);
    final layoutHeight = normalizeLayoutDim(widget.height);
    final needsLayout = layoutWidth == null || layoutHeight == null;

    if (!needsLayout) {
      return _wrap(
        _buildContent(
          constraints: BoxConstraints.tightFor(
            width: layoutWidth,
            height: layoutHeight,
          ),
          layoutWidth: layoutWidth,
          layoutHeight: layoutHeight,
        ),
      );
    }

    return _wrap(
      LayoutBuilder(
        builder: (context, constraints) {
          return _buildContent(
            constraints: constraints,
            layoutWidth: layoutWidth,
            layoutHeight: layoutHeight,
          );
        },
      ),
    );
  }
}
