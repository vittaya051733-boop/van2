import 'package:flutter/material.dart';

import 'catalog_search_utils.dart';
import 'category_catalog_screen.dart';
import 'public_catalog_service.dart';

class CatalogProductSearchScreen extends StatefulWidget {
  const CatalogProductSearchScreen({
    super.key,
    required this.title,
    required this.sectionsStream,
    required this.searchHint,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final String title;
  final Stream<List<PublicCatalogSection>> sectionsStream;
  final String searchHint;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<CatalogProductSearchScreen> createState() =>
      _CatalogProductSearchScreenState();
}

class _CatalogProductSearchScreenState
    extends State<CatalogProductSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final nextQuery = _searchController.text;
      if (nextQuery == _searchQuery) {
        return;
      }
      setState(() => _searchQuery = nextQuery);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CatalogSearchBar(
            controller: _searchController,
            hintText: widget.searchHint,
            autofocus: true,
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          Expanded(
            child: StreamBuilder<List<PublicCatalogSection>>(
              stream: widget.sectionsStream,
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

                final products = CatalogSearchUtils.collectMatchingProducts(
                  snapshot.data ?? const <PublicCatalogSection>[],
                  _searchQuery,
                );

                if (_searchQuery.trim().isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'พิมพ์ชื่อสินค้า ร้าน หรือประเภทสินค้าเพื่อค้นหา',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }

                if (products.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'ไม่พบสินค้าที่ตรงกับ "${_searchQuery.trim()}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }

                final cardSize = catalogGridProductCardSize(context);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: cardSize.height,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final shopDistanceKm = computeCatalogShopDistanceKm(
                      customerLatitude: widget.customerLatitude,
                      customerLongitude: widget.customerLongitude,
                      shopLatitude: product.shopLatitude,
                      shopLongitude: product.shopLongitude,
                    );
                    return CatalogProductCard(
                      product: product,
                      shopProducts: products,
                      shopLatitude: product.shopLatitude,
                      shopLongitude: product.shopLongitude,
                      shopDistanceKm: shopDistanceKm,
                      customerLatitude: widget.customerLatitude,
                      customerLongitude: widget.customerLongitude,
                      onConfirmOrder: widget.onConfirmOrder,
                      onNavigateToCart: widget.onNavigateToCart,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
