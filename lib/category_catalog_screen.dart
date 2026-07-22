import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'catalog_search_utils.dart';
import 'public_catalog_service.dart';
import 'services/catalog_share.dart';
import 'services/favorites_service.dart';
import 'services/app_image_prefetch.dart';
import 'services/catalog_product_media_prefetch.dart';
import 'tax_pricing_policy.dart';
import 'utils/catalog_product_image_url.dart';
import 'utils/delivery_eta_policy.dart';
import 'widgets/cached_app_image.dart';
import 'widgets/catalog_product_media_carousel.dart';
import 'widgets/product_comment_section.dart';
import 'widgets/product_discount_badge.dart';
import 'widgets/product_discount_price.dart';
import 'widgets/product_reaction_bar.dart';

part 'catalog_product_detail_pager.dart';
part 'catalog_shop_browser.dart';

class CartProductSelection {
  const CartProductSelection({
    required this.productId,
    required this.shopId,
    required this.shopName,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.productName,
    required this.unitPrice,
    required this.merchantBasePrice,
    required this.discountPercent,
    required this.merchantUnitPayout,
    required this.imageUrl,
    required this.selectedToppings,
    required this.quantity,
    required this.availableStock,
    required this.preparationTimeMinutes,
    this.parcelWeightGrams = 1000,
    this.parcelLengthCm,
    this.parcelWidthCm,
    this.parcelHeightCm,
  });

  final String productId;
  final String shopId;
  final String shopName;
  final double? shopLatitude;
  final double? shopLongitude;
  final String productName;
  final num unitPrice;
  final num merchantBasePrice;
  final double discountPercent;
  final num merchantUnitPayout;
  final String? imageUrl;
  final List<String> selectedToppings;
  final int quantity;
  final int? availableStock;
  final int preparationTimeMinutes;
  final int parcelWeightGrams;
  final double? parcelLengthCm;
  final double? parcelWidthCm;
  final double? parcelHeightCm;
}

class _ToppingOption {
  const _ToppingOption({
    required this.label,
    required this.rawPrice,
    required this.adjustedPrice,
    required this.displayLabel,
  });

  final String label;
  final num rawPrice;
  final num adjustedPrice;
  final String displayLabel;
}

class _ToppingGroup {
  const _ToppingGroup({required this.heading, required this.options});

  final String? heading;
  final List<_ToppingOption> options;
}

class _IndexedToppingOption {
  const _IndexedToppingOption({required this.key, required this.option});

  final String key;
  final _ToppingOption option;
}

class CategoryCatalogScreen extends StatelessWidget {
  const CategoryCatalogScreen({
    super.key,
    required this.title,
    this.serviceType = '',
    this.shopIdFilter,
    this.nationwideShippingOnly = false,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
    this.embedded = false,
    this.onBack,
  });

  final String title;
  final String serviceType;
  final String? shopIdFilter;
  final bool nationwideShippingOnly;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFFF57C00),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: ColoredBox(
          color: const Color(0xFFF57C00),
          child: Column(
            children: <Widget>[
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: const Color(0xFFF4FAFB),
                  child: _CategoryCatalogBody(
                    title: title,
                    serviceType: serviceType,
                    shopIdFilter: shopIdFilter,
                    nationwideShippingOnly: nationwideShippingOnly,
                    customerLatitude: customerLatitude,
                    customerLongitude: customerLongitude,
                    onConfirmOrder: onConfirmOrder,
                    onNavigateToCart: onNavigateToCart,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFFF57C00),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      body: _CategoryCatalogBody(
        title: title,
        serviceType: serviceType,
        shopIdFilter: shopIdFilter,
        nationwideShippingOnly: nationwideShippingOnly,
        customerLatitude: customerLatitude,
        customerLongitude: customerLongitude,
        onConfirmOrder: onConfirmOrder,
        onNavigateToCart: onNavigateToCart,
      ),
    );
  }
}

class _CategoryCatalogBody extends StatefulWidget {
  const _CategoryCatalogBody({
    required this.title,
    required this.serviceType,
    this.shopIdFilter,
    this.nationwideShippingOnly = false,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final String title;
  final String serviceType;
  final String? shopIdFilter;
  final bool nationwideShippingOnly;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<_CategoryCatalogBody> createState() => _CategoryCatalogBodyState();
}

class _CategoryCatalogBodyState extends State<_CategoryCatalogBody> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<PublicCatalogSection>? _initialSections;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateFromLocalCache());
  }

  Future<List<PublicCatalogSection>> _loadSectionsFromLocalCache() {
    final normalizedShopId = widget.shopIdFilter?.trim();
    if (normalizedShopId != null && normalizedShopId.isNotEmpty) {
      return PublicCatalogService.sectionsFromLocalCache(
        shopId: normalizedShopId,
      );
    }
    if (widget.nationwideShippingOnly) {
      return PublicCatalogService.sectionsFromLocalCache(
        nationwideShippingOnly: true,
      );
    }
    if (widget.serviceType.trim().isNotEmpty) {
      return PublicCatalogService.sectionsFromLocalCache(
        serviceType: widget.serviceType,
      );
    }
    return Future<List<PublicCatalogSection>>.value(
      const <PublicCatalogSection>[],
    );
  }

  String? get _prefetchCategoryKey {
    if (widget.nationwideShippingOnly) {
      return AppImagePrefetch.nationwideKey;
    }
    if (widget.serviceType.trim().isNotEmpty) {
      return AppImagePrefetch.serviceTypeKey(widget.serviceType);
    }
    return null;
  }

  Future<void> _hydrateFromLocalCache() async {
    try {
      final sections = await _loadSectionsFromLocalCache();
      if (!mounted || sections.isEmpty) {
        return;
      }
      setState(() => _initialSections = sections);
      if (widget.nationwideShippingOnly) {
        await AppImagePrefetch.continueWarmNationwide();
      } else if (widget.serviceType.trim().isNotEmpty) {
        await AppImagePrefetch.continueWarmForServiceType(widget.serviceType);
      } else {
        await AppImagePrefetch.prefetchCatalogSectionsImmediate(sections);
      }
    } catch (_) {
      // StreamBuilder still paints from network/cache.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _searchHint {
    if (widget.nationwideShippingOnly) {
      return 'ค้นหาสินค้าส่งทั่วประเทศ';
    }
    final normalizedShopId = widget.shopIdFilter?.trim();
    if (normalizedShopId != null && normalizedShopId.isNotEmpty) {
      return 'ค้นหาสินค้าในร้านนี้';
    }
    if (widget.serviceType.trim().isNotEmpty) {
      return 'ค้นหาสินค้าในหมวด${widget.title}';
    }
    return 'ค้นหาสินค้า';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CatalogSearchBar(
          controller: _searchController,
          hintText: _searchHint,
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        Expanded(child: _buildCatalogList()),
      ],
    );
  }

  Widget _buildCatalogList() {
    final normalizedShopId = widget.shopIdFilter?.trim();
    final bool filterByShop =
        normalizedShopId != null && normalizedShopId.isNotEmpty;

    final Stream<List<PublicCatalogSection>> sectionsStream;
    if (filterByShop) {
      sectionsStream = PublicCatalogService.streamSectionsByShopId(
        normalizedShopId,
      );
    } else if (widget.nationwideShippingOnly) {
      sectionsStream = PublicCatalogService.streamNationwideShippingSections();
    } else {
      sectionsStream = PublicCatalogService.streamSectionsByServiceType(
        widget.serviceType,
      );
    }

    return StreamBuilder<List<PublicCatalogSection>>(
      stream: sectionsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData && _initialSections == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'โหลดข้อมูลไม่สำเร็จ: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final rawSections = snapshot.hasData
            ? snapshot.data!
            : (_initialSections ?? const <PublicCatalogSection>[]);
        if (rawSections.isEmpty &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final sections = CatalogSearchUtils.filterSections(
          rawSections,
          _searchQuery,
        );
        if (sections.isNotEmpty) {
          AppImagePrefetch.scheduleCatalogSectionsPrefetch(
            sections,
            categoryKey: _prefetchCategoryKey,
          );
        }

        if (sections.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _searchQuery.trim().isNotEmpty
                    ? 'ไม่พบสินค้าที่ตรงกับ "${_searchQuery.trim()}"'
                    : filterByShop
                    ? 'ร้านนี้ยังไม่มีสินค้า active ให้สั่งออนไลน์ตอนนี้'
                    : 'ยังไม่มีร้านที่เปิดอยู่ในหมวดนี้ หรือร้านยังไม่ได้เลือกสินค้าแสดง',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (filterByShop) {
          return _ShopCatalogPage(
            section: sections.first,
            customerLatitude: widget.customerLatitude,
            customerLongitude: widget.customerLongitude,
            onConfirmOrder: widget.onConfirmOrder,
            onNavigateToCart: widget.onNavigateToCart,
          );
        }

        return _CatalogShopsFeed(
          sections: sections,
          customerLatitude: widget.customerLatitude,
          customerLongitude: widget.customerLongitude,
          onConfirmOrder: widget.onConfirmOrder,
          onNavigateToCart: widget.onNavigateToCart,
        );
      },
    );
  }
}

class CatalogProductCard extends StatelessWidget {
  const CatalogProductCard({
    super.key,
    required this.product,
    this.shopProducts,
    this.shopLatitude,
    this.shopLongitude,
    this.shopDistanceKm,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
    this.compact = false,
    this.showRatingSummary = true,
  });

  final PublicCatalogProduct product;
  final List<PublicCatalogProduct>? shopProducts;
  final double? shopLatitude;
  final double? shopLongitude;
  final double? shopDistanceKm;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;
  final bool compact;
  final bool showRatingSummary;

  @override
  Widget build(BuildContext context) {
    final data = product.data;
    final String name = (data['name'] ?? '').toString();
    final String description = (data['description'] ?? '').toString();
    final String cleanDescription = _cleanDescriptionWithoutToppings(
      description,
    );
    final String? distanceText = compact
        ? null
        : buildCatalogDeliveryDistanceLabel(
            shopDistanceKm: shopDistanceKm,
            preparationTimeMinutes: _extractPreparationTimeMinutes(data),
          );

    void openProductDetails() =>
        unawaited(_openProductDetailPager(context, shopProducts: shopProducts));

    final Widget imageTile = wrapCatalogImageWithDiscountBadge(
      productData: data,
      productId: product.id,
      shopId: product.shopId,
      compact: compact,
      child: CatalogProductMediaCarousel(
        productData: data,
        name: name,
        compact: compact,
        fixedHeight: compact ? 92 : null,
        borderRadius: compact ? 14 : 18,
        onTap: openProductDetails,
      ),
    );

    final Widget priceRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: ProductDiscountPrice(
            productData: data,
            productId: product.id,
            shopId: product.shopId,
            compact: compact,
            style: (compact
                    ? Theme.of(context).textTheme.titleSmall
                    : Theme.of(context).textTheme.titleMedium)
                ?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFFE55A00),
            ),
          ),
        ),
        Material(
          color: const Color(0xFFE55A00),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: openProductDetails,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: compact ? 30 : 34,
              height: compact ? 30 : 34,
              child: Icon(
                Icons.add,
                color: Colors.white,
                size: compact ? 20 : 22,
              ),
            ),
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          imageTile,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      name.isNotEmpty ? name : 'ไม่ระบุชื่อสินค้า',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        height: 1.12,
                      ),
                    ),
                  ),
                  if (showRatingSummary)
                    _ProductRatingSummary(productId: product.id, compact: true),
                  priceRow,
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        imageTile,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 8),
              Text(
                name.isNotEmpty ? name : 'ไม่ระบุชื่อสินค้า',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                  height: 1.15,
                ),
              ),
              if (showRatingSummary)
                _ProductRatingSummary(productId: product.id),
              if (cleanDescription.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  cleanDescription,
                  maxLines: distanceText != null ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    height: 1.2,
                  ),
                ),
              ],
              if (distanceText != null) ...<Widget>[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.near_me_outlined,
                        size: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        distanceText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              priceRow,
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openProductDetailPager(
    BuildContext context, {
    List<PublicCatalogProduct>? shopProducts,
  }) async {
    var products = shopProducts;
    if (products == null || products.isEmpty) {
      products = await PublicCatalogService.listActiveProductsForShop(
        product.shopId,
      );
    }
    if (products.isEmpty) {
      products = <PublicCatalogProduct>[product];
    }

    var initialIndex = products.indexWhere((entry) => entry.id == product.id);
    if (initialIndex < 0) {
      products = <PublicCatalogProduct>[product, ...products];
      initialIndex = 0;
    }

    if (!context.mounted) {
      return;
    }

    showCatalogProductDetailPager(
      context: context,
      products: products,
      initialIndex: initialIndex,
      customerLatitude: customerLatitude,
      customerLongitude: customerLongitude,
      onConfirmOrder: onConfirmOrder,
      onNavigateToCart: onNavigateToCart,
    );
  }
}

class _ProductRatingSummary extends StatelessWidget {
  const _ProductRatingSummary({required this.productId, this.compact = false});

  final String productId;
  final bool compact;

  static final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>>
  _ratingFutures = <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};

  static Future<DocumentSnapshot<Map<String, dynamic>>> _ratingFuture(
    String productId,
  ) {
    return _ratingFutures.putIfAbsent(
      productId,
      () => FirebaseFirestore.instance
          .collection('product_review_stats')
          .doc(productId)
          .get(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedId = productId.trim();
    if (normalizedId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _ratingFuture(normalizedId),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final count = (data?['ratingCount'] as num?)?.toInt() ?? 0;
        final average = (data?['ratingAverage'] as num?)?.toDouble() ?? 0;
        if (count <= 0 || average <= 0) {
          return const SizedBox.shrink();
        }

        final label = '${average.toStringAsFixed(1)} ($count)';
        return Padding(
          padding: EdgeInsets.only(top: compact ? 2 : 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.star_rounded,
                size: compact ? 14 : 16,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? Theme.of(context).textTheme.labelSmall
                              : Theme.of(context).textTheme.bodySmall)
                          ?.copyWith(
                            color: const Color(0xFF92400E),
                            fontWeight: FontWeight.w800,
                          ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProductRecentReviews extends StatelessWidget {
  const _ProductRecentReviews({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    if (productId.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('product_reviews')
          .where('productId', isEqualTo: productId)
          .where('status', isEqualTo: 'visible')
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final reviews = docs.map((doc) => doc.data()).toList(growable: false)
          ..sort((left, right) {
            final leftTs = left['updatedAt'] ?? left['createdAt'];
            final rightTs = right['updatedAt'] ?? right['createdAt'];
            final leftMs = leftTs is Timestamp
                ? leftTs.millisecondsSinceEpoch
                : 0;
            final rightMs = rightTs is Timestamp
                ? rightTs.millisecondsSinceEpoch
                : 0;
            return rightMs.compareTo(leftMs);
          });

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'รีวิวล่าสุด',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                for (final review in reviews) ...<Widget>[
                  _ProductReviewPreview(review: review),
                  if (review != reviews.last) const Divider(height: 16),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductReviewPreview extends StatelessWidget {
  const _ProductReviewPreview({required this.review});

  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = (review['comment'] as String?)?.trim() ?? '';
    final imageUrls = ((review['imageUrls'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (var index = 1; index <= 5; index++)
              Icon(
                index <= rating
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                size: 16,
                color: const Color(0xFFF59E0B),
              ),
          ],
        ),
        if (comment.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            comment,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF374151),
              height: 1.35,
            ),
          ),
        ],
        if (imageUrls.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: imageUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: CachedAppImage(
                      imageUrl: imageUrls[index],
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      lightweight: true,
                      errorWidget: const ColoredBox(
                        color: Color(0xFFF3F4F6),
                        child: Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

int? _extractAvailableStock(Map<String, dynamic> data) {
  const stockKeys = <String>[
    'stock',
    'quantity',
    'qty',
    'availableStock',
    'remainingStock',
    'inventory',
  ];

  for (final key in stockKeys) {
    final parsed = _parseNonNegativeInt(data[key]);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

int _extractPreparationTimeMinutes(Map<String, dynamic> data) {
  final direct = _parseNonNegativeInt(data['preparationTimeMinutes']);
  if (direct != null && direct > 0) {
    return direct.clamp(1, 240).toInt();
  }
  final durationMs = _parseNonNegativeInt(data['preparingDuration']);
  if (durationMs != null && durationMs > 0) {
    return (durationMs / 60000).ceil().clamp(1, 240).toInt();
  }
  return 10;
}

int _extractParcelWeightGrams(Map<String, dynamic> data) {
  final raw =
      data['parcelWeightGrams'] ?? data['weightGrams'] ?? data['weight'];
  if (raw is num) {
    return raw <= 0 ? 1000 : raw.toInt().clamp(1, 30000);
  }

  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);
    final amount = match == null ? null : double.tryParse(match.group(1)!);
    if (amount == null || amount <= 0) {
      return 1000;
    }
    if (normalized.contains('kg') || normalized.contains('กก')) {
      return (amount * 1000).round().clamp(1, 30000);
    }
    return amount.round().clamp(1, 30000);
  }

  return 1000;
}

double? _parsePositiveDouble(Object? value) {
  if (value is num) {
    return value > 0 ? value.toDouble() : null;
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    return parsed != null && parsed > 0 ? parsed : null;
  }
  return null;
}

int? _parseNonNegativeInt(dynamic value) {
  if (value is num) {
    return value < 0 ? 0 : value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return null;
    }
    return parsed < 0 ? 0 : parsed;
  }
  return null;
}

List<_ToppingGroup> _extractToppings(Map<String, dynamic> data) {
  const keys = <String>[
    'toppings',
    'topping',
    'addons',
    'addOns',
    'options',
    'extraOptions',
  ];

  for (final key in keys) {
    final raw = data[key];
    final values = _parseToppingValues(raw);
    if (values.isNotEmpty) {
      return values;
    }
  }

  return const <_ToppingGroup>[];
}

List<_ToppingGroup> _parseToppingValues(dynamic raw) {
  if (raw is String) {
    final structured = _extractStructuredToppingGroups(raw);
    if (structured.isNotEmpty) {
      return structured;
    }

    final parts = raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map(_buildToppingOption)
        .toList(growable: false);
    return parts.isEmpty
        ? const <_ToppingGroup>[]
        : <_ToppingGroup>[_ToppingGroup(heading: null, options: parts)];
  }

  if (raw is List) {
    final result = <_ToppingGroup>[];
    for (final item in raw) {
      if (item is String) {
        final structured = _extractStructuredToppingGroups(item);
        if (structured.isNotEmpty) {
          result.addAll(structured);
          continue;
        }

        final value = item.trim();
        if (value.isNotEmpty) {
          result.add(
            _ToppingGroup(
              heading: null,
              options: <_ToppingOption>[_buildToppingOption(value)],
            ),
          );
        }
        continue;
      }

      if (item is Map) {
        final map = item.cast<Object?, Object?>();
        for (final key in <String>['name', 'label', 'title']) {
          final value = (map[key] ?? '').toString().trim();
          if (value.isNotEmpty) {
            result.add(
              _ToppingGroup(
                heading: null,
                options: <_ToppingOption>[
                  _buildToppingOption(
                    value,
                    explicitPrice: TaxPricingPolicy.parseNumber(map['price']),
                  ),
                ],
              ),
            );
            break;
          }
        }
      }
    }

    return result;
  }

  return const <_ToppingGroup>[];
}

List<_ToppingGroup> _extractStructuredToppingGroups(String source) {
  final text = source.trim();
  if (!text.contains('+') && !text.contains('(')) {
    return const <_ToppingGroup>[];
  }

  final headingPattern = RegExp(r'\(([^()]+)\)');
  final headingMatches = headingPattern
      .allMatches(text)
      .toList(growable: false);
  if (headingMatches.isEmpty) {
    final options = _extractDelimitedOptions(text);
    return options.isEmpty
        ? const <_ToppingGroup>[]
        : <_ToppingGroup>[_ToppingGroup(heading: null, options: options)];
  }

  final groups = <_ToppingGroup>[];

  final leadingOptions = _extractDelimitedOptions(
    text.substring(0, headingMatches.first.start),
  );
  if (leadingOptions.isNotEmpty) {
    groups.add(_ToppingGroup(heading: null, options: leadingOptions));
  }

  for (var index = 0; index < headingMatches.length; index++) {
    final match = headingMatches[index];
    final heading = (match.group(1) ?? '').trim();
    final bodyStart = match.end;
    final bodyEnd = index + 1 < headingMatches.length
        ? headingMatches[index + 1].start
        : text.length;
    final options = _extractDelimitedOptions(
      text.substring(bodyStart, bodyEnd),
    );
    if (heading.isNotEmpty || options.isNotEmpty) {
      groups.add(
        _ToppingGroup(
          heading: heading.isEmpty ? null : heading,
          options: options,
        ),
      );
    }
  }

  return groups
      .where((group) => group.options.isNotEmpty)
      .toList(growable: false);
}

List<_ToppingOption> _extractDelimitedOptions(String source) {
  final parts = source
      .split('+')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .map(_buildToppingOption)
      .toList(growable: false);
  return parts;
}

_ToppingOption _buildToppingOption(String value, {num? explicitPrice}) {
  final label = value.trim();
  final num rawPrice = explicitPrice ?? _extractTrailingPrice(label) ?? 0;
  final adjusted = TaxPricingPolicy.applyToppingMarkup(rawPrice);
  final cleanName = _cleanToppingLabel(label, rawPrice);
  final display = adjusted > 0
      ? '$cleanName +฿${TaxPricingPolicy.formatPrice(adjusted)}'
      : cleanName;
  return _ToppingOption(
    label: cleanName,
    rawPrice: rawPrice,
    adjustedPrice: adjusted,
    displayLabel: display,
  );
}

String _cleanToppingLabel(String label, num rawPrice) {
  var name = label.trim();
  if (rawPrice > 0) {
    name = name.replaceAll(RegExp(r'(\d+(?:\.\d+)?)\s*$'), '').trim();
    name = name.replaceAll(RegExp(r'[+\-–—]\s*$'), '').trim();
  }
  return name.isEmpty ? label.trim() : name;
}

num? _extractTrailingPrice(String value) {
  final match = RegExp(r'(\d+(?:\.\d+)?)\s*$').firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  return TaxPricingPolicy.parseNumber(match.group(1));
}

String _cleanDescriptionWithoutToppings(String source) {
  if (source.trim().isEmpty) {
    return '';
  }

  var cleaned = source;
  cleaned = cleaned.replaceAll(RegExp(r'\([^()]+\)'), ' ');
  cleaned = cleaned.replaceAll(RegExp(r'\+[^+]+\+'), ' ');
  cleaned = cleaned.replaceAll(RegExp(r'\+[^+]*?\d+(?:\.\d+)?'), '');
  cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  cleaned = cleaned.replaceAll(RegExp(r'^[,;|\-\s]+'), '').trim();
  cleaned = cleaned.replaceAll(RegExp(r'[,;|\-\s]+$'), '').trim();
  return cleaned;
}

class _ShopAvatar extends StatelessWidget {
  const _ShopAvatar({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDD5),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? CachedAppImage(
              imageUrl: imageUrl!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(16),
              lightweight: true,
              errorWidget:
                  const Icon(Icons.storefront, color: Color(0xFF9A3412)),
            )
          : const Icon(Icons.storefront, color: Color(0xFF9A3412)),
    );
  }
}

double? computeCatalogShopDistanceKm({
  required double? customerLatitude,
  required double? customerLongitude,
  required double? shopLatitude,
  required double? shopLongitude,
}) {
  if (customerLatitude == null ||
      customerLongitude == null ||
      shopLatitude == null ||
      shopLongitude == null) {
    return null;
  }

  final meters = Geolocator.distanceBetween(
    customerLatitude,
    customerLongitude,
    shopLatitude,
    shopLongitude,
  );
  return meters / 1000;
}

bool _isRecentlyUpdatedShop(DateTime? updatedAt) {
  if (updatedAt == null) {
    return false;
  }
  return DateTime.now().difference(updatedAt) <= const Duration(days: 14);
}

String? buildCatalogDeliveryDistanceLabel({
  required double? shopDistanceKm,
  required int preparationTimeMinutes,
}) {
  final distanceText = _formatDistanceKm(shopDistanceKm);
  if (distanceText == null) {
    return null;
  }

  final totalMinutes = DeliveryEtaPolicy.estimateTotalDeliveryMinutes(
    preparationTimeMinutes: preparationTimeMinutes,
    straightDistanceKm: shopDistanceKm,
  );
  return 'ห่าง $distanceText · ส่งถึง ~$totalMinutes นาที';
}

String? _formatDistanceKm(double? distanceKm) {
  if (distanceKm == null) {
    return null;
  }

  if (distanceKm < 1) {
    return '${(distanceKm * 1000).round()} ม.';
  }

  return '${distanceKm.toStringAsFixed(distanceKm >= 10 ? 0 : 1)} กม.';
}

/// Same width/height as one cell in the 2-column catalog grid (ร้านอาหาร/ตลาด/ฯลฯ).
({double width, double height}) catalogGridProductCardSize(
  BuildContext context,
) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  const catalogHorizontalPadding = 40.0;
  const columnGap = 8.0;
  final width = (screenWidth - catalogHorizontalPadding - columnGap) / 2;
  const textAndActionsHeight = 166.0;
  final height = width / 1.05 + textAndActionsHeight;
  return (width: width, height: height);
}
