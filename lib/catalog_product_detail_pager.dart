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

  String get _shopName {
    final current = widget.products[_currentIndex];
    return current.shopName?.trim().isNotEmpty == true
        ? current.shopName!.trim()
        : 'ร้านค้า';
  }

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
                'ปัดซ้าย/ขวาเพื่อดูสินค้าอื่น (${_currentIndex + 1}/$total)',
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
          IconButton(
            tooltip: 'แชร์',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => shareCatalogProduct(
              widget.products[_currentIndex],
              context: context,
            ),
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
          return _CatalogProductDetailPage(
            product: widget.products[index],
            isCurrentProduct: index == _currentIndex,
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
        : 'สินค้า';

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
                      'เพิ่ม $quantity ชิ้นลงตะกร้าแล้ว',
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
                  label: const Text(
                    'ไปที่ตะกร้า',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
    this.customerLatitude,
    this.customerLongitude,
    required this.onAddToCart,
    this.bottomInset = 24,
  });

  final PublicCatalogProduct product;
  final bool isCurrentProduct;
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

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final data = product.data;

    final String name = (data['name'] ?? '').toString();
    final String description = _cleanDescriptionWithoutToppings(
      (data['description'] ?? '').toString(),
    );
    final num adjustedBasePrice = TaxPricingPolicy.resolveCustomerUnitPrice(data);
    final String? imageUrl = readCatalogProductImageUrl(data);
    final List<_ToppingGroup> toppingGroups = _extractToppings(data);
    final int? availableStock = _extractAvailableStock(data);
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
    final String shopName = product.shopName?.trim().isNotEmpty == true
        ? product.shopName!.trim()
        : 'ร้านค้า';

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
    final merchantBasePrice = TaxPricingPolicy.parseNumber(data['price']);
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
                productData: data,
                name: name,
                enableVideo: true,
                playbackActive: widget.isCurrentProduct,
                fixedHeight: 280,
                fit: BoxFit.contain,
                borderRadius: 16,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name.isEmpty ? 'ไม่ระบุชื่อสินค้า' : name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          ProductDiscountPrice(
            productData: data,
            productId: product.id,
            shopId: product.shopId,
          ),
          _ProductRatingSummary(productId: product.id),
          const SizedBox(height: 10),
          ProductReactionBar(
            productId: product.id,
            shopId: product.shopId,
            onCommentTap: () {
              showProductCommentComposerSheet(
                context: context,
                productId: product.id,
                shopId: product.shopId,
              );
            },
          ),
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
                    'เวลาเตรียมสินค้า: ประมาณ $preparationTimeMinutes นาที',
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
                      'เวลาส่งถึงคุณ: ประมาณ $travelMinutes นาที'
                      ' (ห่าง ${_formatDistanceKm(shopDistanceKm)!})',
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
                    'สต๊อกคงเหลือ: $availableStock',
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
                    'สต๊อกคงเหลือ: ไม่จำกัด',
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
                  ? 'สินค้าหมดสต๊อกชั่วคราว'
                  : 'จะเหลือหลังสั่งครั้งนี้ $remainingAfterOrder',
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
              'ท็อปปิ้ง',
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
          ProductCommentList(productId: product.id),
              ],
            ),
          ),
        ),
        _CatalogProductAddToCartBar(
          outOfStock: outOfStock,
          extraBottomPadding: widget.bottomInset,
          onAddToCart: () {
            final selectedNames = selectedOptions
                .map((option) => option.label)
                .toList(growable: false);
            widget.onAddToCart(
              CartProductSelection(
                productId: product.id,
                shopId: product.shopId,
                shopName: shopName,
                shopLatitude: product.shopLatitude,
                shopLongitude: product.shopLongitude,
                productName: name.isEmpty ? 'สินค้า' : name,
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
              label: const Text(
                'เพิ่มลงตะกร้า',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
