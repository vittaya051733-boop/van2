import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:geolocator/geolocator.dart';

import 'public_catalog_service.dart';
import 'tax_pricing_policy.dart';

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
  const _ToppingGroup({
    required this.heading,
    required this.options,
  });

  final String? heading;
  final List<_ToppingOption> options;
}

class _IndexedToppingOption {
  const _IndexedToppingOption({
    required this.key,
    required this.option,
  });

  final String key;
  final _ToppingOption option;
}

class CategoryCatalogScreen extends StatelessWidget {
  const CategoryCatalogScreen({
    super.key,
    required this.title,
    this.serviceType = '',
    this.shopIdFilter,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.embedded = false,
    this.onBack,
  });

  final String title;
  final String serviceType;
  final String? shopIdFilter;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return Column(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: Container(
              color: const Color(0xFFF57C00),
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
          Expanded(child: _buildCatalogList()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
      ),
      body: _buildCatalogList(),
    );
  }

  Widget _buildCatalogList() {
    final normalizedShopId = shopIdFilter?.trim();
    final bool filterByShop = normalizedShopId != null && normalizedShopId.isNotEmpty;

    return StreamBuilder<List<PublicCatalogSection>>(
      stream: filterByShop
        ? PublicCatalogService.streamSectionsByShopId(normalizedShopId)
        : PublicCatalogService.streamSectionsByServiceType(serviceType),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: sections.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final section = sections[index];
              return _ShopSectionCard(
                section: section,
                customerLatitude: customerLatitude,
                customerLongitude: customerLongitude,
                onConfirmOrder: onConfirmOrder,
              );
            },
          );
        },
    );
  }
}

class _ShopSectionCard extends StatelessWidget {
  const _ShopSectionCard({
    required this.section,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
  });

  final PublicCatalogSection section;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;

  @override
  Widget build(BuildContext context) {
    final shopDistanceKm = _computeShopDistanceKm(
      customerLatitude: customerLatitude,
      customerLongitude: customerLongitude,
      shopLatitude: section.shopLatitude,
      shopLongitude: section.shopLongitude,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const double spacing = 8;
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final product in section.products)
              SizedBox(
                width: itemWidth,
                child: _ProductCard(
                  product: product,
                  shopLatitude: section.shopLatitude,
                  shopLongitude: section.shopLongitude,
                  shopDistanceKm: shopDistanceKm,
                  onConfirmOrder: onConfirmOrder,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    this.shopLatitude,
    this.shopLongitude,
    this.shopDistanceKm,
    this.onConfirmOrder,
  });

  final PublicCatalogProduct product;
  final double? shopLatitude;
  final double? shopLongitude;
  final double? shopDistanceKm;
  final ValueChanged<CartProductSelection>? onConfirmOrder;

  @override
  Widget build(BuildContext context) {
    final data = product.data;
    final List<String> thumbnails = ((data['thumbnailUrls'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList();
    final List<String> images = ((data['imageUrls'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList();
    final String? imageUrl = thumbnails.isNotEmpty
        ? thumbnails.first
        : (images.isNotEmpty ? images.first : null);
    final String name = (data['name'] ?? '').toString();
    final String description = (data['description'] ?? '').toString();
    final String cleanDescription = _cleanDescriptionWithoutToppings(description);
    final bool taxable = TaxPricingPolicy.isTaxableProduct(data);
    final num basePrice = TaxPricingPolicy.parseNumber(data['price']);
    final num adjustedBasePrice = TaxPricingPolicy.applyProductMarkup(basePrice, taxable);
    final String adjustedPriceText = TaxPricingPolicy.formatPrice(adjustedBasePrice);
    final List<_ToppingGroup> toppingGroups = _extractToppings(data);
    final int? availableStock = _extractAvailableStock(data);
    final int preparationTimeMinutes = _extractPreparationTimeMinutes(data);
    final String shopName =
        product.shopName?.trim().isNotEmpty == true ? product.shopName!.trim() : 'ร้านค้า';
    final String? distanceText = _formatDistanceKm(shopDistanceKm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.05,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    cacheManager: _localFirstImageCacheManager,
                    useOldImageOnUrlChange: true,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _ProductPlaceholder(name: name),
                  )
                : _ProductPlaceholder(name: name),
          ),
        ),
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
        if (cleanDescription.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            cleanDescription,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
          ),
        ],
        if (distanceText != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
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
        Text(
          '฿$adjustedPriceText',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFFE55A00),
              ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _showProductDetails(
              context,
              shopName: shopName,
              shopImageUrl: product.shopImageUrl,
              productName: name,
              description: cleanDescription,
              adjustedBasePrice: adjustedBasePrice,
              imageUrl: imageUrl,
                    toppingGroups: toppingGroups,
              availableStock: availableStock,
              preparationTimeMinutes: preparationTimeMinutes,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE55A00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.shopping_cart_checkout, size: 18),
            label: const Text(
              'สั่งซื้อ',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
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
  void _showProductDetails(
    BuildContext context, {
    required String shopName,
    required String? shopImageUrl,
    required String productName,
    required String description,
    required num adjustedBasePrice,
    required String? imageUrl,
    required List<_ToppingGroup> toppingGroups,
    required int? availableStock,
    required int preparationTimeMinutes,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final List<_IndexedToppingOption> indexedToppings = <_IndexedToppingOption>[
      for (var groupIndex = 0; groupIndex < toppingGroups.length; groupIndex++)
        for (var optionIndex = 0; optionIndex < toppingGroups[groupIndex].options.length; optionIndex++)
          _IndexedToppingOption(
            key: '$groupIndex:$optionIndex',
            option: toppingGroups[groupIndex].options[optionIndex],
          ),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final selectedToppings = <String>{};
        var quantity = 1;
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final bool outOfStock = availableStock != null && availableStock <= 0;
              final int remainingAfterOrder = availableStock == null
                  ? -1
                  : (availableStock - quantity).clamp(0, availableStock);
              final int maxQuantity = availableStock == null
                  ? 99
                  : (availableStock <= 0 ? 1 : availableStock);

              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                Row(
                  children: [
                    _ShopAvatar(imageUrl: shopImageUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        shopName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    color: const Color(0xFFF8FAFC),
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            cacheManager: _localFirstImageCacheManager,
                            useOldImageOnUrlChange: true,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => _ProductPlaceholder(name: productName),
                          )
                        : _ProductPlaceholder(name: productName),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  productName.isEmpty ? 'ไม่ระบุชื่อสินค้า' : productName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF4B5563),
                        ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    if (availableStock != null)
                      Expanded(
                        child: Text(
                          'สต๊อกคงเหลือ: $availableStock',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: outOfStock ? const Color(0xFFB91C1C) : const Color(0xFF1F2937),
                              ),
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          'สต๊อกคงเหลือ: ไม่จำกัด',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1F2937),
                              ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: quantity > 1
                                ? () => setModalState(() => quantity -= 1)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$quantity',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: (!outOfStock && quantity < maxQuantity)
                                ? () => setModalState(() => quantity += 1)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (availableStock != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    outOfStock
                        ? 'สินค้าหมดสต๊อกชั่วคราว'
                        : 'คงเหลือหลังสั่งครั้งนี้: $remainingAfterOrder',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: outOfStock ? const Color(0xFFB91C1C) : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                if (toppingGroups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'ท็อปปิ้ง',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2937),
                        ),
                  ),
                  const SizedBox(height: 6),
                  Column(
                    children: [
                      for (var groupIndex = 0; groupIndex < toppingGroups.length; groupIndex++) ...[
                        if (toppingGroups[groupIndex].heading?.isNotEmpty == true) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 2),
                            child: Text(
                              toppingGroups[groupIndex].heading!,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF92400E),
                                  ),
                            ),
                          ),
                        ],
                        for (var optionIndex = 0; optionIndex < toppingGroups[groupIndex].options.length; optionIndex++)
                          Builder(
                            builder: (context) {
                              final option = toppingGroups[groupIndex].options[optionIndex];
                              final selectionKey = '$groupIndex:$optionIndex';
                              final isChecked = selectedToppings.contains(selectionKey);
                              return CheckboxListTile(
                                value: isChecked,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                activeColor: const Color(0xFFE55A00),
                                title: Text(
                                  option.displayLabel,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: const Color(0xFF374151),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                onChanged: (value) {
                                  setModalState(() {
                                    if (value == true) {
                                      selectedToppings.add(selectionKey);
                                    } else {
                                      selectedToppings.remove(selectionKey);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '฿${TaxPricingPolicy.formatPrice(adjustedBasePrice)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFE55A00),
                      ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.bottomRight,
                  child: FilledButton.icon(
                    onPressed: outOfStock
                        ? null
                        : () {
                      final selectedOptions = indexedToppings
                          .where((entry) => selectedToppings.contains(entry.key))
                          .map((entry) => entry.option)
                          .toList(growable: false);
                      final selectedNames = selectedOptions
                          .map((option) => option.label)
                          .toList(growable: false);
                      final toppingTotal = selectedOptions.fold<num>(
                        0,
                        (sum, option) => sum + option.adjustedPrice,
                      );
                      final unitPrice = adjustedBasePrice + toppingTotal;
                      final lineTotal = unitPrice * quantity;
                      onConfirmOrder?.call(
                        CartProductSelection(
                          productId: product.id,
                          shopId: product.shopId,
                          shopName: shopName,
                          shopLatitude: product.shopLatitude ?? shopLatitude,
                          shopLongitude: product.shopLongitude ?? shopLongitude,
                          productName: productName.isEmpty ? 'สินค้า' : productName,
                          unitPrice: unitPrice,
                          imageUrl: imageUrl,
                          selectedToppings: selectedNames,
                          quantity: quantity,
                          availableStock: availableStock,
                          preparationTimeMinutes: preparationTimeMinutes,
                        ),
                      );
                      Navigator.of(sheetContext).pop();
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(
                            'เพิ่ม ${productName.isEmpty ? 'สินค้า' : productName} จำนวน $quantity ชิ้นแล้ว (฿${TaxPricingPolicy.formatPrice(lineTotal)})',
                          ),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      minimumSize: const Size(0, 38),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text(
                      'ยืนยัน',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
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
    const keys = <String>['toppings', 'topping', 'addons', 'addOns', 'options', 'extraOptions'];

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
    final headingMatches = headingPattern.allMatches(text).toList(growable: false);
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
      final options = _extractDelimitedOptions(text.substring(bodyStart, bodyEnd));
      if (heading.isNotEmpty || options.isNotEmpty) {
        groups.add(_ToppingGroup(heading: heading.isEmpty ? null : heading, options: options));
      }
    }

    return groups.where((group) => group.options.isNotEmpty).toList(growable: false);
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
}

class _ProductPlaceholder extends StatelessWidget {
  const _ProductPlaceholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final String display = name.isEmpty ? 'สินค้า' : name.substring(0, name.length > 18 ? 18 : name.length);
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
              errorWidget: (_, __, ___) => const Icon(Icons.storefront, color: Color(0xFF9A3412)),
            )
          : const Icon(Icons.storefront, color: Color(0xFF9A3412)),
    );
  }
}

double? _computeShopDistanceKm({
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
