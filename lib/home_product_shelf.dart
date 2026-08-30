import 'package:flutter/material.dart';

import 'category_catalog_screen.dart';
import 'l10n/l10n.dart';
import 'services/locale_service.dart';
import 'services/product_translation_service.dart';
import 'home_product_discovery_service.dart';
import 'public_catalog_service.dart';
import 'services/home_product_image_prefetch.dart';

import 'widgets/home_shelf_infinite_carousel.dart';
import 'widgets/product_discount_badge.dart';
import 'widgets/product_discount_price.dart';
import 'utils/catalog_product_image_url.dart';
import 'utils/localized_product_text.dart';
import 'widgets/cached_app_image.dart';

typedef HomeShelfProductTap = void Function(PublicCatalogProduct product);

Widget buildHomeShelfCatalogCard({
  required BuildContext context,
  required PublicCatalogProduct product,
  double? customerLatitude,
  double? customerLongitude,
  ValueChanged<CartProductSelection>? onConfirmOrder,
  VoidCallback? onNavigateToCart,
  List<PublicCatalogProduct>? shopProducts,
}) {
  final cardSize = catalogHomeShelfCardSize(context);
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
      shopProducts: shopProducts,
      shopLatitude: product.shopLatitude,
      shopLongitude: product.shopLongitude,
      shopDistanceKm: shopDistanceKm,
      customerLatitude: customerLatitude,
      customerLongitude: customerLongitude,
      onConfirmOrder: onConfirmOrder,
      onNavigateToCart: onNavigateToCart,
      pinPriceToBottom: true,
    ),
  );
}

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
    this.showWhenEmpty = false,
    this.emptyMessage,
    this.enableInfiniteCarousel = false,
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
  final bool showWhenEmpty;
  final String? emptyMessage;
  final bool enableInfiniteCarousel;

  static const double _catalogSpacing = 12;

  static const double _compactRowHeight = 180;

  @override
  Widget build(BuildContext context) {
    if (!isLoading && products.isEmpty && !showWhenEmpty) {
      return const SizedBox.shrink();
    }

    if (useCatalogCardStyle) {
      final cardSize = catalogHomeShelfCardSize(context);

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

          const SizedBox(height: 4),

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
                : products.isEmpty
                ? _HomeShelfEmptyMessage(message: emptyMessage)
                : enableInfiniteCarousel
                ? HomeShelfInfiniteCarousel(
                    itemCount: products.length,
                    itemWidth: cardSize.width,
                    spacing: _catalogSpacing,
                    height: cardSize.height,
                    itemBuilder: (context, index) {
                      final product = products[index];

                      return buildHomeShelfCatalogCard(
                        context: context,
                        product: product,
                        customerLatitude: customerLatitude,
                        customerLongitude: customerLongitude,
                        onConfirmOrder: onConfirmOrder,
                        onNavigateToCart: onNavigateToCart,
                      );
                    },
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

                      return buildHomeShelfCatalogCard(
                        context: context,
                        product: product,
                        customerLatitude: customerLatitude,
                        customerLongitude: customerLongitude,
                        onConfirmOrder: onConfirmOrder,
                        onNavigateToCart: onNavigateToCart,
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

        const SizedBox(height: 4),

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
              : products.isEmpty
              ? _HomeShelfEmptyMessage(message: emptyMessage)
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

class _HomeShelfEmptyMessage extends StatelessWidget {
  const _HomeShelfEmptyMessage({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        message?.trim().isNotEmpty == true
            ? message!.trim()
            : L10n.catalogNoProductsYet,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF92400E),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class HomeDiscountProductFeedSection extends StatefulWidget {
  const HomeDiscountProductFeedSection({
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
  State<HomeDiscountProductFeedSection> createState() =>
      _HomeDiscountProductFeedSectionState();
}

class _HomeDiscountProductFeedSectionState
    extends State<HomeDiscountProductFeedSection> {
  late Future<List<PublicCatalogProduct>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _productsFuture = HomeProductDiscoveryService.loadDiscountFeed();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PublicCatalogProduct>>(
      future: _productsFuture,
      builder: (context, snapshot) {
        final loading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final products = snapshot.data ?? const <PublicCatalogProduct>[];

        if (!loading && products.isEmpty) {
          return const SizedBox.shrink();
        }

        if (!loading && products.isNotEmpty) {
          HomeProductImagePrefetch.scheduleShelfPrefetch(
            products,
            limit: products.length,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                L10n.catalogDiscountProducts,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (var index = 0; index < products.length; index++) ...<Widget>[
                if (index > 0) const SizedBox(height: 4),
                _HomeDiscountFeedCard(
                  product: products[index],
                  shopProducts: products,
                  customerLatitude: widget.customerLatitude,
                  customerLongitude: widget.customerLongitude,
                  onConfirmOrder: widget.onConfirmOrder,
                  onNavigateToCart: widget.onNavigateToCart,
                ),
              ],
          ],
        );
      },
    );
  }
}

class _HomeDiscountFeedCard extends StatelessWidget {
  const _HomeDiscountFeedCard({
    required this.product,
    required this.shopProducts,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final PublicCatalogProduct product;
  final List<PublicCatalogProduct> shopProducts;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: buildHomeShelfCatalogCard(
        context: context,
        product: product,
        shopProducts: shopProducts,
        customerLatitude: customerLatitude,
        customerLongitude: customerLongitude,
        onConfirmOrder: onConfirmOrder,
        onNavigateToCart: onNavigateToCart,
      ),
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
    Widget tile = _buildTile(context);
    if (LocaleService.instance.isEnglish) {
      tile = ListenableBuilder(
        listenable: ProductTranslationService.instance,
        builder: (context, _) => _buildTile(context),
      );
    }
    return tile;
  }

  Widget _buildTile(BuildContext context) {
    final data = product.data;

    final imageUrl = readCatalogProductImageUrl(data);

    final name = LocalizedProductText.nameForProduct(product);

    final shopName = LocalizedProductText.shopNameForProduct(product);

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
                  child: wrapCatalogImageWithDiscountBadge(
                    productData: data,
                    productId: product.id,
                    shopId: product.shopId,
                    compact: true,
                    child: imageUrl == null
                        ? Container(
                            color: const Color(0xFFF3F4F6),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.image_outlined,
                              color: Color(0xFF9CA3AF),
                            ),
                          )
                        : CachedAppImage(
                            imageUrl: imageUrl,
                            width: 124,
                            height: 92,
                            fit: BoxFit.cover,
                            lightweight: true,
                            errorWidget: Container(
                              color: const Color(0xFFF3F4F6),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: Color(0xFF9CA3AF),
                              ),
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
                            name.isEmpty ? L10n.productFallback : name,

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

                        ProductDiscountPrice(
                          productData: data,
                          productId: product.id,
                          shopId: product.shopId,
                          compact: true,
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
