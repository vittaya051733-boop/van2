import 'package:flutter/material.dart';

import '../category_catalog_screen.dart';
import '../public_catalog_service.dart';
import 'catalog_product_link.dart';

Future<bool> openCatalogProductFromShareLink({
  required BuildContext context,
  required CatalogProductLinkTarget target,
  double? customerLatitude,
  double? customerLongitude,
  ValueChanged<CartProductSelection>? onConfirmOrder,
  VoidCallback? onNavigateToCart,
}) async {
  final products = await PublicCatalogService.resolveProductsByIds(
    <String>[target.productId],
    requireDisplayImage: false,
  );
  if (products.isEmpty || !context.mounted) {
    return false;
  }

  final product = products.first;
  var shopProducts = await PublicCatalogService.listActiveProductsForShop(
    target.shopId ?? product.shopId,
  );
  if (shopProducts.isEmpty) {
    shopProducts = <PublicCatalogProduct>[product];
  }

  var initialIndex = shopProducts.indexWhere((entry) => entry.id == product.id);
  if (initialIndex < 0) {
    shopProducts = <PublicCatalogProduct>[product, ...shopProducts];
    initialIndex = 0;
  }

  if (!context.mounted) {
    return false;
  }

  showCatalogProductDetailPager(
    context: context,
    products: shopProducts,
    initialIndex: initialIndex,
    customerLatitude: customerLatitude,
    customerLongitude: customerLongitude,
    onConfirmOrder: onConfirmOrder,
    onNavigateToCart: onNavigateToCart,
  );
  CatalogProductLink.normalizeWebHomeUrl();
  return true;
}
