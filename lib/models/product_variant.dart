import 'dart:math';

import '../utils/catalog_product_image_url.dart';

/// One purchasable SKU: image + optional size/color + price + stock.
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.size = '',
    this.color = '',
    required this.price,
    required this.stock,
    this.isActive = true,
  });

  final String id;
  final String imageUrl;
  final String thumbnailUrl;
  final String size;
  final String color;
  final double price;
  final int stock;
  final bool isActive;

  String get label {
    final parts = <String>[
      if (color.trim().isNotEmpty) color.trim(),
      if (size.trim().isNotEmpty) size.trim(),
    ];
    return parts.isEmpty ? 'ตัวเลือก' : parts.join(' · ');
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      if (size.trim().isNotEmpty) 'size': size.trim(),
      if (color.trim().isNotEmpty) 'color': color.trim(),
      'price': price,
      'stock': stock,
      'isActive': isActive,
    };
  }

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: (map['id'] as String?)?.trim() ?? '',
      imageUrl: (map['imageUrl'] as String?)?.trim() ?? '',
      thumbnailUrl: (map['thumbnailUrl'] as String?)?.trim() ??
          (map['imageUrl'] as String?)?.trim() ??
          '',
      size: (map['size'] as String?)?.trim() ?? '',
      color: (map['color'] as String?)?.trim() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] != false,
    );
  }

  ProductVariant copyWith({
    String? id,
    String? imageUrl,
    String? thumbnailUrl,
    String? size,
    String? color,
    double? price,
    int? stock,
    bool? isActive,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      size: size ?? this.size,
      color: color ?? this.color,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Editable row before images are uploaded (uses image index).
class ProductVariantDraft {
  ProductVariantDraft({
    String? id,
    required this.imageIndex,
    this.size = '',
    this.color = '',
    this.priceText = '',
    this.stockText = '',
  }) : id = id ?? ProductVariantSupport.generateId();

  final String id;
  final int imageIndex;
  String size;
  String color;
  String priceText;
  String stockText;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'imageIndex': imageIndex,
        'size': size,
        'color': color,
        'priceText': priceText,
        'stockText': stockText,
      };

  factory ProductVariantDraft.fromJson(Map<String, dynamic> json) {
    return ProductVariantDraft(
      id: (json['id'] as String?)?.trim(),
      imageIndex: (json['imageIndex'] as num?)?.toInt() ?? 0,
      size: (json['size'] as String?) ?? '',
      color: (json['color'] as String?) ?? '',
      priceText: (json['priceText'] as String?) ?? '',
      stockText: (json['stockText'] as String?) ?? '',
    );
  }
}

class ProductVariantSupport {
  ProductVariantSupport._();

  static final Random _random = Random();

  static String generateId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final suffix = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'v_${millis}_$suffix';
  }

  static List<ProductVariant> parseList(dynamic raw) {
    if (raw is! List) {
      return const <ProductVariant>[];
    }
    return raw
        .whereType<Map>()
        .map((entry) => ProductVariant.fromMap(Map<String, dynamic>.from(entry)))
        .where((variant) => variant.id.isNotEmpty)
        .toList(growable: false);
  }

  static bool productHasVariants(Map<String, dynamic> data) {
    if (data['hasVariants'] == true) {
      return true;
    }
    return parseList(data['variants']).isNotEmpty;
  }

  /// Variant shown by default in catalog cards — mirrors detail pager on open.
  static ProductVariant? catalogDefaultVariant(Map<String, dynamic> data) {
    if (!productHasVariants(data)) {
      return null;
    }
    final variants = activeVariants(parseList(data['variants']));
    if (variants.isEmpty) {
      return null;
    }
    if (variants.length == 1) {
      return variants.first;
    }

    final scoped = variantsForImageIndex(variants, data, 0);
    if (scoped.length == 1) {
      return scoped.first;
    }
    if (scoped.isNotEmpty) {
      return scoped.reduce(
        (a, b) => a.price <= b.price ? a : b,
      );
    }

    return matchVariant(variants);
  }

  static Map<String, dynamic> catalogListPricingData(Map<String, dynamic> data) {
    final variant = catalogDefaultVariant(data);
    if (variant == null) {
      return data;
    }
    return <String, dynamic>{
      ...data,
      'price': variant.price,
    };
  }

  /// Variants tied to one product image slot (original or thumbnail URL).
  static List<ProductVariant> variantsForImageIndex(
    List<ProductVariant> variants,
    Map<String, dynamic> productData,
    int imageIndex,
  ) {
    if (imageIndex < 0) {
      return const <ProductVariant>[];
    }

    final originals = readCatalogProductImageUrls(productData);
    if (imageIndex >= originals.length) {
      return const <ProductVariant>[];
    }
    return variantsForImageUrl(variants, originals[imageIndex]);
  }

  static List<ProductVariant> variantsForImageUrl(
    List<ProductVariant> variants,
    String imageUrl,
  ) {
    final normalized = imageUrl.trim();
    if (normalized.isEmpty) {
      return const <ProductVariant>[];
    }

    return activeVariants(variants)
        .where(
          (variant) =>
              variant.imageUrl.trim() == normalized ||
              variant.thumbnailUrl.trim() == normalized,
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> variantGalleryFields(
    List<ProductVariant> variants,
  ) {
    final active = activeVariants(variants);
    if (active.isEmpty) {
      return const <String, dynamic>{};
    }
    final derived = buildDerivedProductFields(active);
    return <String, dynamic>{
      'imageUrls': derived['imageUrls'],
      'thumbnailUrls': derived['thumbnailUrls'],
    };
  }

  static int galleryImageIndexForVariant(
    List<ProductVariant> variants,
    ProductVariant variant,
  ) {
    final gallery = variantGalleryFields(variants);
    final rawUrls = gallery['imageUrls'];
    if (rawUrls is! List || rawUrls.isEmpty) {
      return 0;
    }
    final urls = rawUrls.map((entry) => entry.toString().trim()).toList();
    for (final candidate in <String>[
      variant.imageUrl.trim(),
      variant.thumbnailUrl.trim(),
    ]) {
      if (candidate.isEmpty) {
        continue;
      }
      final index = urls.indexOf(candidate);
      if (index >= 0) {
        return index;
      }
    }

    final active = activeVariants(variants);
    for (var index = 0; index < urls.length; index++) {
      final scoped = variantsForImageUrl(active, urls[index]);
      if (scoped.any((entry) => entry.id == variant.id)) {
        return index;
      }
    }
    return 0;
  }

  static String optionKey({required String size, required String color}) {
    return '${size.trim().toLowerCase()}::${color.trim().toLowerCase()}';
  }

  static Map<String, dynamic> buildDerivedProductFields(
    List<ProductVariant> variants,
  ) {
    final active = variants.where((v) => v.isActive && v.price > 0).toList();
    if (active.isEmpty) {
      return <String, dynamic>{
        'hasVariants': false,
        'variants': <Map<String, dynamic>>[],
      };
    }

    final prices = active.map((v) => v.price).toList(growable: false);
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final totalStock = active.fold<int>(0, (sum, v) => sum + v.stock);

    final imageUrls = <String>[];
    final thumbnailUrls = <String>[];
    for (final variant in active) {
      final primary = variant.imageUrl.trim();
      final thumb = variant.thumbnailUrl.trim();
      final displayUrl = primary.isNotEmpty ? primary : thumb;
      if (displayUrl.isNotEmpty && !imageUrls.contains(displayUrl)) {
        imageUrls.add(displayUrl);
      }
      final thumbDisplay = thumb.isNotEmpty ? thumb : primary;
      if (thumbDisplay.isNotEmpty && !thumbnailUrls.contains(thumbDisplay)) {
        thumbnailUrls.add(thumbDisplay);
      }
    }

    final colors = <String>[];
    final sizes = <String>[];
    for (final variant in active) {
      if (variant.color.trim().isNotEmpty &&
          !colors.contains(variant.color.trim())) {
        colors.add(variant.color.trim());
      }
      if (variant.size.trim().isNotEmpty &&
          !sizes.contains(variant.size.trim())) {
        sizes.add(variant.size.trim());
      }
    }

    return <String, dynamic>{
      'hasVariants': true,
      'variants': active.map((v) => v.toMap()).toList(growable: false),
      'price': minPrice,
      'stock': totalStock,
      'imageUrls': imageUrls,
      'thumbnailUrls': thumbnailUrls.isNotEmpty ? thumbnailUrls : imageUrls,
      'colors': colors,
      'sizes': sizes,
    };
  }

  static List<ProductVariant> bindDraftsToUploadedImages({
    required List<ProductVariantDraft> drafts,
    required List<String> imageUrls,
    required List<String> thumbnailUrls,
  }) {
    final variants = <ProductVariant>[];
    for (final draft in drafts) {
      if (draft.imageIndex < 0 || draft.imageIndex >= imageUrls.length) {
        continue;
      }
      final price = double.tryParse(draft.priceText.trim()) ?? 0;
      final stock = int.tryParse(draft.stockText.trim()) ?? 0;
      if (price <= 0) {
        continue;
      }
      variants.add(
        ProductVariant(
          id: draft.id,
          imageUrl: imageUrls[draft.imageIndex],
          thumbnailUrl: draft.imageIndex < thumbnailUrls.length
              ? thumbnailUrls[draft.imageIndex]
              : imageUrls[draft.imageIndex],
          size: draft.size.trim(),
          color: draft.color.trim(),
          price: price,
          stock: stock,
        ),
      );
    }
    return variants;
  }

  static List<ProductVariantDraft> draftsFromVariants(
    List<ProductVariant> variants, {
    required List<String> imageUrls,
  }) {
    return variants.map((variant) {
      var index = imageUrls.indexOf(variant.imageUrl);
      if (index < 0) {
        index = 0;
      }
      return ProductVariantDraft(
        id: variant.id,
        imageIndex: index,
        size: variant.size,
        color: variant.color,
        priceText: variant.price > 0 ? variant.price.toString() : '',
        stockText: variant.stock.toString(),
      );
    }).toList(growable: false);
  }

  static List<ProductVariant> activeVariants(List<ProductVariant> variants) {
    return variants
        .where((variant) => variant.isActive && variant.price > 0)
        .toList(growable: false);
  }

  static ProductVariant? matchVariant(
    List<ProductVariant> variants, {
    String? variantId,
    String? color,
    String? size,
  }) {
    final active = activeVariants(variants);
    final normalizedId = variantId?.trim();
    if (normalizedId != null && normalizedId.isNotEmpty) {
      for (final variant in active) {
        if (variant.id == normalizedId) {
          return variant;
        }
      }
    }
    final normalizedColor = color?.trim() ?? '';
    final normalizedSize = size?.trim() ?? '';
    for (final variant in active) {
      final colorMatch =
          normalizedColor.isEmpty || variant.color.trim() == normalizedColor;
      final sizeMatch =
          normalizedSize.isEmpty || variant.size.trim() == normalizedSize;
      if (colorMatch && sizeMatch) {
        return variant;
      }
    }
    return active.length == 1 ? active.first : null;
  }

  static List<String> uniqueOptionValues(
    List<ProductVariant> variants, {
    required bool colors,
    String? selectedColor,
    String? selectedSize,
  }) {
    final active = activeVariants(variants);
    final values = <String>[];
    for (final variant in active) {
      if (colors) {
        if (selectedSize != null &&
            selectedSize.trim().isNotEmpty &&
            variant.size.trim() != selectedSize.trim()) {
          continue;
        }
        final value = variant.color.trim();
        if (value.isNotEmpty && !values.contains(value)) {
          values.add(value);
        }
      } else {
        if (selectedColor != null &&
            selectedColor.trim().isNotEmpty &&
            variant.color.trim() != selectedColor.trim()) {
          continue;
        }
        final value = variant.size.trim();
        if (value.isNotEmpty && !values.contains(value)) {
          values.add(value);
        }
      }
    }
    return values;
  }

  static String? validateDrafts(List<ProductVariantDraft> drafts) {
    if (drafts.isEmpty) {
      return 'กรุณาเพิ่มตัวเลือกอย่างน้อย 1 รายการ';
    }
    final seen = <String>{};
    for (final draft in drafts) {
      final price = double.tryParse(draft.priceText.trim());
      final stock = int.tryParse(draft.stockText.trim());
      if (price == null || price <= 0) {
        return 'กรุณาระบุราคาที่ถูกต้องทุกตัวเลือก';
      }
      if (stock == null || stock < 0) {
        return 'กรุณาระบุสต็อกที่ถูกต้องทุกตัวเลือก';
      }
      final key =
          '${draft.imageIndex}::${ProductVariantSupport.optionKey(size: draft.size, color: draft.color)}';
      if (!seen.add(key)) {
        return 'มีตัวเลือกซ้ำ (รูป/ขนาด/สี) — กรุณาแก้ไข';
      }
    }
    return null;
  }
}
