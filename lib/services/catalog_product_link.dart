import 'package:flutter/foundation.dart';

import 'catalog_product_link_platform.dart' as platform;
class CatalogProductLink {
  CatalogProductLink._();

  static const String webBaseUrl = 'https://vantalad.web.app';

  static const Set<String> _allowedHosts = <String>{
    'vantalad.web.app',
    'localhost',
    '127.0.0.1',
  };

  static String buildShareUrl({
    required String productId,
    String? shopId,
  }) {
    return _buildProductUri(
      productId: productId,
      shopId: shopId,
      suffix: null,
    ).toString();
  }

  /// Same-origin JPEG proxy for share attachments (avoids Storage CORS on web).
  static String buildOgImageUrl({
    required String productId,
    String? shopId,
  }) {
    return _buildProductUri(
      productId: productId,
      shopId: shopId,
      suffix: 'og.jpg',
    ).toString();
  }

  /// Full, uncropped source image through the same-origin share proxy.
  static String buildShareImageUrl({
    required String productId,
    String? shopId,
  }) {
    return _buildProductUri(
      productId: productId,
      shopId: shopId,
      suffix: 'share.jpg',
    ).toString();
  }

  static Uri _buildProductUri({
    required String productId,
    String? shopId,
    String? suffix,
  }) {
    final normalizedId = productId.trim();
    final segments = <String>[
      'product',
      normalizedId,
      if (suffix != null && suffix.isNotEmpty) suffix,
    ];
    final query = <String, String>{};
    final normalizedShopId = shopId?.trim();
    if (normalizedShopId != null && normalizedShopId.isNotEmpty) {
      query['shop'] = normalizedShopId;
    }
    return Uri(
      scheme: 'https',
      host: Uri.parse(webBaseUrl).host,
      pathSegments: segments,
      queryParameters: query.isEmpty ? null : query,
    );
  }

  static CatalogProductLinkTarget? parse(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!_allowedHosts.contains(host)) {
      return null;
    }

    final segments = uri.pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length < 2 || segments.first.toLowerCase() != 'product') {
      return null;
    }

    final productId = Uri.decodeComponent(segments[1]).trim();
    if (productId.isEmpty) {
      return null;
    }

    final shopId = uri.queryParameters['shop']?.trim();
    return CatalogProductLinkTarget(
      productId: productId,
      shopId: shopId == null || shopId.isEmpty ? null : shopId,
    );
  }

  static CatalogProductLinkTarget? parseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) {
      return null;
    }
    return parse(uri);
  }

  static CatalogProductLinkTarget? readCurrentWebTarget() {
    if (!kIsWeb) {
      return null;
    }
    return platform.readCurrentWebTarget();
  }

  static void normalizeWebHomeUrl() {
    if (!kIsWeb) {
      return;
    }
    if (Uri.base.pathSegments.isEmpty ||
        Uri.base.pathSegments.first.toLowerCase() != 'product') {
      return;
    }
    platform.replaceWebUrl('/');
  }
}

class CatalogProductLinkTarget {
  const CatalogProductLinkTarget({
    required this.productId,
    this.shopId,
  });

  final String productId;
  final String? shopId;

  @override
  bool operator ==(Object other) {
    return other is CatalogProductLinkTarget &&
        other.productId == productId &&
        other.shopId == shopId;
  }

  @override
  int get hashCode => Object.hash(productId, shopId);
}
