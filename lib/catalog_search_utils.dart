import 'package:flutter/material.dart';

import 'public_catalog_service.dart';

class CatalogSearchUtils {
  CatalogSearchUtils._();

  static bool productMatches(PublicCatalogProduct product, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final data = product.data;
    final tokens = <String>[
      (data['name'] ?? '').toString(),
      (data['description'] ?? '').toString(),
      (data['productType'] ?? data['type'] ?? '').toString(),
      (data['heading'] ?? '').toString(),
      product.shopName ?? '',
      product.shopId,
      product.id,
    ];

    return tokens.any(
      (token) => token.trim().toLowerCase().contains(normalizedQuery),
    );
  }

  static List<PublicCatalogSection> filterSections(
    List<PublicCatalogSection> sections,
    String query,
  ) {
    if (query.trim().isEmpty) {
      return sections;
    }

    final filtered = <PublicCatalogSection>[];
    for (final section in sections) {
      final products = section.products
          .where((product) => productMatches(product, query))
          .toList(growable: false);
      if (products.isEmpty) {
        continue;
      }
      filtered.add(
        PublicCatalogSection(
          shopId: section.shopId,
          shopName: section.shopName,
          shopImageUrl: section.shopImageUrl,
          shopLatitude: section.shopLatitude,
          shopLongitude: section.shopLongitude,
          products: products,
          shopUpdatedAt: section.shopUpdatedAt,
          shopDescription: section.shopDescription,
        ),
      );
    }
    return filtered;
  }

  static List<PublicCatalogProduct> collectMatchingProducts(
    List<PublicCatalogSection> sections,
    String query,
  ) {
    if (query.trim().isEmpty) {
      return sections
          .expand((section) => section.products)
          .toList(growable: false);
    }

    return sections
        .expand((section) => section.products)
        .where((product) => productMatches(product, query))
        .toList(growable: false);
  }
}

class CatalogSearchBar extends StatefulWidget {
  const CatalogSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 8),
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final EdgeInsetsGeometry margin;

  @override
  State<CatalogSearchBar> createState() => _CatalogSearchBarState();
}

class _CatalogSearchBarState extends State<CatalogSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant CatalogSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.margin,
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6B7280)),
          suffixIcon: widget.controller.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'ล้างคำค้นหา',
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged?.call('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFF57C00), width: 1.5),
          ),
        ),
      ),
    );
  }
}
