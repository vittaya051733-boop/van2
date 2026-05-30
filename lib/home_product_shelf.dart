import 'package:flutter/material.dart';



import 'category_catalog_screen.dart';

import 'public_catalog_service.dart';

import 'tax_pricing_policy.dart';



typedef HomeShelfProductTap = void Function(PublicCatalogProduct product);



class HomeProductShelfSection extends StatelessWidget {

  const HomeProductShelfSection({

    super.key,

    required this.title,

    required this.products,

    required this.onProductTap,

    this.isLoading = false,

    this.useCatalogCardStyle = false,

    this.customerLatitude,

    this.customerLongitude,

    this.onConfirmOrder,

    this.onNavigateToCart,

  });



  final String title;

  final List<PublicCatalogProduct> products;

  final HomeShelfProductTap onProductTap;

  final bool isLoading;

  final bool useCatalogCardStyle;

  final double? customerLatitude;

  final double? customerLongitude;

  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;



  static const double _catalogSpacing = 12;

  static const double _compactRowHeight = 172;



  @override

  Widget build(BuildContext context) {

    if (!isLoading && products.isEmpty) {

      return const SizedBox.shrink();

    }



    if (useCatalogCardStyle) {

      final cardSize = catalogGridProductCardSize(context);

      return Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: <Widget>[

          Padding(

            padding: const EdgeInsets.symmetric(horizontal: 2),

            child: Text(

              title,

              style: Theme.of(context).textTheme.titleMedium?.copyWith(

                    color: const Color(0xFF111827),

                    fontWeight: FontWeight.w800,

                  ),

            ),

          ),

          const SizedBox(height: 10),

          SizedBox(

            height: cardSize.height,

            child: isLoading

                ? ListView.separated(

                    scrollDirection: Axis.horizontal,

                    physics: const NeverScrollableScrollPhysics(),

                    itemCount: 4,

                    separatorBuilder: (_, __) =>

                        const SizedBox(width: _catalogSpacing),

                    itemBuilder: (_, __) => _HomeShelfSkeletonTile(

                      width: cardSize.width,

                      height: cardSize.height,

                      borderRadius: 18,

                    ),

                  )

                : ListView.separated(

                    scrollDirection: Axis.horizontal,

                    physics: const BouncingScrollPhysics(),

                    padding: const EdgeInsets.symmetric(horizontal: 2),

                    itemCount: products.length,

                    separatorBuilder: (_, __) =>

                        const SizedBox(width: _catalogSpacing),

                    itemBuilder: (context, index) {

                      final product = products[index];

                      final shopDistanceKm = computeCatalogShopDistanceKm(

                        customerLatitude: customerLatitude,

                        customerLongitude: customerLongitude,

                        shopLatitude: product.shopLatitude,

                        shopLongitude: product.shopLongitude,

                      );

                      return SizedBox(

                        width: cardSize.width,

                        height: cardSize.height,

                        child: CatalogProductCard(

                          product: product,

                          shopLatitude: product.shopLatitude,

                          shopLongitude: product.shopLongitude,

                          shopDistanceKm: shopDistanceKm,

                          onConfirmOrder: onConfirmOrder,

                          onNavigateToCart: onNavigateToCart,

                        ),

                      );

                    },

                  ),

          ),

        ],

      );

    }



    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: <Widget>[

        Padding(

          padding: const EdgeInsets.symmetric(horizontal: 2),

          child: Text(

            title,

            style: Theme.of(context).textTheme.titleMedium?.copyWith(

                  color: const Color(0xFF111827),

                  fontWeight: FontWeight.w800,

                ),

          ),

        ),

        const SizedBox(height: 10),

        SizedBox(

          height: _compactRowHeight,

          child: isLoading

              ? ListView.separated(

                  scrollDirection: Axis.horizontal,

                  physics: const NeverScrollableScrollPhysics(),

                  itemCount: 4,

                  separatorBuilder: (_, __) => const SizedBox(width: 12),

                  itemBuilder: (_, __) => const _HomeShelfSkeletonTile(

                    width: 124,

                    height: _compactRowHeight,

                    borderRadius: 18,

                  ),

                )

              : ListView.separated(

                  scrollDirection: Axis.horizontal,

                  physics: const BouncingScrollPhysics(),

                  padding: const EdgeInsets.symmetric(horizontal: 2),

                  itemCount: products.length,

                  separatorBuilder: (_, __) => const SizedBox(width: 12),

                  itemBuilder: (context, index) {

                    final product = products[index];

                    return HomeShelfProductTile(

                      product: product,

                      onTap: () => onProductTap(product),

                    );

                  },

                ),

        ),

      ],

    );

  }

}



class HomeShelfProductTile extends StatelessWidget {

  const HomeShelfProductTile({

    super.key,

    required this.product,

    required this.onTap,

  });



  final PublicCatalogProduct product;

  final VoidCallback onTap;



  @override

  Widget build(BuildContext context) {

    final data = product.data;

    final imageUrl = _readProductImageUrl(data);

    final name = (data['name'] ?? '').toString().trim();

    final shopName =

        product.shopName?.trim().isNotEmpty == true ? product.shopName!.trim() : 'ร้านค้า';

    final taxable = TaxPricingPolicy.isTaxableProduct(data);

    final basePrice = TaxPricingPolicy.parseNumber(data['price']);

    final adjustedPrice = TaxPricingPolicy.applyProductMarkup(basePrice, taxable);

    final priceText = TaxPricingPolicy.formatPrice(adjustedPrice);



    return SizedBox(

      width: 124,

      height: 172,

      child: Material(

        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        clipBehavior: Clip.antiAlias,

        child: InkWell(

          onTap: onTap,

          child: DecoratedBox(

            decoration: BoxDecoration(

              border: Border.all(color: const Color(0xFFE5E7EB)),

              borderRadius: BorderRadius.circular(18),

              boxShadow: const <BoxShadow>[

                BoxShadow(

                  color: Color(0x10000000),

                  blurRadius: 16,

                  offset: Offset(0, 8),

                ),

              ],

            ),

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: <Widget>[

                SizedBox(

                  height: 92,

                  child: imageUrl == null

                      ? Container(

                          color: const Color(0xFFF3F4F6),

                          alignment: Alignment.center,

                          child: const Icon(

                            Icons.image_outlined,

                            color: Color(0xFF9CA3AF),

                          ),

                        )

                      : Image.network(

                          imageUrl,

                          fit: BoxFit.cover,

                          width: double.infinity,

                          height: 92,

                          errorBuilder: (_, __, ___) => Container(

                            color: const Color(0xFFF3F4F6),

                            alignment: Alignment.center,

                            child: const Icon(

                              Icons.broken_image_outlined,

                              color: Color(0xFF9CA3AF),

                            ),

                          ),

                        ),

                ),

                Expanded(

                  child: Padding(

                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: <Widget>[

                        Expanded(

                          child: Text(

                            name.isEmpty ? 'สินค้า' : name,

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

                        Text(

                          shopName,

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                          style: const TextStyle(

                            fontSize: 9.5,

                            color: Color(0xFF6B7280),

                            height: 1.1,

                          ),

                        ),

                        const SizedBox(height: 1),

                        Text(

                          '฿$priceText',

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                          style: const TextStyle(

                            fontSize: 11.5,

                            fontWeight: FontWeight.w800,

                            color: Color(0xFFEF8A17),

                            height: 1.1,

                          ),

                        ),

                      ],

                    ),

                  ),

                ),

              ],

            ),

          ),

        ),

      ),

    );

  }



  static String? _readProductImageUrl(Map<String, dynamic> data) {

    final thumbnails = data['thumbnailUrls'];

    if (thumbnails is List) {

      for (final entry in thumbnails) {

        final url = entry.toString().trim();

        if (url.isNotEmpty) {

          return url;

        }

      }

    }



    final images = data['imageUrls'];

    if (images is List) {

      for (final entry in images) {

        final url = entry.toString().trim();

        if (url.isNotEmpty) {

          return url;

        }

      }

    }



    for (final key in <String>['imageUrl', 'photoUrl', 'productImage']) {

      final url = data[key]?.toString().trim();

      if (url != null && url.isNotEmpty) {

        return url;

      }

    }



    return null;

  }

}



class _HomeShelfSkeletonTile extends StatelessWidget {

  const _HomeShelfSkeletonTile({

    required this.width,

    required this.height,

    required this.borderRadius,

  });



  final double width;

  final double height;

  final double borderRadius;



  @override

  Widget build(BuildContext context) {

    return SizedBox(

      width: width,

      height: height,

      child: Container(

        decoration: BoxDecoration(

          color: const Color(0xFFF3F4F6),

          borderRadius: BorderRadius.circular(borderRadius),

          border: Border.all(color: const Color(0xFFE5E7EB)),

        ),

      ),

    );

  }

}

