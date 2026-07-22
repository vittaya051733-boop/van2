import 'package:flutter/material.dart';

import 'category_catalog_screen.dart';
import 'public_catalog_service.dart';
import 'services/app_image_prefetch.dart';
import 'services/favorites_service.dart';
import 'widgets/cached_app_image.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
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
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    FavoritesService.instance.ensureLoaded();
    FavoritesService.instance.favorites.addListener(_prefetchFavoriteImages);
    _prefetchFavoriteImages();
  }

  @override
  void dispose() {
    FavoritesService.instance.favorites.removeListener(_prefetchFavoriteImages);
    super.dispose();
  }

  void _prefetchFavoriteImages() {
    final items = FavoritesService.instance.favorites.value;
    AppImagePrefetch.scheduleImageUrlsPrefetch(
      items.map((item) => item.imageUrl),
      dedupeKey: 'favorites:${items.map((item) => item.id).join(',')}',
    );
  }

  Future<void> _openFavorite(CatalogFavorite favorite) async {
    if (favorite.kind == CatalogFavorite.kindProduct) {
      final product = favorite.toProduct();
      if (product == null || !mounted) {
        return;
      }
      showCatalogProductDetailPager(
        context: context,
        products: <PublicCatalogProduct>[product],
        initialIndex: 0,
        customerLatitude: widget.customerLatitude,
        customerLongitude: widget.customerLongitude,
        onConfirmOrder: widget.onConfirmOrder,
        onNavigateToCart: widget.onNavigateToCart,
      );
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CategoryCatalogScreen(
          title: favorite.title,
          serviceType: favorite.serviceType ?? '',
          shopIdFilter: favorite.shopId,
          customerLatitude: widget.customerLatitude,
          customerLongitude: widget.customerLongitude,
          onConfirmOrder: widget.onConfirmOrder,
          onNavigateToCart: widget.onNavigateToCart,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: const Text(
          'รายการโปรด',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
      ),
      body: ValueListenableBuilder<List<CatalogFavorite>>(
        valueListenable: FavoritesService.instance.favorites,
        builder: (context, items, _) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ยังไม่มีรายการโปรด\nกดไอคอนหัวใจที่สินค้าหรือร้านค้าเพื่อบันทึก',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final isProduct = item.kind == CatalogFavorite.kindProduct;
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openFavorite(item),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: item.imageUrl != null &&
                                    item.imageUrl!.trim().isNotEmpty
                                ? CachedAppImage(
                                    imageUrl: item.imageUrl!,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    lightweight: true,
                                    errorWidget: _FavoritePlaceholder(
                                      isProduct: isProduct,
                                    ),
                                  )
                                : _FavoritePlaceholder(isProduct: isProduct),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              if (item.subtitle != null &&
                                  item.subtitle!.trim().isNotEmpty) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                isProduct ? 'สินค้า' : 'ร้านค้า',
                                style: const TextStyle(
                                  color: Color(0xFFF57C00),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'ลบออกจากรายการโปรด',
                          onPressed: () =>
                              FavoritesService.instance.remove(item),
                          icon: const Icon(
                            Icons.favorite,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FavoritePlaceholder extends StatelessWidget {
  const _FavoritePlaceholder({required this.isProduct});

  final bool isProduct;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFEDD5),
      child: Icon(
        isProduct ? Icons.shopping_bag_outlined : Icons.storefront_outlined,
        color: const Color(0xFF9A3412),
      ),
    );
  }
}
