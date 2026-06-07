import 'package:flutter/material.dart';

import '../models/promotion_models.dart';
import '../services/promotion_catalog_service.dart';
import '../services/promotion_display_config_service.dart';
import '../tax_pricing_policy.dart';
import 'product_discount_display.dart';

class ProductDiscountPercentBadge extends StatelessWidget {
  const ProductDiscountPercentBadge({
    super.key,
    this.discountPercent,
    this.label,
    this.compact = false,
  });

  final double? discountPercent;
  final String? label;
  final bool compact;

  factory ProductDiscountPercentBadge.fromData(
    Map<String, dynamic> data, {
    bool compact = false,
  }) {
    return ProductDiscountPercentBadge(
      discountPercent: TaxPricingPolicy.parseDiscountPercent(
        data['discountPercent'],
      ),
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _resolveLabel();
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE55A00),
        borderRadius: BorderRadius.circular(compact ? 7 : 8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 9.5 : 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }

  String? _resolveLabel() {
    final custom = label?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final percent = discountPercent ?? 0;
    if (percent <= 0) {
      return null;
    }
    final value =
        percent % 1 == 0 ? percent.toInt().toString() : percent.toString();
    return 'ลด $value%';
  }
}

Widget wrapCatalogImageWithDiscountBadge({
  required Widget child,
  required Map<String, dynamic> productData,
  String? productId,
  String? shopId,
  bool compact = false,
}) {
  final canMatchPromotion =
      productId != null &&
      productId.isNotEmpty &&
      shopId != null &&
      shopId.isNotEmpty &&
      PromotionDisplayConfigService.instance.current.productBadge;

  Widget overlay(ProductDiscountDisplay display) {
    final badgeLabel = display.badgeLabel;
    if (!display.hasDiscount || badgeLabel == null || badgeLabel.isEmpty) {
      return child;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        Positioned(
          top: compact ? 6 : 8,
          right: compact ? 6 : 8,
          child: ProductDiscountPercentBadge(
            label: badgeLabel,
            compact: compact,
          ),
        ),
      ],
    );
  }

  if (!canMatchPromotion) {
    return overlay(
      ProductDiscountDisplay.resolve(productData: productData),
    );
  }

  return StreamBuilder<List<PromotionOffer>>(
    stream: PromotionCatalogService.instance.watchActivePromotions(),
    builder: (context, snapshot) {
      final promotion = PromotionCatalogService.instance.promotionForProduct(
        snapshot.data ?? const <PromotionOffer>[],
        productId: productId!,
        shopId: shopId!,
      );
      return overlay(
        ProductDiscountDisplay.resolve(
          productData: productData,
          promotion: promotion,
        ),
      );
    },
  );
}
