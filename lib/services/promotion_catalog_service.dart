import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/promotion_models.dart';

class PromotionCatalogService {
  PromotionCatalogService._();

  static final PromotionCatalogService instance = PromotionCatalogService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<PromotionOffer>> watchActivePromotions() {
    return _firestore
        .collection('promotions')
        .where('active', isEqualTo: true)
        .limit(30)
        .snapshots()
        .map((snapshot) {
      final offers = snapshot.docs
          .map((doc) => PromotionOffer.fromFirestore(doc.id, doc.data()))
          .where((offer) => offer.active)
          .toList(growable: false);
      offers.sort((a, b) => b.priority.compareTo(a.priority));
      return offers;
    });
  }

  PromotionOffer? promotionForProduct(
    List<PromotionOffer> promotions, {
    required String productId,
    required String shopId,
  }) {
    for (final promo in promotions) {
      if (!_matchesProduct(promo, productId: productId, shopId: shopId)) {
        continue;
      }
      return promo;
    }
    return null;
  }

  String? badgeForProduct(
    List<PromotionOffer> promotions, {
    required String productId,
    required String shopId,
  }) {
    final promo = promotionForProduct(
      promotions,
      productId: productId,
      shopId: shopId,
    );
    return promo?.badgeText.trim().isNotEmpty == true
        ? promo!.badgeText.trim()
        : null;
  }

  bool _matchesProduct(
    PromotionOffer promo, {
    required String productId,
    required String shopId,
  }) {
    if (promo.productIds.isNotEmpty && !promo.productIds.contains(productId)) {
      return false;
    }
    if (promo.shopIds.isNotEmpty && !promo.shopIds.contains(shopId)) {
      return false;
    }
    return true;
  }
}
