import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Preloads Thai text + Material icon fonts on web before the first frame.
class WebFontBootstrap {
  WebFontBootstrap._();

  static Future<void>? _ready;

  static Future<void> ensureReady() {
    if (!kIsWeb) {
      return Future<void>.value();
    }
    return _ready ??= _load().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }

  static Future<void> _load() async {
    await Future.wait<void>(<Future<void>>[
      _loadNotoSansThai(),
      _loadMaterialIcons(),
    ]);
  }

  static Future<void> _loadNotoSansThai() async {
    await GoogleFonts.pendingFonts(<TextStyle>[
      GoogleFonts.notoSansThai(),
      GoogleFonts.notoSansThai(fontWeight: FontWeight.w500),
      GoogleFonts.notoSansThai(fontWeight: FontWeight.w600),
      GoogleFonts.notoSansThai(fontWeight: FontWeight.w700),
      GoogleFonts.notoSansThai(fontWeight: FontWeight.w800),
      GoogleFonts.notoSansThai(fontWeight: FontWeight.w900),
    ]);
  }

  static Future<void> _loadMaterialIcons() async {
    const candidates = <String>[
      'fonts/MaterialIcons-Regular.otf',
      'packages/flutter/fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    ];

    for (final assetPath in candidates) {
      try {
        final loader = FontLoader(_familyForAsset(assetPath))
          ..addFont(rootBundle.load(assetPath));
        await loader.load();
      } catch (_) {}
    }
  }

  static String _familyForAsset(String assetPath) {
    if (assetPath.contains('CupertinoIcons')) {
      return 'CupertinoIcons';
    }
    return 'MaterialIcons';
  }

  static ThemeData applyTheme(ThemeData base) {
    if (!kIsWeb) {
      return base;
    }

    final thaiTextTheme = GoogleFonts.notoSansThaiTextTheme(base.textTheme);
    return base.copyWith(
      textTheme: thaiTextTheme,
      primaryTextTheme: GoogleFonts.notoSansThaiTextTheme(base.primaryTextTheme),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: GoogleFonts.notoSansThai(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: base.appBarTheme.titleTextStyle?.color ??
              base.colorScheme.onSurface,
        ),
      ),
    );
  }
}
