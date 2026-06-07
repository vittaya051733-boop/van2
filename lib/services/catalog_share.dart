import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../cart_screen.dart';
import '../public_catalog_service.dart';
import '../tax_pricing_policy.dart';

Future<void> shareCatalogProduct(
  PublicCatalogProduct product, {
  BuildContext? context,
}) async {
  final data = product.data;
  final name = (data['name'] ?? 'สินค้า').toString().trim();
  final price = TaxPricingPolicy.resolveCustomerUnitPrice(data);
  final discountPercent = TaxPricingPolicy.parseDiscountPercent(
    data['discountPercent'],
  );
  final shopName = product.shopName?.trim().isNotEmpty == true
      ? product.shopName!.trim()
      : 'ร้านค้า';
  final description = (data['description'] ?? '').toString().trim();

  final buffer = StringBuffer()
    ..writeln(name)
    ..writeln('ร้าน: $shopName')
    ..writeln(
      discountPercent > 0
          ? 'ราคา: ฿${price.toStringAsFixed(0)} (ลด ${discountPercent % 1 == 0 ? discountPercent.toInt() : discountPercent}%)'
          : 'ราคา: ฿${price.toStringAsFixed(0)}',
    );
  if (description.isNotEmpty) {
    buffer.writeln(description);
  }
  buffer.writeln('\nจากแว๊นตลาด');

  await _shareText(buffer.toString().trim(), context: context);
}

Future<void> shareCartLineItem(
  CartLineItem item, {
  BuildContext? context,
}) async {
  final buffer = StringBuffer()
    ..writeln(item.productName)
    ..writeln('ร้าน: ${item.shopName}')
    ..writeln('จำนวน ${item.quantity} x ฿${item.unitPrice.toStringAsFixed(0)}');
  if (item.selectedToppings.isNotEmpty) {
    buffer.writeln('ท็อปปิ้ง: ${item.selectedToppings.join(', ')}');
  }
  buffer.writeln('\nจากแว๊นตลาด');

  await _shareText(buffer.toString().trim(), context: context);
}

Future<void> _shareText(String text, {BuildContext? context}) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } on MissingPluginException {
    await _copyShareFallback(text, context: context);
  } on PlatformException catch (error) {
    if (error.code == 'channel-error' || error.code == 'not-implemented') {
      await _copyShareFallback(text, context: context);
      return;
    }
    rethrow;
  }
}

Future<void> _copyShareFallback(
  String text, {
  BuildContext? context,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  final messengerContext = context;
  if (messengerContext == null || !messengerContext.mounted) {
    return;
  }

  ScaffoldMessenger.of(messengerContext).showSnackBar(
    const SnackBar(
      content: Text(
        'แชร์ไม่พร้อมบนเครื่องนี้ — คัดลอกข้อความแล้ว วางในแชทเพื่อส่งต่อได้',
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
