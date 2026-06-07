import '../models/promotion_models.dart';
import '../tax_pricing_policy.dart';

class ProductDiscountDisplay {
  const ProductDiscountDisplay({
    required this.salePrice,
    required this.originalPrice,
    required this.badgeLabel,
    required this.hasDiscount,
  });

  final num salePrice;
  final num originalPrice;
  final String? badgeLabel;
  final bool hasDiscount;

  static ProductDiscountDisplay resolve({
    required Map<String, dynamic> productData,
    PromotionOffer? promotion,
  }) {
    final merchantPercent =
        TaxPricingPolicy.parseDiscountPercent(productData['discountPercent']);
    final originalPrice =
        TaxPricingPolicy.resolveCustomerOriginalUnitPrice(productData);
    var salePrice = TaxPricingPolicy.resolveCustomerUnitPrice(productData);

    final promoPercent = _promotionPercent(promotion);
    if (promoPercent != null && promoPercent > 0) {
      salePrice = TaxPricingPolicy.roundForPayment(
        salePrice * (1 - promoPercent / 100),
      );
    }

    final badgeLabel = _buildBadgeLabel(
      merchantPercent: merchantPercent,
      promotion: promotion,
      promoPercent: promoPercent,
    );
    final hasDiscount = badgeLabel != null && badgeLabel.isNotEmpty;

    return ProductDiscountDisplay(
      salePrice: salePrice,
      originalPrice: originalPrice,
      badgeLabel: badgeLabel,
      hasDiscount: hasDiscount,
    );
  }

  static double? _promotionPercent(PromotionOffer? promotion) {
    if (promotion == null) {
      return null;
    }
    if (promotion.discountType != 'percent' || promotion.discountValue <= 0) {
      return null;
    }
    return promotion.discountValue;
  }

  static String? _buildBadgeLabel({
    required double merchantPercent,
    required PromotionOffer? promotion,
    required double? promoPercent,
  }) {
    if (merchantPercent > 0 && promoPercent != null && promoPercent > 0) {
      final combined = 100 *
          (1 -
              (1 - merchantPercent / 100) *
                  (1 - promoPercent / 100));
      return 'ลด ${_formatPercent(combined)}%';
    }

    if (merchantPercent > 0) {
      return 'ลด ${_formatPercent(merchantPercent)}%';
    }

    if (promotion == null) {
      return null;
    }

    if (promoPercent != null && promoPercent > 0) {
      return 'ลด ${_formatPercent(promoPercent)}%';
    }

    final badgeText = promotion.badgeText.trim();
    if (badgeText.isNotEmpty) {
      return badgeText;
    }

    if (promotion.discountType == 'fixed' && promotion.discountValue > 0) {
      return 'ลด ฿${promotion.discountValue.toStringAsFixed(0)}';
    }

    return null;
  }

  static String _formatPercent(double value) {
    if (value % 1 == 0) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }
}
