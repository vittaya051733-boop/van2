import 'package:flutter/material.dart';

import 'catalog_search_utils.dart';
import 'category_catalog_screen.dart';
import 'public_catalog_service.dart';
import 'services/nationwide_catalog_service.dart';

class NationwideCategoryProductsScreen extends StatefulWidget {
  const NationwideCategoryProductsScreen({
    super.key,
    required this.categoryKey,
    required this.categoryLabel,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final String categoryKey;
  final String categoryLabel;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<NationwideCategoryProductsScreen> createState() =>
      _NationwideCategoryProductsScreenState();
}

class _NationwideCategoryProductsScreenState
    extends State<NationwideCategoryProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PublicCatalogProduct> _filterProducts(List<PublicCatalogProduct> products) {
    if (_searchQuery.trim().isEmpty) {
      return products;
    }
    return products
        .where((product) => CatalogSearchUtils.productMatches(product, _searchQuery))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: Text(widget.categoryLabel),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CatalogSearchBar(
              controller: _searchController,
              hintText: 'ค้นหาใน${widget.categoryLabel}',
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<PublicCatalogProduct>>(
              stream: NationwideCatalogService.instance
                  .streamNationwideProductsByCategory(widget.categoryKey),
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

                final products = _filterProducts(
                  snapshot.data ?? const <PublicCatalogProduct>[],
                );

                if (products.isEmpty &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (products.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searchQuery.trim().isNotEmpty
                            ? 'ไม่พบสินค้าที่ตรงกับ "${_searchQuery.trim()}"'
                            : 'ยังไม่มีสินค้าส่งทั่วประเทศในหมวดนี้',
                        textAlign: TextAlign.center,
                      ),
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
              },
            ),
          ),
        ],
      ),
    );
  }
}
