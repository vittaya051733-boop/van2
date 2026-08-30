import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
/// Horizontal shelf that auto-advances in fixed item steps and loops seamlessly.
class HomeShelfInfiniteCarousel extends StatefulWidget {
  const HomeShelfInfiniteCarousel({
    super.key,
    required this.itemCount,
    required this.itemWidth,
    required this.spacing,
    required this.height,
    required this.itemBuilder,
    this.itemsPerStep = 2,
    this.stepInterval = const Duration(seconds: 5),
    this.stepAnimation = const Duration(milliseconds: 450),
  });

  final int itemCount;
  final double itemWidth;
  final double spacing;
  final double height;
  final IndexedWidgetBuilder itemBuilder;
  final int itemsPerStep;
  final Duration stepInterval;
  final Duration stepAnimation;

  @override
  State<HomeShelfInfiniteCarousel> createState() =>
      _HomeShelfInfiniteCarouselState();
}

class _HomeShelfInfiniteCarouselState extends State<HomeShelfInfiniteCarousel> {
  static const int _loopCopies = 3;

  late final ScrollController _scrollController;
  Timer? _autoScrollTimer;
  bool _userDragging = false;
  bool _isAnimating = false;
  int? _lastItemCount;
  int _scrollSetupAttempts = 0;

  static const int _maxScrollSetupAttempts = 40;

  ScrollPhysics get _carouselPhysics => kIsWeb
      ? const ClampingScrollPhysics()
      : const BouncingScrollPhysics();
  double get _itemExtent => widget.itemWidth + widget.spacing;

  double get _singleSetWidth => widget.itemCount * _itemExtent;

  double get _stepDistance =>
      max(1, widget.itemsPerStep) * _itemExtent;

  bool get _canLoop => widget.itemCount >= 2;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleInfiniteLoop);
    _lastItemCount = widget.itemCount;
    _scheduleScrollSetup();
  }

  void _scheduleScrollSetup({bool randomizeStart = true}) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (_scrollController.hasClients && _canLoop) {
        _scrollSetupAttempts = 0;
        _jumpToMiddleSet(randomizeStart: randomizeStart);
        _startAutoScroll();
        return;
      }

      if (_scrollSetupAttempts >= _maxScrollSetupAttempts) {
        return;
      }
      _scrollSetupAttempts += 1;
      _scheduleScrollSetup(randomizeStart: randomizeStart);
    });
  }
  @override
  void didUpdateWidget(covariant HomeShelfInfiniteCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      _lastItemCount = widget.itemCount;
      _scheduleScrollSetup(randomizeStart: false);
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController
      ..removeListener(_handleInfiniteLoop)
      ..dispose();
    super.dispose();
  }

  void _jumpToMiddleSet({bool randomizeStart = true}) {
    if (!_scrollController.hasClients || !_canLoop) {
      return;
    }

    var offset = _singleSetWidth;
    if (randomizeStart) {
      final randomIndex = Random().nextInt(widget.itemCount);
      offset += randomIndex * _itemExtent;
    }
    _scrollController.jumpTo(offset);
  }

  void _handleInfiniteLoop() {
    if (!_scrollController.hasClients || !_canLoop || _isAnimating) {
      return;
    }

    final offset = _scrollController.offset;
    if (offset >= _singleSetWidth * 2) {
      _scrollController.jumpTo(offset - _singleSetWidth);
    } else if (offset <= 0) {
      _scrollController.jumpTo(offset + _singleSetWidth);
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(widget.stepInterval, (_) {
      unawaited(_advanceByStep());
    });
  }

  Future<void> _advanceByStep() async {
    if (!mounted || _userDragging || _isAnimating || !_canLoop) {
      return;
    }

    if (!_scrollController.hasClients) {
      _scheduleScrollSetup(randomizeStart: false);
      return;
    }
    _isAnimating = true;
    try {
      await _scrollController.animateTo(
        _scrollController.offset + _stepDistance,
        duration: widget.stepAnimation,
        curve: Curves.easeInOut,
      );
      _normalizeLoopOffset();
    } catch (_) {
      // Ignore interrupted animations when the list rebuilds or disposes.
    } finally {
      _isAnimating = false;
    }
  }

  void _normalizeLoopOffset() {
    if (!_scrollController.hasClients || !_canLoop) {
      return;
    }

    final offset = _scrollController.offset;
    if (offset >= _singleSetWidth * 2) {
      _scrollController.jumpTo(offset - _singleSetWidth);
    } else if (offset <= 0) {
      _scrollController.jumpTo(offset + _singleSetWidth);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userDragging = true;
    } else if (notification is ScrollEndNotification) {
      _userDragging = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) {
      return SizedBox(height: widget.height);
    }

    if (!_canLoop) {
      return SizedBox(
        height: widget.height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: _carouselPhysics,
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
          itemBuilder: widget.itemBuilder,
        ),      );
    }

    return SizedBox(
      height: widget.height,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.separated(
          key: ValueKey<int>(_lastItemCount ?? widget.itemCount),
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: _carouselPhysics,
          primary: false,
          cacheExtent: widget.itemWidth * 4,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          itemCount: widget.itemCount * _loopCopies,
          separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
          itemBuilder: (context, index) {
            return widget.itemBuilder(context, index % widget.itemCount);
          },
        ),      ),
    );
  }
}
