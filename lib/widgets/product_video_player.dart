import 'dart:async';
import 'dart:io';

import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../services/media_cache_service.dart';
import '../services/video_prefetch_service.dart';
import '../services/video_source_helper.dart';
import 'cached_app_image.dart';

class ProductVideoPlayer extends StatefulWidget {
  const ProductVideoPlayer({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    /// When set, parent (e.g. PageView) controls play/pause explicitly.
    /// When null, playback follows [VisibilityDetector].
    this.isActive,
    /// When false, playback stops and the controller is released.
    this.hostActive = true,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final bool? isActive;
  final bool hostActive;

  @override
  State<ProductVideoPlayer> createState() => _ProductVideoPlayerState();
}

class _ProductVideoPlayerState extends State<ProductVideoPlayer> {
  static const BetterPlayerConfiguration _playerConfig =
      BetterPlayerConfiguration(
    autoPlay: true,
    looping: true,
    fit: BoxFit.cover,
    allowedScreenSleep: false,
    autoDispose: false,
    handleLifecycle: false,
    controlsConfiguration: BetterPlayerControlsConfiguration(
      showControls: false,
      showControlsOnInitialize: false,
      enablePlayPause: false,
      enableFullscreen: false,
      enableMute: false,
      enableProgressBar: false,
      enableProgressBarDrag: false,
      enableProgressText: false,
      enableSkips: false,
      enableOverflowMenu: false,
      enablePlaybackSpeed: false,
      enableSubtitles: false,
      enableQualities: false,
      enableAudioTracks: false,
      enableRetry: false,
      enablePip: false,
      loadingWidget: SizedBox.shrink(),
    ),
  );

  BetterPlayerController? _controller;
  bool _hasError = false;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isVisible = false;
  bool _isInitializingController = false;
  bool _wantsAutoplay = false;
  bool _released = false;
  int _thumbnailRequestId = 0;
  String? _thumbnailSource;
  bool _thumbnailIsFile = false;

  bool get _isPlaybackAllowed =>
      widget.hostActive && (widget.isActive ?? _isVisible);

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _released) {
      return;
    }
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    VideoPrefetchService.instance.preloadVideo(widget.videoUrl);
    _loadThumbnail();
    if (widget.isActive == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onPlaybackAllowedChanged();
        }
      });
    }
  }

  @override
  void didUpdateWidget(ProductVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl) {
      unawaited(_releaseController());
      VideoPrefetchService.instance.preloadVideo(widget.videoUrl);
      _loadThumbnail();
    }
    if (widget.thumbnailUrl != oldWidget.thumbnailUrl) {
      _loadThumbnail();
    }
    if (widget.hostActive != oldWidget.hostActive && !widget.hostActive) {
      _wantsAutoplay = false;
      unawaited(_releaseController());
      return;
    }
    if (widget.isActive != oldWidget.isActive ||
        widget.hostActive != oldWidget.hostActive) {
      _onPlaybackAllowedChanged();
    }
  }

  void _onPlaybackAllowedChanged() {
    if (_isPlaybackAllowed) {
      _wantsAutoplay = true;
      if (_hasError) {
        _safeSetState(() => _hasError = false);
      }
      unawaited(_ensureControllerInitialized());
      return;
    }
    _wantsAutoplay = false;
    if (!widget.hostActive) {
      unawaited(_releaseController());
      return;
    }
    _safePause();
  }

  void _safePlay() {
    if (!_isPlaybackAllowed) {
      return;
    }
    _wantsAutoplay = true;
    final controller = _controller;
    if (controller == null || controller.isDisposed) {
      return;
    }
    unawaited(controller.play().catchError((Object error) {
      debugPrint('ProductVideoPlayer: play failed -> $error');
    }));
  }

  void _safePause() {
    final controller = _controller;
    if (controller == null || controller.isDisposed) {
      return;
    }
    unawaited(controller.pause().catchError((Object error) {
      debugPrint('ProductVideoPlayer: pause failed -> $error');
    }));
  }

  Future<void> _resumePlayback() async {
    if (!_isPlaybackAllowed) {
      return;
    }
    final controller = _controller;
    if (controller == null || controller.isDisposed) {
      await _ensureControllerInitialized();
      return;
    }
    _wantsAutoplay = true;
    try {
      await controller.pause();
      await controller.seekTo(Duration.zero);
      await controller.play();
    } catch (error) {
      debugPrint('ProductVideoPlayer: resume failed -> $error');
      await _recreateController();
    }
  }

  Future<void> _recreateController() async {
    await _releaseController();
    if (!mounted || !_isPlaybackAllowed) {
      return;
    }
    await _ensureControllerInitialized();
  }

  Future<void> _ensureControllerInitialized() async {
    if (!_isPlaybackAllowed) {
      return;
    }

    final existing = _controller;
    if (existing != null) {
      if (!existing.isDisposed) {
        await _resumePlayback();
      } else {
        _controller = null;
      }
      if (_controller != null || _isInitializingController) {
        return;
      }
    }

    if (_isInitializingController) {
      return;
    }

    _isInitializingController = true;
    BetterPlayerController? createdController;
    try {
      final resolvedUrl = await VideoSourceHelper.resolveMediaUrl(widget.videoUrl);
      if (!mounted || _released || !_isPlaybackAllowed) {
        return;
      }

      final dataSource = VideoSourceHelper.buildDataSource(resolvedUrl);
      createdController = BetterPlayerController(
        _playerConfig,
        betterPlayerDataSource: dataSource,
      );
      createdController.addEventsListener(_handleBetterPlayerEvent);

      if (!mounted || _released || !_isPlaybackAllowed) {
        return;
      }

      _safeSetState(() {
        _controller = createdController;
        _hasError = false;
        _isBuffering = true;
      });
      createdController = null;
      _safePlay();
    } catch (error) {
      debugPrint('ProductVideoPlayer: init error -> $error');
      _safeSetState(() => _hasError = true);
    } finally {
      if (createdController != null) {
        createdController.removeEventsListener(_handleBetterPlayerEvent);
        createdController.dispose(forceDispose: true);
      }
      _isInitializingController = false;
    }
  }

  Future<void> _loadThumbnail() async {
    final requestId = ++_thumbnailRequestId;
    final url = widget.thumbnailUrl;
    if (url != null && url.isNotEmpty) {
      final cachedPath = await MediaCacheService.instance.getCachedPath(url);
      if (!mounted || requestId != _thumbnailRequestId) {
        return;
      }
      _safeSetState(() {
        _thumbnailSource = cachedPath ?? url;
        _thumbnailIsFile =
            cachedPath != null || !VideoSourceHelper.isNetworkUrl(url);
      });
      return;
    }

    await _loadOrCreateFallbackThumbnail(requestId);
  }

  Future<void> _loadOrCreateFallbackThumbnail(int requestId) async {
    final fallbackKey = _fallbackCacheKey;
    final cached = await MediaCacheService.instance.getCachedPath(fallbackKey);
    if (!mounted || requestId != _thumbnailRequestId) {
      return;
    }
    if (cached != null) {
      _safeSetState(() {
        _thumbnailSource = cached;
        _thumbnailIsFile = true;
      });
      return;
    }

    try {
      final resolvedVideo =
          await VideoSourceHelper.resolveMediaUrl(widget.videoUrl);
      final tempPath = await VideoThumbnail.thumbnailFile(
        video: resolvedVideo,
        imageFormat: ImageFormat.PNG,
        quality: 80,
      );
      if (!mounted || requestId != _thumbnailRequestId || tempPath == null) {
        if (tempPath != null) {
          final tempFile = File(tempPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
        return;
      }

      final tempFile = File(tempPath);
      File? cachedFile;
      try {
        cachedFile = await MediaCacheService.instance.cacheUploadedFile(
          source: tempFile,
          url: fallbackKey,
          bucket: MediaCacheBucket.videoThumbnail,
        );
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      final localPath = cachedFile?.path;
      if (!mounted || requestId != _thumbnailRequestId) {
        return;
      }

      if (localPath != null) {
        _safeSetState(() {
          _thumbnailSource = localPath;
          _thumbnailIsFile = true;
        });
      }
    } catch (error) {
      debugPrint(
        'ProductVideoPlayer: Failed to generate fallback thumbnail: $error',
      );
    }
  }

  String get _fallbackCacheKey => 'generated_video_thumb::${widget.videoUrl}';

  void _handleBetterPlayerEvent(BetterPlayerEvent event) {
    if (!mounted || _released) return;
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.exception:
        _safeSetState(() => _hasError = true);
        unawaited(_releaseController());
        break;
      case BetterPlayerEventType.initialized:
        _safeSetState(() => _isInitialized = true);
        if (_wantsAutoplay && _isPlaybackAllowed) {
          _safePlay();
        }
        break;
      case BetterPlayerEventType.play:
        _safeSetState(() {
          _isPlaying = true;
          _isBuffering = false;
        });
        break;
      case BetterPlayerEventType.bufferingStart:
        _safeSetState(() => _isBuffering = true);
        break;
      case BetterPlayerEventType.bufferingEnd:
        _safeSetState(() => _isBuffering = false);
        break;
      case BetterPlayerEventType.finished:
        break;
      case BetterPlayerEventType.pause:
        _safeSetState(() {
          _isPlaying = false;
          _isBuffering = false;
        });
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _released = true;
    _wantsAutoplay = false;
    final controller = _controller;
    _controller = null;
    _isInitialized = false;
    _isPlaying = false;
    _isBuffering = false;
    if (controller != null) {
      controller.removeEventsListener(_handleBetterPlayerEvent);
      unawaited(_disposeControllerQuietly(controller));
    }
    super.dispose();
  }

  Future<void> _disposeControllerQuietly(BetterPlayerController controller) async {
    try {
      await controller.pause();
    } catch (error) {
      debugPrint('ProductVideoPlayer: pause on release failed -> $error');
    }
    if (!controller.isDisposed) {
      controller.dispose(forceDispose: true);
    }
  }

  Future<void> _releaseController() async {
    if (_released) {
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }

    _wantsAutoplay = false;
    _controller = null;
    _safeSetState(() {
      _isInitialized = false;
      _isPlaying = false;
      _isBuffering = false;
    });

    controller.removeEventsListener(_handleBetterPlayerEvent);
    await _disposeControllerQuietly(controller);
  }

  void _handleVisibilityChanged(VisibilityInfo info) {
    if (info.visibleFraction >= 0.12) {
      VideoPrefetchService.instance.preloadVideo(widget.videoUrl);
    }

    if (widget.isActive != null) {
      return;
    }

    final mostlyVisible = info.visibleFraction >= 0.45;
    final wasVisible = _isVisible;
    _isVisible = mostlyVisible;

    if (mostlyVisible == wasVisible) {
      return;
    }

    _onPlaybackAllowedChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            SizedBox(height: 8),
            Text('ไม่สามารถเล่นวิดีโอได้', style: TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    final controller = _controller;
    final hasThumbnail =
        _thumbnailSource != null && _thumbnailSource!.isNotEmpty;
    final showPlaceholder =
        hasThumbnail && (!_isInitialized || !_isPlaying || _isBuffering);

    return VisibilityDetector(
      key: ValueKey<String>('product-video-${widget.videoUrl}'),
      onVisibilityChanged: _handleVisibilityChanged,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            BetterPlayer(
              key: ValueKey<Object>(controller),
              controller: controller,
            )
          else
            const SizedBox.shrink(),
          if (hasThumbnail)
            IgnorePointer(
              ignoring: true,
              child: AnimatedOpacity(
                opacity: showPlaceholder ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: _buildPlaceholder(),
              ),
            ),
          if (controller == null && _isPlaybackAllowed)
            const _InlineLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    final source = _thumbnailSource;
    if (source == null || source.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Colors.black),
      );
    }

    final Widget child;
    if (_thumbnailIsFile) {
      child = Image.file(
        File(source),
        fit: BoxFit.cover,
      );
    } else {
      child = CachedAppImage(
        imageUrl: source,
        fit: BoxFit.cover,
        errorWidget: const DecoratedBox(
          decoration: BoxDecoration(color: Colors.black),
        ),
      );
    }

    return SizedBox.expand(child: child);
  }
}

class _InlineLoadingOverlay extends StatelessWidget {
  const _InlineLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
