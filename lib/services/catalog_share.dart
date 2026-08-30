import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../cart_screen.dart';
import '../public_catalog_service.dart';
import '../tax_pricing_policy.dart';
import '../utils/catalog_product_image_url.dart';
import 'catalog_product_link.dart';
import 'catalog_share_card_image.dart';
import 'catalog_share_image_cache.dart';
import 'catalog_share_web_sheet.dart';
import 'catalog_share_web_sheet_stub.dart'
    if (dart.library.html) 'catalog_share_web_sheet_web.dart'
    as catalog_share_web_actions;
import 'product_reaction_service.dart';

String _resolveShareShopId(PublicCatalogProduct product) {
  for (final key in <String>['ownerUid', 'shopQrCode', 'shopId']) {
    final value = product.data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return product.shopId;
}

Future<void> shareCatalogProduct(
  PublicCatalogProduct product, {
  BuildContext? context,
  String? shareImageUrl,
  Map<String, dynamic>? productDataForImage,
}) async {
  try {
    final data = productDataForImage ?? product.data;
    final name = (data['name'] ?? product.data['name'] ?? 'สินค้า').toString().trim();
    final price = TaxPricingPolicy.resolveCustomerUnitPrice(data);
    final discountPercent = TaxPricingPolicy.parseDiscountPercent(
      data['discountPercent'] ?? product.data['discountPercent'],
    );
    final shopName = product.shopName?.trim().isNotEmpty == true
        ? product.shopName!.trim()
        : 'ร้านค้า';
    final description = (data['description'] ?? product.data['description'] ?? '')
        .toString()
        .trim();
    final shareShopId = _resolveShareShopId(product);
    final shareUrl = CatalogProductLink.buildShareUrl(
      productId: product.id,
      shopId: shareShopId,
    );
    final ogImageUrl = CatalogProductLink.buildOgImageUrl(
      productId: product.id,
      shopId: shareShopId,
    );
    final fullShareImageUrl = CatalogProductLink.buildShareImageUrl(
      productId: product.id,
      shopId: shareShopId,
    );
    final imageUrl = shareImageUrl?.trim().isNotEmpty == true
        ? shareImageUrl!.trim()
        : readCatalogProductShareAttachmentUrl(data);
    CatalogShareImageCache.instance.warm(fullShareImageUrl);
    CatalogShareImageCache.instance.warm(imageUrl);

    final priceLabel = discountPercent > 0
        ? 'ราคา: ฿${price.toDouble().toStringAsFixed(0)} (ลด ${discountPercent % 1 == 0 ? discountPercent.toInt() : discountPercent}%)'
        : 'ราคา: ฿${price.toDouble().toStringAsFixed(0)}';

    final message = _buildShareMessage(
      name: name,
      shopName: shopName,
      priceLabel: priceLabel,
      description: description,
      shareUrl: shareUrl,
    );

    await _shareProductPayload(
      message: message,
      subject: name,
      imageUrl: imageUrl,
      ogImageUrl: ogImageUrl,
      fullShareImageUrl: fullShareImageUrl,
      shareUrl: shareUrl,
      cardName: name,
      cardShopName: shopName,
      cardPriceLabel: priceLabel,
      cardDescription: description,
      context: context,
    );

    try {
      await ProductReactionService.recordShare(
        productId: product.id,
        shopId: product.shopId,
      );
    } catch (_) {}
  } catch (error) {
    await _showShareFailure(context, error);
  }
}

Future<void> shareCartLineItem(
  CartLineItem item, {
  BuildContext? context,
}) async {
  try {
    final shareUrl = CatalogProductLink.buildShareUrl(
      productId: item.productId,
      shopId: item.shopId,
    );
    final ogImageUrl = CatalogProductLink.buildOgImageUrl(
      productId: item.productId,
      shopId: item.shopId,
    );
    final fullShareImageUrl = CatalogProductLink.buildShareImageUrl(
      productId: item.productId,
      shopId: item.shopId,
    );
    final priceLabel =
        'จำนวน ${item.quantity} x ฿${item.unitPrice.toStringAsFixed(0)}';
    final description = item.selectedToppings.isEmpty
        ? ''
        : 'ท็อปปิ้ง: ${item.selectedToppings.join(', ')}';
    final buffer = StringBuffer()
      ..writeln(shareUrl)
      ..writeln()
      ..writeln(item.productName)
      ..writeln('ร้าน: ${item.shopName}')
      ..writeln(priceLabel);
    if (description.isNotEmpty) {
      buffer.writeln(description);
    }
    buffer.writeln('\nจากแว๊นตลาด');

    final imageUrl = item.imageUrl?.trim();
    CatalogShareImageCache.instance.warm(fullShareImageUrl);
    CatalogShareImageCache.instance.warm(imageUrl);
    await _shareProductPayload(
      message: buffer.toString().trim(),
      subject: item.productName,
      imageUrl: imageUrl == null || imageUrl.isEmpty ? null : imageUrl,
      ogImageUrl: ogImageUrl,
      fullShareImageUrl: fullShareImageUrl,
      shareUrl: shareUrl,
      cardName: item.productName,
      cardShopName: item.shopName,
      cardPriceLabel: priceLabel,
      cardDescription: description,
      context: context,
    );
  } catch (error) {
    await _showShareFailure(context, error);
  }
}

String _buildShareMessage({
  required String name,
  required String shopName,
  required String priceLabel,
  required String description,
  required String shareUrl,
}) {
  final buffer = StringBuffer()
    ..writeln(shareUrl)
    ..writeln()
    ..writeln(name)
    ..writeln('ร้าน: $shopName')
    ..writeln(priceLabel);
  if (description.isNotEmpty) {
    buffer.writeln(description);
  }
  buffer.writeln('\nจากแว๊นตลาด');
  return buffer.toString().trim();
}

Future<void> _shareProductPayload({
  required String message,
  required String subject,
  String? imageUrl,
  String? ogImageUrl,
  String? fullShareImageUrl,
  required String shareUrl,
  required String cardName,
  required String cardShopName,
  required String cardPriceLabel,
  required String cardDescription,
  BuildContext? context,
}) async {
  _showSharePreparing(context);

  final productBytes = await _resolveShareImageBytes(
    imageUrl: imageUrl,
    fullShareImageUrl: fullShareImageUrl,
    ogImageUrl: ogImageUrl,
  );
  final shareBytes = productBytes == null
      ? null
      : await CatalogShareCardImage.build(
          productImageBytes: productBytes,
          name: cardName,
          shopName: cardShopName,
          priceLabel: cardPriceLabel,
          description: cardDescription,
          shareUrl: shareUrl,
        );
  final shareMime = shareBytes != null ? 'image/png' : 'image/jpeg';
  final shareFileName =
      shareBytes != null ? 'vantalad-product.png' : 'vantalad-product.jpg';
  final sharePositionOrigin = _sharePositionOrigin(context);

  if (shareBytes != null) {
    final sharedNative = await catalog_share_web_actions.tryWebNativeShare(
      imageBytes: shareBytes,
      message: shareUrl,
      title: subject,
      mimeType: shareMime,
      fileName: shareFileName,
    );
    if (sharedNative) {
      await _showShareSuccess(context, copied: false, withImage: true);
      return;
    }

    if (context != null && context.mounted) {
      await showProductShareSheet(
        context: context,
        imageBytes: shareBytes,
        message: shareUrl,
        title: subject,
        mimeType: shareMime,
        fileName: shareFileName,
      );
      return;
    }
  }

  try {
    if (shareBytes == null &&
        ((imageUrl != null && imageUrl.isNotEmpty) ||
            (ogImageUrl != null && ogImageUrl.isNotEmpty))) {
      _showShareImageMissing(context);
    }

    if (shareBytes != null && context != null && context.mounted) {
      await showProductShareSheet(
        context: context,
        imageBytes: shareBytes,
        message: shareUrl,
        title: subject,
        mimeType: shareMime,
        fileName: shareFileName,
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    await _showShareSuccess(
      context,
      copied: false,
      withImage: false,
    );
  } on MissingPluginException {
    await _copyShareFallback(
      message,
      context: context,
      imageBytes: shareBytes,
      title: subject,
    );
  } on PlatformException catch (error) {
    if (error.code == 'channel-error' || error.code == 'not-implemented') {
      await _copyShareFallback(
        message,
        context: context,
        imageBytes: shareBytes,
        title: subject,
      );
      return;
    }
    await _copyShareFallback(
      message,
      context: context,
      imageBytes: shareBytes,
      title: subject,
    );
  } catch (_) {
    await _copyShareFallback(
      message,
      context: context,
      imageBytes: shareBytes,
      title: subject,
    );
  }
}

Future<Uint8List?> _resolveShareImageBytes({
  String? imageUrl,
  String? fullShareImageUrl,
  String? ogImageUrl,
}) async {
  final candidates = <String>[
    if (imageUrl != null && imageUrl.isNotEmpty) imageUrl,
    if (fullShareImageUrl != null && fullShareImageUrl.isNotEmpty)
      fullShareImageUrl,
    if (ogImageUrl != null && ogImageUrl.isNotEmpty) ogImageUrl,
  ];

  for (final url in candidates) {
    final rawBytes = await CatalogShareImageCache.instance
        .resolve(url)
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    if (rawBytes != null && rawBytes.isNotEmpty) {
      return rawBytes;
    }
  }
  return null;
}

Rect? _sharePositionOrigin(BuildContext? context) {
  if (context == null || !context.mounted) {
    return null;
  }
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return null;
  }
  return box.localToGlobal(Offset.zero) & box.size;
}

void _showShareImageMissing(BuildContext? context) {
  final messengerContext = context;
  if (messengerContext == null || !messengerContext.mounted) {
    return;
  }
  ScaffoldMessenger.of(messengerContext).showSnackBar(
    const SnackBar(
      content: Text('โหลดรูปไม่สำเร็จ — แชร์ข้อความและลิงก์ก่อน ลองบันทึกรูปจากหน้าสินค้า'),
      duration: Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void _showSharePreparing(BuildContext? context) {
  final messengerContext = context;
  if (messengerContext == null || !messengerContext.mounted) {
    return;
  }
  ScaffoldMessenger.of(messengerContext).showSnackBar(
    const SnackBar(
      content: Text('กำลังสร้างภาพแชร์พร้อมรายละเอียด...'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<void> _showShareSuccess(
  BuildContext? context, {
  required bool copied,
  required bool withImage,
}) async {
  final messengerContext = context;
  if (messengerContext == null || !messengerContext.mounted) {
    return;
  }
  final text = copied
      ? (withImage
            ? 'แชร์รูปแล้ว — คัดลอกรายละเอียดไว้ให้วางในแชร์'
            : 'คัดลอกลิงก์สินค้าแล้ว')
      : withImage
      ? 'แชร์ภาพพร้อมรายละเอียดแล้ว'
      : 'เปิดเมนูแชร์แล้ว';
  ScaffoldMessenger.of(messengerContext).showSnackBar(
    SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<void> _showShareFailure(BuildContext? context, Object error) async {
  final messengerContext = context;
  if (messengerContext == null || !messengerContext.mounted) {
    return;
  }
  ScaffoldMessenger.of(messengerContext).showSnackBar(
    SnackBar(
      content: Text('แชร์ไม่สำเร็จ: $error'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<void> _copyShareFallback(
  String text, {
  BuildContext? context,
  Uint8List? imageBytes,
  String title = 'สินค้า',
}) async {
  await Clipboard.setData(ClipboardData(text: text));

  if (imageBytes != null && context != null && context.mounted) {
    await showProductShareSheet(
      context: context,
      imageBytes: imageBytes,
      message: text,
      title: title,
    );
    return;
  }

  await _showShareSuccess(context, copied: true, withImage: false);
}
