import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/app_image_prefetch.dart';
import '../services/catalog_product_media_prefetch.dart';
import '../services/video_prefetch_service.dart';
import '../utils/catalog_product_image_url.dart';
import 'cached_app_image.dart';
import 'product_video_player.dart';

class CatalogProductMediaCarousel extends StatefulWidget {
  const CatalogProductMediaCarousel({
    super.key,
    required this.productData,
    this.name = '',
    this.compact = false,
    this.enableVideo = false,
    this.fixedHeight,
    this.onTap,
    this.fit = BoxFit.cover,
    this.borderRadius = 18,
    this.showPageIndicator = true,
    this.playbackActive = true,
    this.playVideo,
    this.initialPage = 0,
    this.pageIndex,
    this.onPageChanged,
  });

  final Map<String, dynamic> productData;
  final String name;
  final bool compact;
  final bool enableVideo;
  final double? fixedHeight;
  final VoidCallback? onTap;
  final BoxFit fit;
  final double borderRadius;
  final bool showPageIndicator;
  /// When false, video playback stops completely (e.g. user left this product).
  final bool playbackActive;
  /// When set, controls play/pause separately from [playbackActive] (warm preload).
  final bool? playVideo;
  final int initialPage;
  final int? pageIndex;
  final ValueChanged<int>? onPageChanged;

  @override
  State<CatalogProductMediaCarousel> createState() =>
      _CatalogProductMediaCarouselState();
}

class _CatalogProductMediaCarouselState extends State<CatalogProductMediaCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _didPrefetchAll = false;

  List<String> get _imageUrls =>
      readCatalogProductImageUrls(widget.productData);

  String? get _videoUrl => readCatalogProductVideoUrl(widget.productData);

  String? get _videoThumbnailUrl =>
      readCatalogProductVideoThumbnailUrl(widget.productData);

  bool get _productHasVideo =>
      _videoUrl != null && _videoUrl!.isNotEmpty;

  bool get _showVideoPage => widget.enableVideo && _productHasVideo;

  int get _pageCount => _imageUrls.length + (_showVideoPage ? 1 : 0);

  int get _videoPageIndex => _showVideoPage ? _pageCount - 1 : -1;

  bool get _isOnVideoPage =>
      _showVideoPage && _currentPage == _videoPageIndex;

  bool get _isAdjacentToVideoPage =>
      _showVideoPage && _currentPage == _videoPageIndex - 1;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(0, max(0, _pageCount - 1)).toInt();
    _pageController = PageController(initialPage: _currentPage);
    _prefetchVisibleAndNeighbors(_currentPage);
    if (_productHasVideo) {
      VideoPrefetchService.instance.preloadVideo(_videoUrl);
    }
  }

  void _jumpToPage(int index) {
    final clamped = index.clamp(0, max(0, _pageCount - 1)).toInt();
    if (clamped == _currentPage) {
      return;
    }
    _currentPage = clamped;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(clamped);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) {
          return;
        }
        _pageController.jumpToPage(clamped);
      });
    }
    _prefetchVisibleAndNeighbors(clamped);
  }

  @override
  void didUpdateWidget(CatalogProductMediaCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackActive != widget.playbackActive &&
        !widget.playbackActive) {
      _jumpToPage(0);
      setState(() {});
    }
    if (widget.pageIndex != null &&
        widget.pageIndex != oldWidget.pageIndex &&
        widget.pageIndex != _currentPage) {
      _jumpToPage(widget.pageIndex!);
      setState(() {});
    }
    if (oldWidget.productData != widget.productData) {
      _didPrefetchAll = false;
      if (_currentPage >= _pageCount) {
        _jumpToPage(0);
        setState(() {});
      }
      _prefetchVisibleAndNeighbors(_currentPage);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _prefetchVisibleAndNeighbors(int pageIndex) {
    final urls = <String>[];
    if (pageIndex >= 0 && pageIndex < _imageUrls.length) {
      urls.add(_imageUrls[pageIndex]);
    }
    if (pageIndex > 0 && pageIndex - 1 < _imageUrls.length) {
      urls.add(_imageUrls[pageIndex - 1]);
    }
    if (pageIndex + 1 < _imageUrls.length) {
      urls.add(_imageUrls[pageIndex + 1]);
    }
    if (_showVideoPage &&
        (pageIndex == _videoPageIndex || pageIndex == _videoPageIndex - 1)) {
      VideoPrefetchService.instance.preloadVideo(_videoUrl);
    }
    if (urls.isNotEmpty) {
      unawaited(
        AppImagePrefetch.prefetchUrls(
          urls,
          awaitPriority: widget.enableVideo,
          parallel: 3,
        ),
      );
    }

    if (widget.enableVideo && !_didPrefetchAll) {
      _didPrefetchAll = true;
      prefetchSingleProductMedia(widget.productData);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = _pageCount <= 1
        ? _buildSinglePage()
        : Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PageView.builder(
                controller: _pageController,
                itemCount: _pageCount,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  _prefetchVisibleAndNeighbors(index);
                  widget.onPageChanged?.call(index);
                },
                itemBuilder: (context, index) {
                  if (_showVideoPage && index == _videoPageIndex) {
                    return _buildVideoPage();
                  }
                  return _buildImagePage(_imageUrls[index]);
                },
              ),
              if (widget.showPageIndicator)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: compactIndicatorBottom,
                  child: _PageDots(
                    count: _pageCount,
                    index: _currentPage,
                    compact: widget.compact,
                    highlightVideo: _showVideoPage,
                  ),
                ),
            ],
          );

    return _buildFramedChild(_wrapTapContent(media));
  }

  double get compactIndicatorBottom => widget.compact ? 6 : 10;

  Widget _sizeChild(Widget child) {
    if (widget.fixedHeight == null) {
      return AspectRatio(aspectRatio: 1.05, child: child);
    }
    return SizedBox(
      height: widget.fixedHeight,
      width: double.infinity,
      child: child,
    );
  }

  /// Transparent layer above media so taps work on web [HtmlElementView] images.
  Widget _wrapTapContent(Widget child) {
    if (widget.onTap == null) {
      return _sizeChild(child);
    }

    return _sizeChild(
      Stack(
        fit: StackFit.expand,
        children: <Widget>[
          child,
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePage() {
    if (_showVideoPage && _imageUrls.isEmpty) {
      return _buildVideoPage();
    }
    if (_imageUrls.isEmpty && _productHasVideo && !widget.enableVideo) {
      final thumb = _videoThumbnailUrl;
      if (thumb != null && thumb.isNotEmpty) {
        return _buildImagePage(thumb);
      }
      return _ProductPlaceholder(name: widget.name);
    }
    final imageUrl = _imageUrls.isNotEmpty ? _imageUrls.first : null;
    return imageUrl != null
        ? _buildImagePage(imageUrl)
        : _ProductPlaceholder(name: widget.name);
  }

  Widget _buildImagePage(String imageUrl) {
    return CachedAppImage(
      imageUrl: imageUrl,
      fit: widget.fit,
      lightweight: widget.compact,
      errorWidget: _ProductPlaceholder(name: widget.name),
    );
  }

  Widget _buildVideoPage() {
    final shouldPlay = widget.playVideo ?? widget.playbackActive;
    final warmVideo = _isOnVideoPage || _isAdjacentToVideoPage;
    final isVideoPageActive = shouldPlay && _isOnVideoPage;
    return _KeepAliveCarouselPage(
      child: ProductVideoPlayer(
        videoUrl: _videoUrl!,
        thumbnailUrl: _videoThumbnailUrl,
        isActive: isVideoPageActive,
        hostActive: widget.playbackActive && warmVideo,
      ),
    );
  }

  Widget _buildFramedChild(Widget child) {
    final frameColor =
        _isOnVideoPage ? Colors.black : const Color(0xFFF8FAFC);
    return Container(
      decoration: BoxDecoration(
        color: frameColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _KeepAliveCarouselPage extends StatefulWidget {
  const _KeepAliveCarouselPage({required this.child});

  final Widget child;

  @override
  State<_KeepAliveCarouselPage> createState() => _KeepAliveCarouselPageState();
}

class _KeepAliveCarouselPageState extends State<_KeepAliveCarouselPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SizedBox.expand(child: widget.child);
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.compact,
    required this.highlightVideo,
  });

  final int count;
  final int index;
  final bool compact;
  final bool highlightVideo;

  @override
  Widget build(BuildContext context) {
    final dotSize = compact ? 5.0 : 6.0;
    final activeWidth = compact ? 14.0 : 18.0;
    final isVideoActive = highlightVideo && index == count - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (dotIndex) {
        final active = dotIndex == index;
        final isVideoDot = highlightVideo && dotIndex == count - 1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 3),
          width: active ? activeWidth : dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: active
                ? (isVideoActive ? const Color(0xFFDC2626) : Colors.white)
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(dotSize),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: isVideoDot && !active
              ? Icon(
                  Icons.play_arrow_rounded,
                  size: dotSize + 1,
                  color: const Color(0xFF111827),
                )
              : null,
        );
      }),
    );
  }
}

class _ProductPlaceholder extends StatelessWidget {
  const _ProductPlaceholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F4F6),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.image_outlined,
            size: 36,
            color: Colors.grey.shade500,
          ),
          if (name.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
