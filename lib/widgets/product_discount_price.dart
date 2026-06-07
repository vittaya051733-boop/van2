import 'package:flutter/material.dart';

import '../models/promotion_models.dart';
import '../services/promotion_catalog_service.dart';
import '../services/promotion_display_config_service.dart';
import '../tax_pricing_policy.dart';
import 'product_discount_display.dart';

class ProductDiscountPrice extends StatelessWidget {
  const ProductDiscountPrice({
    super.key,
    required this.productData,
    this.productId,
    this.shopId,
    this.style,
    this.originalStyle,
    this.compact = false,
  });

  final Map<String, dynamic> productData;
  final String? productId;
  final String? shopId;
  final TextStyle? style;
  final TextStyle? originalStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final canMatchPromotion =
        productId != null &&
        productId!.isNotEmpty &&
        shopId != null &&
        shopId!.isNotEmpty &&
        PromotionDisplayConfigService.instance.current.productBadge;

    if (!canMatchPromotion) {
      return _buildPriceRow(
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
        return _buildPriceRow(
          ProductDiscountDisplay.resolve(
            productData: productData,
            promotion: promotion,
          ),
        );
      },
    );
  }

  Widget _buildPriceRow(ProductDiscountDisplay display) {
    final priceStyle = style ??
        TextStyle(
          fontSize: compact ? 11.5 : 16,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFEF8A17),
          height: 1.1,
        );

    if (!display.hasDiscount) {
      return Text(
        '฿${TaxPricingPolicy.formatPrice(display.salePrice)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: priceStyle,
      );
    }

    final strikeStyle = originalStyle ??
        TextStyle(
          fontSize: compact ? 9 : 12,
          color: const Color(0xFF9CA3AF),
          decoration: TextDecoration.lineThrough,
          decorationColor: const Color(0xFF9CA3AF),
          decorationThickness: 2,
          height: 1.1,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          '฿${TaxPricingPolicy.formatPrice(display.originalPrice)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: strikeStyle,
        ),
        SizedBox(width: compact ? 4 : 6),
        Flexible(
          child: Text(
            '฿${TaxPricingPolicy.formatPrice(display.salePrice)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: priceStyle.copyWith(color: const Color(0xFFE55A00)),
          ),
        ),
      ],
    );
  }
}
