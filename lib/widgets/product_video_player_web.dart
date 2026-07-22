import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../services/video_source_helper.dart';
import 'cached_app_image.dart';

/// HTML5 video fallback for web — BetterPlayer is mobile-only (MethodChannel).
class ProductVideoPlayerWeb extends StatefulWidget {
  const ProductVideoPlayerWeb({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.isActive,
    this.hostActive = true,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final bool? isActive;
  final bool hostActive;

  @override
  State<ProductVideoPlayerWeb> createState() => _ProductVideoPlayerWebState();
}

class _ProductVideoPlayerWebState extends State<ProductVideoPlayerWeb>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _hasError = false;
  bool _isVisible = false;
  bool _isInitializing = false;
  bool _released = false;

  bool get _isPlaybackAllowed =>
      widget.hostActive && (widget.isActive ?? _isVisible);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onPlaybackAllowedChanged();
        }
      });
    }
  }

  @override
  void didUpdateWidget(ProductVideoPlayerWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl) {
      unawaited(_releaseController());
    }
    if (widget.hostActive != oldWidget.hostActive && !widget.hostActive) {
      unawaited(_releaseController());
      return;
    }
    if (widget.isActive != oldWidget.isActive ||
        widget.hostActive != oldWidget.hostActive) {
      _onPlaybackAllowedChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_releaseController());
      return;
    }
    if (state == AppLifecycleState.resumed && !_released) {
      _onPlaybackAllowedChanged();
    }
  }

  void _onPlaybackAllowedChanged() {
    if (_isPlaybackAllowed) {
      unawaited(_ensureController());
      return;
    }
    if (!widget.hostActive) {
      unawaited(_releaseController());
      return;
    }
    _pauseController();
  }

  Future<void> _ensureController() async {
    if (!_isPlaybackAllowed || _isInitializing) {
      return;
    }

    final existing = _controller;
    if (existing != null) {
      if (existing.value.isInitialized) {
        if (!existing.value.isPlaying) {
          await existing.play();
        }
        return;
      }
      await _releaseController();
    }

    if (!VideoSourceHelper.isNetworkUrl(widget.videoUrl)) {
      if (mounted && !_released) {
        setState(() => _hasError = true);
      }
      return;
    }

    _isInitializing = true;
    VideoPlayerController? created;
    try {
      created = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await created.initialize();
      await created.setLooping(true);
      await created.setVolume(1);

      if (!mounted || _released || !_isPlaybackAllowed) {
        await created.dispose();
        return;
      }

      setState(() {
        _controller = created;
        _hasError = false;
      });
      created = null;
      await _controller!.play();
    } catch (_) {
      if (mounted && !_released) {
        setState(() => _hasError = true);
      }
    } finally {
      if (created != null) {
        await created.dispose();
      }
      _isInitializing = false;
    }
  }

  void _pauseController() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    unawaited(controller.pause().catchError((_) {}));
  }

  Future<void> _releaseController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) {
      return;
    }
    try {
      await controller.pause();
    } catch (_) {}
    await controller.dispose();
    if (mounted && !_released) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _released = true;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  void _handleVisibilityChanged(VisibilityInfo info) {
    if (widget.isActive != null) {
      return;
    }
    final mostlyVisible = info.visibleFraction >= 0.45;
    if (mostlyVisible == _isVisible) {
      return;
    }
    _isVisible = mostlyVisible;
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
    final thumbnail = widget.thumbnailUrl?.trim();
    final showThumbnail =
        controller == null || !controller.value.isInitialized || !controller.value.isPlaying;

    return VisibilityDetector(
      key: ValueKey<String>('product-video-web-${widget.videoUrl}'),
      onVisibilityChanged: _handleVisibilityChanged,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          if (thumbnail != null && thumbnail.isNotEmpty)
            IgnorePointer(
              ignoring: true,
              child: AnimatedOpacity(
                opacity: showThumbnail ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: CachedAppImage(
                  imageUrl: thumbnail,
                  fit: BoxFit.cover,
                  errorWidget: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          if (controller == null && _isPlaybackAllowed)
            const ColoredBox(
              color: Colors.black54,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
