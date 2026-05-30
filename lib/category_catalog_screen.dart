import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:geolocator/geolocator.dart';

import 'public_catalog_service.dart';
import 'tax_pricing_policy.dart';

part 'catalog_product_detail_pager.dart';
part 'catalog_shop_browser.dart';

class _LocalFirstImageCacheManager extends CacheManager {
  _LocalFirstImageCacheManager._()
    : super(
        Config(
          'van2_local_first_images',
          stalePeriod: const Duration(days: 3650),
          maxNrOfCacheObjects: 2000,
        ),
      );

  static final _LocalFirstImageCacheManager instance =
      _LocalFirstImageCacheManager._();
}

final CacheManager _localFirstImageCacheManager =
    _LocalFirstImageCacheManager.instance;

class CartProductSelection {
  const CartProductSelection({
    required this.productId,
    required this.shopId,
    required this.shopName,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.productName,
    required this.unitPrice,
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
    required this.adjustedPrice,
    required this.displayLabel,
  });

  final String label;
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
                  child: _buildCatalogList(),
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
      body: _buildCatalogList(),
    );
  }

  Widget _buildCatalogList() {
    final normalizedShopId = shopIdFilter?.trim();
    final bool filterByShop =
        normalizedShopId != null && normalizedShopId.isNotEmpty;

    final Stream<List<PublicCatalogSection>> sectionsStream;
    if (filterByShop) {
      sectionsStream = PublicCatalogService.streamSectionsByShopId(
        normalizedShopId,
      );
    } else if (nationwideShippingOnly) {
      sectionsStream = PublicCatalogService.streamNationwideShippingSections();
    } else {
      sectionsStream = PublicCatalogService.streamSectionsByServiceType(
        serviceType,
      );
    }

    return StreamBuilder<List<PublicCatalogSection>>(
      stream: sectionsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
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

        final sections = snapshot.data ?? const <PublicCatalogSection>[];
        if (sections.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                filterByShop
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
            customerLatitude: customerLatitude,
            customerLongitude: customerLongitude,
            onConfirmOrder: onConfirmOrder,
            onNavigateToCart: onNavigateToCart,
          );
        }

        return _CatalogShopPager(
          sections: sections,
          customerLatitude: customerLatitude,
          customerLongitude: customerLongitude,
          onConfirmOrder: onConfirmOrder,
          onNavigateToCart: onNavigateToCart,
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
    this.onConfirmOrder,
    this.onNavigateToCart,
    this.compact = false,
  });

  final PublicCatalogProduct product;
  final List<PublicCatalogProduct>? shopProducts;
  final double? shopLatitude;
  final double? shopLongitude;
  final double? shopDistanceKm;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final data = product.data;
    final List<String> thumbnails =
        ((data['thumbnailUrls'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .where((url) => url.trim().isNotEmpty)
            .toList();
    final List<String> images =
        ((data['imageUrls'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .where((url) => url.trim().isNotEmpty)
            .toList();
    final String? imageUrl = thumbnails.isNotEmpty
        ? thumbnails.first
        : (images.isNotEmpty ? images.first : null);
    final String name = (data['name'] ?? '').toString();
    final String description = (data['description'] ?? '').toString();
    final String cleanDescription = _cleanDescriptionWithoutToppings(
      description,
    );
    final bool taxable = TaxPricingPolicy.isTaxableProduct(data);
    final num basePrice = TaxPricingPolicy.parseNumber(data['price']);
    final num adjustedBasePrice = TaxPricingPolicy.applyProductMarkup(
      basePrice,
      taxable,
    );
    final String adjustedPriceText = TaxPricingPolicy.formatPrice(
      adjustedBasePrice,
    );
    final String? distanceText = compact
        ? null
        : _formatDistanceKm(shopDistanceKm);

    void openProductDetails() =>
        unawaited(_openProductDetailPager(context, shopProducts: shopProducts));

    final Widget imageTile = _buildProductImageTile(
      context: context,
      imageUrl: imageUrl,
      name: name,
      onTap: openProductDetails,
      fixedHeight: compact ? 92 : null,
    );

    final Widget priceRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text(
            '฿$adjustedPriceText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (compact
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
        const SizedBox(height: 8),
        Text(
          name.isNotEmpty ? name : 'ไม่ระบุชื่อสินค้า',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        if (cleanDescription.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            cleanDescription,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
          ),
        ],
        if (distanceText != null) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(
                Icons.near_me_outlined,
                size: 14,
                color: Color(0xFF6B7280),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'ห่าง $distanceText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        priceRow,
      ],
    );
  }

  Widget _buildProductImageTile({
    required BuildContext context,
    required String? imageUrl,
    required String name,
    required VoidCallback onTap,
    double? fixedHeight,
  }) {
    final Widget imageContent = Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              cacheManager: _localFirstImageCacheManager,
              useOldImageOnUrlChange: true,
              width: double.infinity,
              height: fixedHeight,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _ProductPlaceholder(name: name),
            )
          : _ProductPlaceholder(name: name),
    );

    return GestureDetector(
      onTap: onTap,
      child: fixedHeight == null
          ? AspectRatio(aspectRatio: 1.05, child: imageContent)
          : SizedBox(
              height: fixedHeight,
              width: double.infinity,
              child: imageContent,
            ),
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
      onConfirmOrder: onConfirmOrder,
      onNavigateToCart: onNavigateToCart,
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
  final display = adjusted > 0
      ? '$label (+฿${TaxPricingPolicy.formatPrice(adjusted)})'
      : label;
  return _ToppingOption(
    label: label,
    adjustedPrice: adjusted,
    displayLabel: display,
  );
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

class _ProductPlaceholder extends StatelessWidget {
  const _ProductPlaceholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final String display = name.isEmpty
        ? 'สินค้า'
        : name.substring(0, name.length > 18 ? 18 : name.length);
    return Container(
      color: const Color(0xFFFFEDD5),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          display,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF9A3412),
          ),
        ),
      ),
    );
  }
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
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              cacheManager: _localFirstImageCacheManager,
              useOldImageOnUrlChange: true,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
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
  const textAndActionsHeight = 152.0;
  final height = width / 1.05 + textAndActionsHeight;
  return (width: width, height: height);
}
