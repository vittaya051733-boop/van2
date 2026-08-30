import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart';

/// Builds a single share image: product photo + detail text panel (2 layers).
class CatalogShareCardImage {
  CatalogShareCardImage._();

  static const double _cardWidth = 1080;
  // Product detail uses a wide media viewport; 4:3 mirrors that framing.
  static const double _photoHeight = 810;
  static const double _horizontalPad = 44;
  static const Color _accent = Color(0xFFF57C00);
  static const Color _panelBg = Color(0xFFFFFBF5);
  static const Color _titleColor = Color(0xFF111827);
  static const Color _bodyColor = Color(0xFF374151);
  static const Color _mutedColor = Color(0xFF6B7280);

  static Future<Uint8List?> build({
    required Uint8List productImageBytes,
    required String name,
    required String shopName,
    required String priceLabel,
    required String description,
    required String shareUrl,
  }) async {
    if (productImageBytes.isEmpty) {
      return null;
    }

    try {
      final codec = await ui.instantiateImageCodec(productImageBytes);
      final frame = await codec.getNextFrame();
      final productImage = frame.image;

      final blocks = _layoutBlocks(
        name: name,
        shopName: shopName,
        priceLabel: priceLabel,
        description: description,
        shareUrl: shareUrl,
      );
      final panelHeight = blocks.fold<double>(
            0,
            (sum, block) => sum + block.height + block.topGap,
          ) +
          56;

      final totalHeight = _photoHeight + panelHeight;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawRect(
        Rect.fromLTWH(0, 0, _cardWidth, totalHeight),
        Paint()..color = Colors.white,
      );
      _drawCoverImage(
        canvas,
        productImage,
        Rect.fromLTWH(0, 0, _cardWidth, _photoHeight),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, _photoHeight, _cardWidth, 6),
        Paint()..color = _accent,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, _photoHeight + 6, _cardWidth, panelHeight - 6),
        Paint()..color = _panelBg,
      );

      var y = _photoHeight + 6 + 36;
      for (final block in blocks) {
        y += block.topGap;
        block.paint(canvas, Offset(_horizontalPad, y));
        y += block.height;
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        _cardWidth.toInt(),
        totalHeight.ceil(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      productImage.dispose();
      image.dispose();

      if (byteData == null) {
        return null;
      }

      final pngBytes = byteData.buffer.asUint8List();
      if (kIsWeb) {
        return pngBytes;
      }

      final jpeg = await FlutterImageCompress.compressWithList(
        pngBytes,
        format: CompressFormat.jpeg,
        quality: 95,
      );
      return jpeg.isEmpty ? pngBytes : jpeg;
    } catch (_) {
      return null;
    }
  }

  static List<_ShareCardBlock> _layoutBlocks({
    required String name,
    required String shopName,
    required String priceLabel,
    required String description,
    required String shareUrl,
  }) {
    final maxTextWidth = _cardWidth - (_horizontalPad * 2);
    final blocks = <_ShareCardBlock>[
      _ShareCardBlock(
        topGap: 0,
        painter: _painter(
          name,
          GoogleFonts.notoSansThai(
            fontSize: 46,
            fontWeight: FontWeight.w800,
            color: _titleColor,
            height: 1.25,
          ),
          maxWidth: maxTextWidth,
          maxLines: 2,
        ),
      ),
      _ShareCardBlock(
        topGap: 18,
        painter: _painter(
          'ร้าน: $shopName',
          GoogleFonts.notoSansThai(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            color: _bodyColor,
            height: 1.3,
          ),
          maxWidth: maxTextWidth,
          maxLines: 1,
        ),
      ),
      _ShareCardBlock(
        topGap: 14,
        painter: _painter(
          priceLabel,
          GoogleFonts.notoSansThai(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: _accent,
            height: 1.2,
          ),
          maxWidth: maxTextWidth,
          maxLines: 1,
        ),
      ),
    ];

    final trimmedDescription = description.trim();
    if (trimmedDescription.isNotEmpty) {
      blocks.add(
        _ShareCardBlock(
          topGap: 20,
          painter: _painter(
            trimmedDescription,
            GoogleFonts.notoSansThai(
              fontSize: 30,
              fontWeight: FontWeight.w400,
              color: _bodyColor,
              height: 1.45,
            ),
            maxWidth: maxTextWidth,
            maxLines: 5,
          ),
        ),
      );
    }

    blocks.add(
      _ShareCardBlock(
        topGap: 24,
        painter: _painter(
          'จากแว๊นตลาด\n$shareUrl',
          GoogleFonts.notoSansThai(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: _mutedColor,
            height: 1.35,
          ),
          maxWidth: maxTextWidth,
          maxLines: 3,
        ),
      ),
    );

    return blocks;
  }

  static TextPainter _painter(
    String text,
    TextStyle style, {
    required double maxWidth,
    required int maxLines,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  static void _drawCoverImage(
    Canvas canvas,
    ui.Image image,
    Rect dest,
  ) {
    final imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final fitted = applyBoxFit(BoxFit.cover, imageSize, dest.size);
    final source = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & imageSize,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;
    canvas.drawImageRect(image, source, dest, paint);
  }
}

class _ShareCardBlock {
  _ShareCardBlock({
    required this.topGap,
    required this.painter,
  });

  final double topGap;
  final TextPainter painter;

  double get height => painter.height;

  void paint(Canvas canvas, Offset offset) {
    painter.paint(canvas, offset);
  }
}
