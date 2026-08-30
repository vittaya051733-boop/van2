import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'catalog_product_link.dart';
import 'catalog_product_link_platform.dart' as platform;

/// Captures shared /product/... links on web and Android.
class CatalogProductDeepLinkService {
  CatalogProductDeepLinkService._();

  static final CatalogProductDeepLinkService instance =
      CatalogProductDeepLinkService._();

  final StreamController<CatalogProductLinkTarget> _targetsController =
      StreamController<CatalogProductLinkTarget>.broadcast();

  Stream<CatalogProductLinkTarget> get targets => _targetsController.stream;

  CatalogProductLinkTarget? _pending;
  StreamSubscription<Uri>? _linkSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (kIsWeb) {
      final initial = platform.readCurrentWebTarget();
      if (initial != null) {
        _enqueue(initial);
      }
      return;
    }

    final appLinks = AppLinks();
    try {
      final initialUri = await appLinks.getInitialLink();
      _captureUri(initialUri);
    } catch (_) {}

    _linkSubscription = appLinks.uriLinkStream.listen(
      _captureUri,
      onError: (_) {},
    );
  }

  CatalogProductLinkTarget? consumePending() {
    final pending = _pending;
    _pending = null;
    return pending;
  }

  void dispose() {
    unawaited(_linkSubscription?.cancel());
    unawaited(_targetsController.close());
  }

  void _captureUri(Uri? uri) {
    if (uri == null) {
      return;
    }
    final target = CatalogProductLink.parse(uri);
    if (target == null) {
      return;
    }
    _enqueue(target);
  }

  void _enqueue(CatalogProductLinkTarget target) {
    _pending = target;
    if (!_targetsController.isClosed) {
      _targetsController.add(target);
    }
  }
}
