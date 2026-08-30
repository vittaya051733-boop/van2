part of 'category_catalog_screen.dart';

void showCatalogProductDetailPager({
  required BuildContext context,
  required List<PublicCatalogProduct> products,
  required int initialIndex,
  double? customerLatitude,
  double? customerLongitude,
  ValueChanged<CartProductSelection>? onConfirmOrder,
  VoidCallback? onNavigateToCart,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _CatalogProductDetailPager(
        products: products,
        initialIndex: initialIndex,
        customerLatitude: customerLatitude,
        customerLongitude: customerLongitude,
        onConfirmOrder: onConfirmOrder,
        onNavigateToCart: onNavigateToCart,
      ),
    ),
  );
}

class _CatalogProductDetailPager extends StatefulWidget {
  const _CatalogProductDetailPager({
    required this.products,
    required this.initialIndex,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final List<PublicCatalogProduct> products;
  final int initialIndex;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<_CatalogProductDetailPager> createState() =>
      _CatalogProductDetailPagerState();
}

class _CatalogProductDetailPagerState
    extends State<_CatalogProductDetailPager> {
  late final PageController _pageController;
  late int _currentIndex;
  int? _lastAddedQuantity;
  String? _lastAddedProductName;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.products.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    AppImagePrefetch.scheduleProductsPrefetch(
      widget.products,
      dedupeKey: 'pager:${widget.products.map((p) => p.id).join(',')}',
    );
    prefetchCatalogProductMedia(
      products: widget.products,
      selectedIndex: _currentIndex,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _shopName =>
      LocalizedProductText.shopNameForProduct(widget.products[_currentIndex]);

  void _handleAddToCart(CartProductSelection selection) {
    widget.onConfirmOrder?.call(selection);
    setState(() {
      _lastAddedQuantity = selection.quantity;
      _lastAddedProductName = selection.productName;
    });
  }

  void _openCart() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onNavigateToCart?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        LocaleService.instance,
        ProductTranslationService.instance,
      ]),
      builder: (context, _) {
    final total = widget.products.length;
    final showPagerHint = total > 1;
    final showCartBar = _lastAddedQuantity != null && _lastAddedQuantity! > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _shopName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (showPagerHint)
              Text(
                L10n.catalogSwipeProductHint(_currentIndex + 1, total),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
        actions: <Widget>[
          CatalogFavoriteToggleButton(
            favorite: CatalogFavorite.fromProduct(
              widget.products[_currentIndex],
            ),
            iconColor: Colors.white,
            inactiveColor: Colors.white,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: total,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          prefetchCatalogProductMedia(
            products: widget.products,
            selectedIndex: index,
          );
        },
        itemBuilder: (context, index) {
          final isNeighbor = (index - _currentIndex).abs() <= 1;
          return _CatalogProductDetailPage(
            product: widget.products[index],
            isCurrentProduct: index == _currentIndex,
            warmVideoPlayback: isNeighbor,
            customerLatitude: widget.customerLatitude,
            customerLongitude: widget.customerLongitude,
            onAddToCart: _handleAddToCart,
            bottomInset: showCartBar ? 112 : 0,
          );
        },
      ),
      bottomNavigationBar: showCartBar
          ? _CatalogAddedToCartBar(
              quantity: _lastAddedQuantity!,
              productName: _lastAddedProductName,
              onOpenCart: widget.onNavigateToCart != null ? _openCart : null,
            )
          : null,
    );
      },
    );
  }
}

class _CatalogAddedToCartBar extends StatelessWidget {
  const _CatalogAddedToCartBar({
    required this.quantity,
    required this.productName,
    this.onOpenCart,
  });

  final int quantity;
  final String? productName;
  final VoidCallback? onOpenCart;

  @override
  Widget build(BuildContext context) {
    final label = productName?.trim().isNotEmpty == true
        ? productName!.trim()
        : L10n.productFallback;

    return Material(
      elevation: 12,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$quantity',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      L10n.catalogAddedToCart(quantity),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onOpenCart != null) ...<Widget>[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onOpenCart,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text(
                    L10n.catalogGoToCart,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogProductDetailPage extends StatefulWidget {
  const _CatalogProductDetailPage({
    required this.product,
    required this.isCurrentProduct,
    this.warmVideoPlayback = false,
    this.customerLatitude,
    this.customerLongitude,
    required this.onAddToCart,
    this.bottomInset = 24,
  });

  final PublicCatalogProduct product;
  final bool isCurrentProduct;
  final bool warmVideoPlayback;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection> onAddToCart;
  final double bottomInset;

  @override
  State<_CatalogProductDetailPage> createState() =>
      _CatalogProductDetailPageState();
}

class _CatalogProductDetailPageState extends State<_CatalogProductDetailPage> {
  final Set<String> _selectedToppings = <String>{};
  int _quantity = 1;
  String? _selectedColor;
  String? _selectedSize;
  String? _selectedVariantId;
  int _mediaPageIndex = 0;

  List<ProductVariant> get _variants =>
      ProductVariantSupport.parseList(widget.product.data['variants']);

  bool get _hasVariants =>
      ProductVariantSupport.productHasVariants(widget.product.data);

  ProductVariant? get _resolvedVariant => _hasVariants
      ? ProductVariantSupport.matchVariant(
          _variants,
          variantId: _selectedVariantId,
          color: _selectedColor,
          size: _selectedSize,
        )
      : null;

  @override
  void initState() {
    super.initState();
    _applyDefaultVariantSelection();
    _warmShareImage(widget.product.data);
  }

  @override
  void didUpdateWidget(covariant _CatalogProductDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _selectedToppings.clear();
      _quantity = 1;
      _selectedColor = null;
      _selectedSize = null;
      _selectedVariantId = null;
      _mediaPageIndex = 0;
      _applyDefaultVariantSelection();
      _warmShareImage(widget.product.data);
    }
  }

  void _applyDefaultVariantSelection() {
    if (!_hasVariants) {
      return;
    }
    final defaultVariant =
        ProductVariantSupport.catalogDefaultVariant(widget.product.data);
    if (defaultVariant == null) {
      return;
    }
    _selectedVariantId = defaultVariant.id;
    _selectedColor = defaultVariant.color.trim().isEmpty
        ? null
        : defaultVariant.color.trim();
    _selectedSize =
        defaultVariant.size.trim().isEmpty ? null : defaultVariant.size.trim();
    _mediaPageIndex = _imageIndexForVariant(defaultVariant);
  }

  int _imageIndexForVariant(ProductVariant variant) {
    return ProductVariantSupport.galleryImageIndexForVariant(_variants, variant);
  }

  ProductVariant? _variantForCarouselSync({
    bool preferSize = false,
    bool preferColor = false,
  }) {
    if (preferSize) {
      return ProductVariantSupport.matchVariant(
            _variants,
            color: _selectedColor,
            size: _selectedSize,
          ) ??
          ProductVariantSupport.matchVariant(
            _variants,
            size: _selectedSize,
          );
    }
    if (preferColor) {
      return ProductVariantSupport.matchVariant(
            _variants,
            color: _selectedColor,
            size: _selectedSize,
          ) ??
          ProductVariantSupport.matchVariant(
            _variants,
            color: _selectedColor,
          );
    }
    return _resolvedVariant ??
        ProductVariantSupport.matchVariant(
          _variants,
          color: _selectedColor,
          size: _selectedSize,
        );
  }

  void _syncCarouselToVariant(ProductVariant? variant) {
    if (variant == null) {
      return;
    }
    final nextIndex = _imageIndexForVariant(variant);
    if (nextIndex == _mediaPageIndex) {
      return;
    }
    setState(() => _mediaPageIndex = nextIndex);
  }

  void _syncCarouselToSelection({
    bool preferSize = false,
    bool preferColor = false,
  }) {
    _syncCarouselToVariant(
      _variantForCarouselSync(
        preferSize: preferSize,
        preferColor: preferColor,
      ),
    );
  }

  void _onMediaPageChanged(int index) {
    if (!_hasVariants) {
      setState(() => _mediaPageIndex = index);
      return;
    }

    final urls =
        readCatalogProductImageUrls(_displayProductData(widget.product.data));
    if (index < 0 || index >= urls.length) {
      return;
    }

    final scoped =
        ProductVariantSupport.variantsForImageUrl(_variants, urls[index]);
    if (scoped.isEmpty) {
      setState(() => _mediaPageIndex = index);
      return;
    }

    final picked = ProductVariantSupport.matchVariant(
          scoped,
          color: _selectedColor,
          size: _selectedSize,
        ) ??
        scoped.first;

    setState(() {
      _mediaPageIndex = index;
      _selectedVariantId = picked.id;
      _selectedColor =
          picked.color.trim().isEmpty ? null : picked.color.trim();
      _selectedSize = picked.size.trim().isEmpty ? null : picked.size.trim();
      _quantity = 1;
    });
    _warmShareImage(widget.product.data);
  }

  Map<String, dynamic> _pricingData(Map<String, dynamic> data) {
    final variant = _resolvedVariant;
    if (variant == null) {
      return data;
    }
    return <String, dynamic>{
      ...data,
      'price': variant.price,
    };
  }

  Map<String, dynamic> _displayProductData(Map<String, dynamic> data) {
    if (!_hasVariants) {
      return data;
    }

    final gallery = ProductVariantSupport.variantGalleryFields(_variants);
    final imageUrls = gallery['imageUrls'];
    if (imageUrls is! List || imageUrls.isEmpty) {
      return data;
    }

    return <String, dynamic>{
      ...data,
      'imageUrls': imageUrls,
      'thumbnailUrls': gallery['thumbnailUrls'] ?? imageUrls,
    };
  }

  void _warmShareImage(Map<String, dynamic> data) {
    CatalogShareImageCache.instance.warm(
      readCatalogProductShareImageUrl(_displayProductData(data)),
    );
  }

  String? _shareImageUrlFor(Map<String, dynamic> data) {
    final displayData = _displayProductData(data);
    final variant = _resolvedVariant;
    if (variant != null) {
      if (variant.imageUrl.trim().isNotEmpty) {
        return variant.imageUrl.trim();
      }
      if (variant.thumbnailUrl.trim().isNotEmpty) {
        return variant.thumbnailUrl.trim();
      }
    }
    return readCatalogProductShareAttachmentUrl(displayData);
  }

  bool get _variantSelectionRequired =>
      _hasVariants && _resolvedVariant == null;

  Widget _buildVariantPickers(Map<String, dynamic> data) {
    if (!_hasVariants) {
      return const SizedBox.shrink();
    }
    final colors = ProductVariantSupport.uniqueOptionValues(
      _variants,
      colors: true,
    );
    final sizes = ProductVariantSupport.uniqueOptionValues(
      _variants,
      colors: false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        if (colors.isNotEmpty) ...[
          Text(
            L10n.catalogColor,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: colors.map((color) {
              final selected = _selectedColor == color;
              return ProductVariantColorSwatch(
                storedColor: color,
                size: 34,
                selected: selected,
                onTap: () {
                  setState(() {
                    _selectedColor = color;
                    _selectedVariantId = null;
                    _quantity = 1;
                  });
                  _syncCarouselToSelection(preferColor: true);
                },
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 12),
        ],
        if (sizes.isNotEmpty) ...[
          Text(
            L10n.catalogSize,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sizes.map((size) {
              final selected = _selectedSize == size;
              return FilterChip(
                label: Text(size),
                selected: selected,
                onSelected: (selected) {
                  if (!selected) {
                    return;
                  }
                  setState(() {
                    _selectedSize = size;
                    _selectedVariantId = null;
                    _quantity = 1;
                  });
                  _syncCarouselToSelection(preferSize: true);
                },
              );
            }).toList(growable: false),
          ),
        ],
        if (_variantSelectionRequired)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              L10n.catalogSelectVariant,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final data = product.data;
    final pricingData = _pricingData(data);
    final displayData = _displayProductData(data);

    final String name = LocalizedProductText.nameForProduct(product);
    final String description = _cleanDescriptionWithoutToppings(
      LocalizedProductText.descriptionForProduct(product),
    );
    final num adjustedBasePrice =
        TaxPricingPolicy.resolveCustomerUnitPrice(pricingData);
    final String? imageUrl = _resolvedVariant?.thumbnailUrl.isNotEmpty == true
        ? _resolvedVariant!.thumbnailUrl
        : (_resolvedVariant?.imageUrl.isNotEmpty == true
              ? _resolvedVariant!.imageUrl
              : readCatalogProductImageUrl(displayData));
    final List<_ToppingGroup> toppingGroups = _extractToppings(data);
    final int? availableStock = _hasVariants
        ? _resolvedVariant?.stock
        : _extractAvailableStock(data);
    final int preparationTimeMinutes = _extractPreparationTimeMinutes(data);
    final int parcelWeightGrams = _extractParcelWeightGrams(data);
    final shopDistanceKm = computeCatalogShopDistanceKm(
      customerLatitude: widget.customerLatitude,
      customerLongitude: widget.customerLongitude,
      shopLatitude: product.shopLatitude,
      shopLongitude: product.shopLongitude,
    );
    final travelMinutes =
        DeliveryEtaPolicy.estimateTravelMinutesFromStraightDistanceKm(
      shopDistanceKm,
    );
    final String shopName = LocalizedProductText.shopNameForProduct(product);

    final List<_IndexedToppingOption> indexedToppings = <_IndexedToppingOption>[
      for (var groupIndex = 0; groupIndex < toppingGroups.length; groupIndex++)
        for (
          var optionIndex = 0;
          optionIndex < toppingGroups[groupIndex].options.length;
          optionIndex++
        )
          _IndexedToppingOption(
            key: '$groupIndex:$optionIndex',
            option: toppingGroups[groupIndex].options[optionIndex],
          ),
    ];

    final bool outOfStock = availableStock != null && availableStock <= 0;
    final int remainingAfterOrder = availableStock == null
        ? -1
        : (availableStock - _quantity).clamp(0, availableStock);
    final int maxQuantity = availableStock == null
        ? 99
        : (availableStock <= 0 ? 1 : availableStock);

    final selectedOptions = indexedToppings
        .where((entry) => _selectedToppings.contains(entry.key))
        .map((entry) => entry.option)
        .toList(growable: false);
    final toppingTotal = selectedOptions.fold<num>(
      0,
      (sum, option) => sum + option.adjustedPrice,
    );
    final merchantBasePrice = _resolvedVariant?.price ??
        TaxPricingPolicy.parseNumber(pricingData['price']);
    final discountPercent = TaxPricingPolicy.parseDiscountPercent(
      data['discountPercent'],
    );
    final toppingMerchantPayout = selectedOptions.fold<num>(
      0,
      (sum, option) => sum + TaxPricingPolicy.merchantToppingPayout(option.rawPrice),
    );
    final merchantUnitPayout =
        TaxPricingPolicy.resolveMerchantUnitPayout(data) + toppingMerchantPayout;
    final unitPrice = adjustedBasePrice + toppingTotal;
    final lineTotal = unitPrice * _quantity;

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
          Row(
            children: <Widget>[
              _ShopAvatar(imageUrl: product.shopImageUrl),
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
          SizedBox(
            height: 280,
            width: double.infinity,
            child: wrapCatalogImageWithDiscountBadge(
              productData: data,
              productId: product.id,
              shopId: product.shopId,
              child: CatalogProductMediaCarousel(
                key: ValueKey<String>(product.id),
                productData: displayData,
                name: name,
                enableVideo: true,
                playbackActive: widget.isCurrentProduct || widget.warmVideoPlayback,
                playVideo: widget.isCurrentProduct,
                fixedHeight: 280,
                fit: BoxFit.cover,
                borderRadius: 16,
                initialPage: _mediaPageIndex,
                pageIndex: _mediaPageIndex,
                onPageChanged: _onMediaPageChanged,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name.isEmpty ? L10n.catalogUnnamedProduct : name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          ProductDiscountPrice(
            productData: pricingData,
            productId: product.id,
            shopId: product.shopId,
          ),
          _buildVariantPickers(data),
          _ProductRatingSummary(productId: product.id),
          const SizedBox(height: 10),
          ProductReactionBar(
            productId: product.id,
            shopId: product.shopId,
            showShareAction: true,
            onCommentTap: () {
              showProductCommentsSheet(
                context: context,
                productId: product.id,
                shopId: product.shopId,
              );
            },
            onShareTap: () => shareCatalogProduct(
              product,
              context: context,
              productDataForImage: displayData,
              shareImageUrl: _shareImageUrlFor(data),
            ),
          ),
          const SizedBox(height: 10),
          if (description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF4B5563)),
            ),
          ],
          const SizedBox(height: 10),
          _ProductRecentReviews(productId: product.id),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.restaurant, color: Color(0xFFF57C00), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    L10n.catalogPrepTime(preparationTimeMinutes),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF9A3412),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (travelMinutes > 0) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.delivery_dining,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.catalogDeliveryEta(
                        travelMinutes,
                        L10n.formatDistanceKm(shopDistanceKm),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF1D4ED8),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (availableStock != null)
                Expanded(
                  child: Text(
                    L10n.catalogStockRemaining(availableStock),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: outOfStock
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFF1F2937),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    L10n.catalogStockUnlimited,
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
                      onPressed: _quantity > 1
                          ? () => setState(() => _quantity -= 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$_quantity',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: (!outOfStock && _quantity < maxQuantity)
                          ? () => setState(() => _quantity += 1)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (availableStock != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              outOfStock
                  ? L10n.catalogOutOfStock
                  : L10n.catalogStockAfterOrder(remainingAfterOrder),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: outOfStock
                    ? const Color(0xFFB91C1C)
                    : const Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (toppingGroups.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              L10n.catalogToppings,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 6),
            Column(
              children: <Widget>[
                for (
                  var groupIndex = 0;
                  groupIndex < toppingGroups.length;
                  groupIndex++
                ) ...<Widget>[
                  if (toppingGroups[groupIndex].heading?.isNotEmpty ==
                      true) ...<Widget>[
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
                  for (
                    var optionIndex = 0;
                    optionIndex < toppingGroups[groupIndex].options.length;
                    optionIndex++
                  )
                    Builder(
                      builder: (context) {
                        final option =
                            toppingGroups[groupIndex].options[optionIndex];
                        final selectionKey = '$groupIndex:$optionIndex';
                        final isChecked = _selectedToppings.contains(
                          selectionKey,
                        );
                        return CheckboxListTile(
                          value: isChecked,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: const Color(0xFFE55A00),
                          title: Text(
                            option.displayLabel,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF374151),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedToppings.add(selectionKey);
                              } else {
                                _selectedToppings.remove(selectionKey);
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
            '฿${TaxPricingPolicy.formatPrice(lineTotal)}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFFE55A00),
            ),
          ),
          if (_quantity > 1 || toppingTotal > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '฿${TaxPricingPolicy.formatPrice(unitPrice)} × $_quantity',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
              ],
            ),
          ),
        ),
        _CatalogProductAddToCartBar(
          outOfStock: outOfStock || _variantSelectionRequired,
          extraBottomPadding: widget.bottomInset,
          onAddToCart: () {
            final selectedNames = selectedOptions
                .map((option) => option.label)
                .toList(growable: false);
            final variant = _resolvedVariant;
            widget.onAddToCart(
              CartProductSelection(
                productId: product.id,
                shopId: product.shopId,
                shopName: shopName,
                shopLatitude: product.shopLatitude,
                shopLongitude: product.shopLongitude,
                productName: name.isEmpty ? L10n.productFallback : name,
                unitPrice: unitPrice,
                merchantBasePrice: merchantBasePrice,
                discountPercent: discountPercent,
                merchantUnitPayout: merchantUnitPayout,
                imageUrl: imageUrl,
                selectedToppings: selectedNames,
                quantity: _quantity,
                availableStock: availableStock,
                preparationTimeMinutes: preparationTimeMinutes,
                parcelWeightGrams: parcelWeightGrams,
                parcelLengthCm: _parsePositiveDouble(
                  data['parcelLengthCm'],
                ),
                parcelWidthCm: _parsePositiveDouble(
                  data['parcelWidthCm'],
                ),
                parcelHeightCm: _parsePositiveDouble(
                  data['parcelHeightCm'],
                ),
                variantId: variant?.id,
                selectedSize: variant?.size,
                selectedColor: variant?.color,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CatalogProductAddToCartBar extends StatelessWidget {
  const _CatalogProductAddToCartBar({
    required this.outOfStock,
    required this.onAddToCart,
    this.extraBottomPadding = 0,
  });

  final bool outOfStock;
  final VoidCallback onAddToCart;
  final double extraBottomPadding;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.only(bottom: extraBottomPadding),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: outOfStock ? null : onAddToCart,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(
                L10n.catalogAddToCart,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
