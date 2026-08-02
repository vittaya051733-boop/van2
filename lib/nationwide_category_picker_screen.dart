import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_search_utils.dart';
import 'category_catalog_screen.dart';
import 'public_catalog_service.dart';
import 'services/app_image_prefetch.dart';
import 'services/nationwide_catalog_service.dart';

/// หน้ารวมสินค้าส่งทั่วประเทศ — ค้นหา + เลือกประเภท + รายการสินค้าข้ามร้าน
class NationwideCategoryPickerScreen extends StatefulWidget {
  const NationwideCategoryPickerScreen({
    super.key,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<NationwideCategoryPickerScreen> createState() =>
      _NationwideCategoryPickerScreenState();
}

class _NationwideCategoryPickerScreenState
    extends State<NationwideCategoryPickerScreen> {
  static const String _allCategoriesKey = '';

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryKey = _allCategoriesKey;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PublicCatalogProduct> _filterProducts(
    List<PublicCatalogProduct> products,
  ) {
    var filtered = products;

    final categoryKey = _selectedCategoryKey?.trim() ?? '';
    if (categoryKey.isNotEmpty) {
      filtered = filtered
          .where(
            (product) =>
                NationwideCatalogService.categoryKeyForProduct(product) ==
                categoryKey,
          )
          .toList(growable: false);
    }

    if (_searchQuery.trim().isNotEmpty) {
      filtered = filtered
          .where(
            (product) =>
                CatalogSearchUtils.productMatches(product, _searchQuery),
          )
          .toList(growable: false);
    }

    return filtered;
  }

  void _onCategoryChanged(String? categoryKey) {
    final normalizedKey = categoryKey ?? _allCategoriesKey;
    setState(() => _selectedCategoryKey = normalizedKey);

    if (normalizedKey.isNotEmpty) {
      unawaited(
        AppImagePrefetch.continueWarmNationwide(categoryKey: normalizedKey),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: const Text('สินค้าส่งทั่วประเทศ'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: StreamBuilder<List<PublicCatalogSection>>(
        stream: PublicCatalogService.streamNationwideShippingSections(),
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'โหลดสินค้าไม่สำเร็จ: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final sections = snapshot.data ?? const <PublicCatalogSection>[];
          final categories =
              NationwideCatalogService.buildCategoriesFromSections(sections);
          final allProducts =
              NationwideCatalogService.flattenNationwideProducts(sections);
          final products = _filterProducts(allProducts);

          if (sections.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CatalogSearchBar(
                controller: _searchController,
                hintText: 'ค้นหาสินค้าส่งทั่วประเทศ',
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _NationwideCategoryDropdown(
                  categories: categories,
                  selectedCategoryKey: _selectedCategoryKey,
                  totalProductCount: allProducts.length,
                  onChanged: _onCategoryChanged,
                ),
              ),
              Expanded(
                child: _buildProductList(
                  snapshot: snapshot,
                  sectionsEmpty: sections.isEmpty,
                  products: products,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProductList({
    required AsyncSnapshot<List<PublicCatalogSection>> snapshot,
    required bool sectionsEmpty,
    required List<PublicCatalogProduct> products,
  }) {
    if (sectionsEmpty && snapshot.connectionState != ConnectionState.waiting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'ยังไม่มีสินค้าส่งทั่วประเทศในตอนนี้',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (products.isEmpty &&
        snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (products.isEmpty) {
      final hasSearch = _searchQuery.trim().isNotEmpty;
      final hasCategory =
          (_selectedCategoryKey?.trim().isNotEmpty ?? false);
      final emptyMessage = hasSearch
          ? 'ไม่พบสินค้าที่ตรงกับ "${_searchQuery.trim()}"'
          : hasCategory
          ? 'ยังไม่มีสินค้าส่งทั่วประเทศในประเภทนี้'
          : 'ยังไม่มีสินค้าส่งทั่วประเทศในตอนนี้';

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        NationwideMixedProductsFeed(
          products: products,
          customerLatitude: widget.customerLatitude,
          customerLongitude: widget.customerLongitude,
          onConfirmOrder: widget.onConfirmOrder,
          onNavigateToCart: widget.onNavigateToCart,
        ),
      ],
    );
  }
}

class _NationwideCategoryDropdown extends StatelessWidget {
  const _NationwideCategoryDropdown({
    required this.categories,
    required this.selectedCategoryKey,
    required this.totalProductCount,
    required this.onChanged,
  });

  final List<NationwideProductCategory> categories;
  final String? selectedCategoryKey;
  final int totalProductCount;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final normalizedSelection = selectedCategoryKey?.trim() ?? '';
    final selectedExists = normalizedSelection.isEmpty ||
        categories.any((category) => category.key == normalizedSelection);
    final effectiveValue = selectedExists ? normalizedSelection : '';

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'ประเภทสินค้า',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE55A00), width: 1.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: effectiveValue,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: '',
              child: Text('ทั้งหมด ($totalProductCount รายการ)'),
            ),
            for (final category in categories)
              DropdownMenuItem<String>(
                value: category.key,
                child: Text('${category.label} (${category.productCount} รายการ)'),
              ),
          ],
          onChanged: categories.isEmpty && totalProductCount == 0
              ? null
              : onChanged,
        ),
      ),
    );
  }
}
