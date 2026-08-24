class PromotionDisplayConfig {
  const PromotionDisplayConfig({
    required this.cartStyle,
    required this.showAutoPromotionsInCart,
    required this.showCouponField,
    required this.homePromoBanner,
    required this.productBadge,
  });

  final String cartStyle;
  final bool showAutoPromotionsInCart;
  final bool showCouponField;
  final bool homePromoBanner;
  final bool productBadge;

  static const PromotionDisplayConfig defaults = PromotionDisplayConfig(
    cartStyle: 'expanded',
    showAutoPromotionsInCart: true,
    showCouponField: true,
    homePromoBanner: true,
    productBadge: true,
  );

  factory PromotionDisplayConfig.fromFirestore(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    final style = (source['cartStyle'] ?? 'expanded').toString().trim();
    return PromotionDisplayConfig(
      cartStyle: style.isEmpty ? 'expanded' : style,
      showAutoPromotionsInCart: source['showAutoPromotionsInCart'] != false,
      showCouponField: source['showCouponField'] != false,
      homePromoBanner: source['homePromoBanner'] != false,
      productBadge: source['productBadge'] != false,
    );
  }

  bool get isCompactCart => cartStyle == 'compact';
  bool get isBannerOnlyCart => cartStyle == 'banner_only';
}

class ClaimableCouponOffer {
  const ClaimableCouponOffer({
    required this.id,
    required this.name,
    required this.active,
    required this.shortLabel,
    required this.imageUrl,
    required this.presentation,
    required this.popupTitle,
    required this.ctaText,
    required this.discountType,
    required this.discountValue,
    required this.minSubtotal,
    required this.priority,
    required this.claimCount,
    required this.maxClaimsTotal,
    required this.transparentImage,
    this.startAt,
    this.endAt,
  });

  final String id;
  final String name;
  final bool active;
  final String shortLabel;
  final String imageUrl;
  final String presentation;
  final String popupTitle;
  final String ctaText;
  final String discountType;
  final double discountValue;
  final double minSubtotal;
  final int priority;
  final int claimCount;
  final int maxClaimsTotal;
  final bool transparentImage;
  final DateTime? startAt;
  final DateTime? endAt;

  bool get showsPopup =>
      presentation == 'popup' || presentation == 'both';
  bool get showsInline =>
      presentation == 'inline' || presentation == 'both';

  String get discountSummary {
    if (discountType == 'percent') {
      return 'ลด ${discountValue.toStringAsFixed(0)}%';
    }
    if (discountType == 'free_shipping') {
      return 'ฟรีค่าส่ง';
    }
    return 'ลด ฿${discountValue.toStringAsFixed(0)}';
  }

  bool get isClaimQuotaFull =>
      maxClaimsTotal > 0 && claimCount >= maxClaimsTotal;

  bool isWithinSchedule([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (startAt != null && current.isBefore(startAt!)) {
      return false;
    }
    if (endAt != null && current.isAfter(endAt!)) {
      return false;
    }
    return true;
  }

  factory ClaimableCouponOffer.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final display = data['display'] is Map
        ? Map<String, dynamic>.from(data['display'] as Map)
        : const <String, dynamic>{};
    final conditions = data['conditions'] is Map
        ? Map<String, dynamic>.from(data['conditions'] as Map)
        : const <String, dynamic>{};
    final discount = data['discount'] is Map
        ? Map<String, dynamic>.from(data['discount'] as Map)
        : const <String, dynamic>{};

    return ClaimableCouponOffer(
      id: id,
      name: (data['name'] ?? '').toString(),
      active: data['active'] == true,
      shortLabel: (display['shortLabel'] ?? data['name'] ?? 'คูปอง').toString(),
      imageUrl: (display['imageUrl'] ?? '').toString(),
      presentation: (display['presentation'] ?? 'inline').toString(),
      popupTitle: (display['popupTitle'] ?? data['name'] ?? 'คูปอง').toString(),
      ctaText: (display['ctaText'] ?? 'รับคูปอง').toString(),
      discountType: (discount['type'] ?? 'fixed').toString(),
      discountValue: (discount['value'] as num?)?.toDouble() ?? 0,
      minSubtotal: (conditions['minSubtotal'] as num?)?.toDouble() ?? 0,
      priority: (data['priority'] as num?)?.toInt() ?? 0,
      claimCount: (data['claimCount'] as num?)?.toInt() ?? 0,
      maxClaimsTotal: (conditions['maxClaimsTotal'] as num?)?.toInt() ?? 0,
      transparentImage: display['transparentImage'] == true,
      startAt: _parseFirestoreDate(conditions['startAt']),
      endAt: _parseFirestoreDate(conditions['endAt']),
    );
  }
}

class ClaimedCoupon {
  const ClaimedCoupon({
    required this.couponId,
    required this.code,
    required this.name,
    required this.shortLabel,
    required this.discountSummary,
    required this.imageUrl,
    required this.status,
    this.claimedAt,
    this.expiresAt,
    this.usedAt,
  });

  final String couponId;
  final String code;
  final String name;
  final String shortLabel;
  final String discountSummary;
  final String imageUrl;
  final String status;
  final DateTime? claimedAt;
  final DateTime? expiresAt;
  final DateTime? usedAt;

  bool get isActive => status == 'active';

  factory ClaimedCoupon.fromFirestore(
    String couponId,
    Map<String, dynamic> data,
  ) {
    return ClaimedCoupon(
      couponId: couponId,
      code: (data['code'] ?? '').toString(),
      name: (data['name'] ?? 'คูปอง').toString(),
      shortLabel: (data['shortLabel'] ?? data['name'] ?? 'คูปอง').toString(),
      discountSummary: (data['discountSummary'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      status: (data['status'] ?? 'active').toString(),
      claimedAt: _parseFirestoreDate(data['claimedAt']),
      expiresAt: _parseFirestoreDate(data['expiresAt']),
      usedAt: _parseFirestoreDate(data['usedAt']),
    );
  }
}

DateTime? _parseFirestoreDate(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  try {
    return (value as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

class PromotionOffer {
  const PromotionOffer({
    required this.id,
    required this.name,
    required this.active,
    required this.shortLabel,
    required this.homeBannerText,
    required this.badgeText,
    required this.discountType,
    required this.discountValue,
    required this.productIds,
    required this.shopIds,
    required this.minSubtotal,
    required this.priority,
  });

  final String id;
  final String name;
  final bool active;
  final String shortLabel;
  final String homeBannerText;
  final String badgeText;
  final String discountType;
  final double discountValue;
  final List<String> productIds;
  final List<String> shopIds;
  final double minSubtotal;
  final int priority;

  factory PromotionOffer.fromFirestore(String id, Map<String, dynamic> data) {
    final display = data['display'] is Map
        ? Map<String, dynamic>.from(data['display'] as Map)
        : const <String, dynamic>{};
    final conditions = data['conditions'] is Map
        ? Map<String, dynamic>.from(data['conditions'] as Map)
        : const <String, dynamic>{};
    final productIds = conditions['productIds'] is List
        ? (conditions['productIds'] as List)
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final shopIds = conditions['shopIds'] is List
        ? (conditions['shopIds'] as List)
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final minSubtotal = (conditions['minSubtotal'] as num?)?.toDouble() ?? 0;
    final discount = data['discount'] is Map
        ? Map<String, dynamic>.from(data['discount'] as Map)
        : const <String, dynamic>{};

    return PromotionOffer(
      id: id,
      name: (data['name'] ?? '').toString(),
      active: data['active'] == true,
      shortLabel: (display['shortLabel'] ?? data['name'] ?? 'โปรโมชั่น')
          .toString(),
      homeBannerText: (display['homeBannerText'] ?? display['shortLabel'] ?? '')
          .toString(),
      badgeText: (display['badgeText'] ?? display['shortLabel'] ?? 'ลด')
          .toString(),
      discountType: (discount['type'] ?? 'fixed').toString(),
      discountValue: (discount['value'] as num?)?.toDouble() ?? 0,
      productIds: productIds,
      shopIds: shopIds,
      minSubtotal: minSubtotal,
      priority: (data['priority'] as num?)?.toInt() ?? 0,
    );
  }
}

class CartDiscountLine {
  const CartDiscountLine({
    required this.kind,
    required this.id,
    required this.label,
    required this.amount,
    this.code,
  });

  final String kind;
  final String id;
  final String label;
  final double amount;
  final String? code;

  factory CartDiscountLine.fromPayload(Map<String, dynamic> data) {
    return CartDiscountLine(
      kind: (data['kind'] ?? '').toString(),
      id: (data['id'] ?? '').toString(),
      label: (data['label'] ?? 'ส่วนลด').toString(),
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      code: data['code']?.toString(),
    );
  }

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      'kind': kind,
      'id': id,
      'label': label,
      'amount': amount,
      if (code != null && code!.isNotEmpty) 'code': code,
    };
  }
}

class NearMissPromotion {
  const NearMissPromotion({
    required this.id,
    required this.label,
    required this.reason,
    required this.shortfall,
  });

  final String id;
  final String label;
  final String reason;
  final double shortfall;

  factory NearMissPromotion.fromPayload(Map<String, dynamic> data) {
    return NearMissPromotion(
      id: (data['id'] ?? '').toString(),
      label: (data['label'] ?? 'โปรโมชั่น').toString(),
      reason: (data['reason'] ?? '').toString(),
      shortfall: (data['shortfall'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CartCheckoutContext {
  const CartCheckoutContext({
    required this.couponCode,
    required this.discounts,
    this.checkoutQuoteId,
  });

  final String? couponCode;
  final CartDiscountSnapshot discounts;
  final String? checkoutQuoteId;
}

class CartDiscountSnapshot {
  const CartDiscountSnapshot({
    required this.promotionDiscount,
    required this.couponDiscount,
    required this.discountTotal,
    required this.discountLines,
    required this.nearMissPromotions,
    required this.appliedCouponCode,
    required this.couponError,
    required this.stackNote,
  });

  final double promotionDiscount;
  final double couponDiscount;
  final double discountTotal;
  final List<CartDiscountLine> discountLines;
  final List<NearMissPromotion> nearMissPromotions;
  final String? appliedCouponCode;
  final String? couponError;
  final String? stackNote;

  static const CartDiscountSnapshot empty = CartDiscountSnapshot(
    promotionDiscount: 0,
    couponDiscount: 0,
    discountTotal: 0,
    discountLines: <CartDiscountLine>[],
    nearMissPromotions: <NearMissPromotion>[],
    appliedCouponCode: null,
    couponError: null,
    stackNote: null,
  );

  factory CartDiscountSnapshot.fromServerPayload(Map payload) {
    final discountLines = payload['discountLines'] is List
        ? (payload['discountLines'] as List)
            .whereType<Map>()
            .map(
              (line) => CartDiscountLine.fromPayload(
                Map<String, dynamic>.from(line),
              ),
            )
            .toList(growable: false)
        : const <CartDiscountLine>[];
    final nearMiss = payload['nearMissPromotions'] is List
        ? (payload['nearMissPromotions'] as List)
            .whereType<Map>()
            .map(
              (line) => NearMissPromotion.fromPayload(
                Map<String, dynamic>.from(line),
              ),
            )
            .toList(growable: false)
        : const <NearMissPromotion>[];

    return CartDiscountSnapshot(
      promotionDiscount: (payload['promotionDiscount'] as num?)?.toDouble() ?? 0,
      couponDiscount: (payload['couponDiscount'] as num?)?.toDouble() ?? 0,
      discountTotal: (payload['discountTotal'] as num?)?.toDouble() ?? 0,
      discountLines: discountLines,
      nearMissPromotions: nearMiss,
      appliedCouponCode: payload['appliedCouponCode']?.toString(),
      couponError: payload['couponError']?.toString(),
      stackNote: payload['stackNote']?.toString(),
    );
  }
}
