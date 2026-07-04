import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

int _webDomImageViewSeq = 0;

String _objectFitCss(BoxFit fit) {
  return switch (fit) {
    BoxFit.contain => 'contain',
    BoxFit.cover => 'cover',
    BoxFit.fill => 'fill',
    BoxFit.fitWidth => 'scale-down',
    BoxFit.fitHeight => 'scale-down',
    BoxFit.none => 'none',
    BoxFit.scaleDown => 'scale-down',
  };
}

String? _borderRadiusCss(BorderRadius? borderRadius) {
  if (borderRadius == null) {
    return null;
  }
  final radius = borderRadius.topLeft.x;
  if (radius <= 0) {
    return null;
  }
  return '${radius}px';
}

Widget buildWebDomImage({
  required String url,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  BorderRadius? borderRadius,
  Widget Function(BuildContext context)? errorBuilder,
}) {
  return _WebDomImage(
    url: url.trim(),
    width: width,
    height: height,
    fit: fit,
    borderRadius: borderRadius,
    errorBuilder: errorBuilder,
  );
}

class _WebDomImage extends StatefulWidget {
  const _WebDomImage({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget Function(BuildContext context)? errorBuilder;

  @override
  State<_WebDomImage> createState() => _WebDomImageState();
}

class _WebDomImageState extends State<_WebDomImage> {
  late final String _viewType;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'van2-web-img-${_webDomImageViewSeq++}';
    _registerViewFactory(widget.url);
  }

  @override
  void didUpdateWidget(covariant _WebDomImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _failed = false;
      _viewType = 'van2-web-img-${_webDomImageViewSeq++}';
      _registerViewFactory(widget.url);
    }
  }

  void _registerViewFactory(String url) {
    final fit = widget.fit;
    final borderRadius = widget.borderRadius;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final img = web.HTMLImageElement()
        ..src = url
        ..decoding = 'async'
        ..style.border = 'none'
        ..style.margin = '0'
        ..style.padding = '0'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = _objectFitCss(fit);

      final radiusCss = _borderRadiusCss(borderRadius);
      if (radiusCss != null) {
        img.style.borderRadius = radiusCss;
      }

      img.onError.listen((_) {
        if (!mounted) {
          return;
        }
        setState(() => _failed = true);
      });

      return img;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty || _failed) {
      return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
