part of 'category_catalog_screen.dart';

const double _catalogProductGroupGap = 4;
const double _catalogHeadingBottomGap = 4;

class _CatalogHeadingGroup {
  const _CatalogHeadingGroup({
    required this.heading,
    required this.sortOrder,
    required this.products,
  });

  final String heading;
  final int sortOrder;
  final List<PublicCatalogProduct> products;
}

class _CatalogTypeGroup {
  const _CatalogTypeGroup({
    required this.type,
    required this.typeKey,
    required this.sortOrder,
    required this.headings,
  });

  final String type;
  final String typeKey;
  final int sortOrder;
  final List<_CatalogHeadingGroup> headings;
}

class _CatalogShopsFeed extends StatefulWidget {
  const _CatalogShopsFeed({
    required this.sections,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final List<PublicCatalogSection> sections;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<_CatalogShopsFeed> createState() => _CatalogShopsFeedState();
}

class _CatalogShopsFeedState extends State<_CatalogShopsFeed> {
  int _prefetchedShopIndex = 0;
  int _currentShopIndex = 0;
  late List<GlobalKey> _shopSectionKeys;

  @override
  void initState() {
    super.initState();
    _shopSectionKeys = _buildShopSectionKeys(widget.sections.length);
    _prefetchShopsThrough(1);
  }

  @override
  void didUpdateWidget(covariant _CatalogShopsFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections.length != widget.sections.length) {
      _shopSectionKeys = _buildShopSectionKeys(widget.sections.length);
      _currentShopIndex = _currentShopIndex.clamp(
        0,
        widget.sections.length - 1,
      );
      _prefetchedShopIndex = 0;
      _prefetchShopsThrough(1);
      return;
    }
    if (oldWidget.sections != widget.sections) {
      _prefetchedShopIndex = 0;
      _prefetchShopsThrough(_currentShopIndex + 1);
    }
  }

  List<GlobalKey> _buildShopSectionKeys(int count) {
    return List<GlobalKey>.generate(count, (_) => GlobalKey());
  }

  void _prefetchShopsThrough(int lastIndexInclusive) {
    if (widget.sections.isEmpty) {
      return;
    }
    final target = lastIndexInclusive.clamp(0, widget.sections.length - 1);
    if (target < _prefetchedShopIndex) {
      return;
    }
    final batch = widget.sections
        .skip(_prefetchedShopIndex)
        .take(target - _prefetchedShopIndex + 1)
        .toList(growable: false);
    if (batch.isEmpty) {
      return;
    }
    _prefetchedShopIndex = target + 1;
    unawaited(
      AppImagePrefetch.prefetchCatalogSectionsImmediate(
        batch,
        productLimit: AppImagePrefetch.onTapPrefetchBatch,
      ),
    );
  }

  void _jumpToShop(int index) {
    if (index < 0 || index >= widget.sections.length) {
      return;
    }
    setState(() => _currentShopIndex = index);
    _prefetchShopsThrough(index + 1);

    final targetContext = _shopSectionKeys[index].currentContext;
    if (targetContext == null) {
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0,
      ),
    );
  }

  void _handleHorizontalSwipe(DragEndDetails details) {
    if (widget.sections.length <= 1) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -240) {
      _jumpToShop(_currentShopIndex + 1);
      return;
    }
    if (velocity > 240) {
      _jumpToShop(_currentShopIndex - 1);
    }
  }

  void _syncCurrentShopFromScroll() {
    if (widget.sections.length <= 1 || !mounted) {
      return;
    }

    final anchorY = MediaQuery.paddingOf(context).top + 132;
    var nextIndex = _currentShopIndex;
    var closestDistance = double.infinity;

    for (var index = 0; index < _shopSectionKeys.length; index++) {
      final targetContext = _shopSectionKeys[index].currentContext;
      if (targetContext == null) {
        continue;
      }
      final renderObject = targetContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }

      final topY = renderObject.localToGlobal(Offset.zero).dy;
      final distance = (topY - anchorY).abs();
      if (topY <= anchorY + 72 && distance < closestDistance) {
        closestDistance = distance;
        nextIndex = index;
      }
    }

    if (nextIndex != _currentShopIndex) {
      setState(() => _currentShopIndex = nextIndex);
      _prefetchShopsThrough(nextIndex + 1);
    }
  }

  void _handleScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _syncCurrentShopFromScroll();
    }

    if (widget.sections.length <= 1) {
      return;
    }
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return;
    }

    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) {
      return;
    }
    if (metrics.pixels < metrics.maxScrollExtent - 480) {
      return;
    }

    final nextIndex = _prefetchedShopIndex;
    if (nextIndex >= widget.sections.length) {
      return;
    }
    _prefetchShopsThrough(nextIndex + 1);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.sections.length;

    return Column(
      children: <Widget>[
        if (total > 1) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Text(
              L10n.catalogShopPager(_currentShopIndex + 1, total),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF9A3412),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(total, (index) {
              final isActive = index == _currentShopIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFE55A00)
                      : const Color(0xFFFED7AA),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              L10n.catalogSwipeShopHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: _handleHorizontalSwipe,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                _handleScroll(notification);
                return false;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: <Widget>[
                  for (var index = 0; index < widget.sections.length; index++) ...<Widget>[
                    if (index > 0)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(0, 4, 0, 8),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFE5E7EB),
                        ),
                      ),
                    KeyedSubtree(
                      key: _shopSectionKeys[index],
                      child: _ShopCatalogSection(
                        section: widget.sections[index],
                        customerLatitude: widget.customerLatitude,
                        customerLongitude: widget.customerLongitude,
                        onConfirmOrder: widget.onConfirmOrder,
                        onNavigateToCart: widget.onNavigateToCart,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShopCatalogPage extends StatelessWidget {
  const _ShopCatalogPage({
    required this.section,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final PublicCatalogSection section;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: _ShopCatalogSection(
        section: section,
        customerLatitude: customerLatitude,
        customerLongitude: customerLongitude,
        onConfirmOrder: onConfirmOrder,
        onNavigateToCart: onNavigateToCart,
      ),
    );
  }
}

class _ShopCatalogSection extends StatelessWidget {
  const _ShopCatalogSection({
    required this.section,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final PublicCatalogSection section;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  Widget build(BuildContext context) {
    final shopDistanceKm = computeCatalogShopDistanceKm(
      customerLatitude: customerLatitude,
      customerLongitude: customerLongitude,
      shopLatitude: section.shopLatitude,
      shopLongitude: section.shopLongitude,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ShopHeaderBanner(
          section: section,
          shopName: section.shopName,
          shopImageUrl: section.shopImageUrl,
          shopDistanceKm: shopDistanceKm,
          shopDescription: section.shopDescription,
          isNew: _isRecentlyUpdatedShop(section.shopUpdatedAt),
        ),
        const SizedBox(height: 8),
        _ShopProductsPanel(
          section: section,
          shopDistanceKm: shopDistanceKm,
          customerLatitude: customerLatitude,
          customerLongitude: customerLongitude,
          onConfirmOrder: onConfirmOrder,
          onNavigateToCart: onNavigateToCart,
        ),
      ],
    );
  }
}

class _ShopHeaderBanner extends StatelessWidget {
  const _ShopHeaderBanner({
    required this.section,
    required this.shopName,
    required this.shopImageUrl,
    required this.shopDescription,
    required this.shopDistanceKm,
    required this.isNew,
  });

  final PublicCatalogSection section;
  final String? shopName;
  final String? shopImageUrl;
  final String? shopDescription;
  final double? shopDistanceKm;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final displayName = LocalizedProductText.shopName(<String, dynamic>{
      'shopName': shopName,
    });
    final description = shopDescription?.trim();
    final distanceText = _formatDistanceKm(shopDistanceKm);
    final hasImage = shopImageUrl != null && shopImageUrl!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          clipBehavior: kIsWeb ? Clip.none : Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 1.35,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bannerWidth = constraints.maxWidth;
                final bannerHeight = constraints.maxHeight;
                if (!hasImage) {
                  return const ColoredBox(
                    color: Color(0xFFFFEDD5),
                    child: Center(
                      child: Icon(
                        Icons.storefront,
                        size: 48,
                        color: Color(0xFF9A3412),
                      ),
                    ),
                  );
                }
                return CachedAppImage(
                  imageUrl: shopImageUrl!,
                  width: bannerWidth,
                  height: bannerHeight,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(18),
                  lightweight: true,
                  errorWidget: const ColoredBox(
                    color: Color(0xFFFFEDD5),
                    child: Center(
                      child: Icon(
                        Icons.storefront,
                        size: 48,
                        color: Color(0xFF9A3412),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
            CatalogFavoriteToggleButton(
              favorite: CatalogFavorite.fromSection(section),
            ),
            if (isNew) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  L10n.catalogNewBadge,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (distanceText != null) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(
                Icons.near_me_outlined,
                size: 14,
                color: Color(0xFF6B7280),
              ),
              const SizedBox(width: 4),
              Text(
                L10n.catalogDistanceAway(distanceText),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
        if (description != null && description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF4B5563),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _ShopProductsPanel extends StatefulWidget {
  const _ShopProductsPanel({
    required this.section,
    required this.shopDistanceKm,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final PublicCatalogSection section;
  final double? shopDistanceKm;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<_ShopProductsPanel> createState() => _ShopProductsPanelState();
}

class _ShopProductsPanelState extends State<_ShopProductsPanel> {
  String? _selectedTypeKey;

  @override
  Widget build(BuildContext context) {
    final typeGroups = _groupProductsByCatalogType(widget.section.products);
    const fallbackType = 'อื่นๆ';
    final showTypeFilters =
        typeGroups.length > 1 ||
        (typeGroups.isNotEmpty && typeGroups.first.type != fallbackType);
    final visibleTypeGroups = _selectedTypeKey == null
        ? typeGroups
        : typeGroups
              .where((group) => group.typeKey == _selectedTypeKey)
              .toList(growable: false);

    final cardSize = catalogGridProductCardSize(context);
    const spacing = 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTypeFilters) ...<Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(L10n.catalogFilterAll),
                    selected: _selectedTypeKey == null,
                    onSelected: (_) => setState(() => _selectedTypeKey = null),
                    selectedColor: const Color(0xFFFFEDD5),
                    checkmarkColor: const Color(0xFF9A3412),
                  ),
                ),
                for (final typeGroup in typeGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(L10n.catalogTaxonomyLabel(typeGroup.type)),
                      selected: _selectedTypeKey == typeGroup.typeKey,
                      onSelected: (_) =>
                          setState(() => _selectedTypeKey = typeGroup.typeKey),
                      selectedColor: const Color(0xFFFFEDD5),
                      checkmarkColor: const Color(0xFF9A3412),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final typeGroup in visibleTypeGroups) ...<Widget>[
          if (_selectedTypeKey == null && showTypeFilters)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: _catalogHeadingBottomGap),
              child: Text(
                L10n.catalogTaxonomyLabel(typeGroup.type),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF9A3412),
                ),
              ),
            ),
          for (final headingGroup in typeGroup.headings) ...<Widget>[
            if (headingGroup.heading != 'อื่นๆ' ||
                typeGroup.headings.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: _catalogHeadingBottomGap),
                child: Text(
                  CatalogTaxonomy.displayHeading(headingGroup.heading),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            SizedBox(
              height: cardSize.height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                cacheExtent: 360,
                itemCount: headingGroup.products.length,
                separatorBuilder: (_, __) => const SizedBox(width: spacing),
                itemBuilder: (context, index) {
                  final product = headingGroup.products[index];
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: cardSize.width,
                      child: CatalogProductCard(
                        product: product,
                        shopProducts: widget.section.products,
                        shopLatitude: widget.section.shopLatitude,
                        shopLongitude: widget.section.shopLongitude,
                        shopDistanceKm: widget.shopDistanceKm,
                        customerLatitude: widget.customerLatitude,
                        customerLongitude: widget.customerLongitude,
                        onConfirmOrder: widget.onConfirmOrder,
                        onNavigateToCart: widget.onNavigateToCart,
                        pinPriceToBottom: true,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: _catalogProductGroupGap),
          ],
        ],
      ],
    );
  }
}

class NationwideMixedProductsFeed extends StatefulWidget {
  const NationwideMixedProductsFeed({
    super.key,
    required this.products,
    this.customerLatitude,
    this.customerLongitude,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final List<PublicCatalogProduct> products;
  final double? customerLatitude;
  final double? customerLongitude;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<NationwideMixedProductsFeed> createState() =>
      _NationwideMixedProductsFeedState();
}

class _NationwideMixedProductsFeedState extends State<NationwideMixedProductsFeed> {
  String? _selectedHeadingKey;

  Map<String, List<PublicCatalogProduct>> _productsByShopId() {
    final grouped = <String, List<PublicCatalogProduct>>{};
    for (final product in widget.products) {
      grouped
          .putIfAbsent(product.shopId, () => <PublicCatalogProduct>[])
          .add(product);
    }
    return grouped;
  }

  List<_CatalogHeadingGroup> _groupByHeading(List<PublicCatalogProduct> products) {
    const fallbackHeading = 'อื่นๆ';
    final byHeading = <String, List<PublicCatalogProduct>>{};
    final headingLabels = <String, String>{};
    final headingSortByKey = <String, int>{};

    for (final product in products) {
      final headingLabel = _readProductHeadingLabel(product.data, fallbackHeading);
      final headingKey = _readCatalogSlug(null, headingLabel);
      headingLabels[headingKey] = headingLabel;
      byHeading.putIfAbsent(headingKey, () => <PublicCatalogProduct>[]).add(product);

      final sort = _parseCatalogSort(product.data['catalogHeadingSort']);
      if (headingLabel != fallbackHeading && sort != null) {
        headingSortByKey[headingKey] = sort;
      }
    }

    final groups = byHeading.entries
        .map(
          (entry) => _CatalogHeadingGroup(
            heading: headingLabels[entry.key] ?? fallbackHeading,
            sortOrder: headingSortByKey[entry.key] ?? 999999,
            products: entry.value,
          ),
        )
        .toList(growable: false);

    groups.sort((left, right) {
      final bySort = left.sortOrder.compareTo(right.sortOrder);
      if (bySort != 0) {
        return bySort;
      }
      return left.heading.compareTo(right.heading);
    });

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) {
      return const SizedBox.shrink();
    }

    final productsByShopId = _productsByShopId();
    final headingGroups = _groupByHeading(widget.products);
    const fallbackHeading = 'อื่นๆ';
    final showHeadingFilters =
        headingGroups.length > 1 ||
        (headingGroups.isNotEmpty && headingGroups.first.heading != fallbackHeading);
    final visibleHeadingGroups = _selectedHeadingKey == null
        ? headingGroups
        : headingGroups
              .where(
                (group) =>
                    _readCatalogSlug(null, group.heading) == _selectedHeadingKey,
              )
              .toList(growable: false);

    final cardSize = catalogGridProductCardSize(context);
    const spacing = 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showHeadingFilters) ...<Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(L10n.catalogFilterAll),
                    selected: _selectedHeadingKey == null,
                    onSelected: (_) => setState(() => _selectedHeadingKey = null),
                    selectedColor: const Color(0xFFFFEDD5),
                    checkmarkColor: const Color(0xFF9A3412),
                  ),
                ),
                for (final headingGroup in headingGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(CatalogTaxonomy.displayHeading(headingGroup.heading)),
                      selected:
                          _selectedHeadingKey ==
                          _readCatalogSlug(null, headingGroup.heading),
                      onSelected: (_) => setState(
                        () => _selectedHeadingKey = _readCatalogSlug(
                          null,
                          headingGroup.heading,
                        ),
                      ),
                      selectedColor: const Color(0xFFFFEDD5),
                      checkmarkColor: const Color(0xFF9A3412),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final headingGroup in visibleHeadingGroups) ...<Widget>[
          if (headingGroup.heading != fallbackHeading ||
              headingGroups.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: _catalogHeadingBottomGap),
              child: Text(
                headingGroup.heading,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
          SizedBox(
            height: cardSize.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              cacheExtent: 360,
              itemCount: headingGroup.products.length,
              separatorBuilder: (_, __) => const SizedBox(width: spacing),
              itemBuilder: (context, index) {
                final product = headingGroup.products[index];
                final shopProducts =
                    productsByShopId[product.shopId] ?? <PublicCatalogProduct>[product];
                final shopDistanceKm = computeCatalogShopDistanceKm(
                  customerLatitude: widget.customerLatitude,
                  customerLongitude: widget.customerLongitude,
                  shopLatitude: product.shopLatitude,
                  shopLongitude: product.shopLongitude,
                );

                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: cardSize.width,
                    child: CatalogProductCard(
                      product: product,
                      shopProducts: shopProducts,
                      shopLatitude: product.shopLatitude,
                      shopLongitude: product.shopLongitude,
                      shopDistanceKm: shopDistanceKm,
                      customerLatitude: widget.customerLatitude,
                      customerLongitude: widget.customerLongitude,
                      onConfirmOrder: widget.onConfirmOrder,
                      onNavigateToCart: widget.onNavigateToCart,
                      pinPriceToBottom: true,
                    ),
                  ),
                );
              },
            ),
            ),
          const SizedBox(height: _catalogProductGroupGap),
        ],
      ],
    );
  }
}

List<_CatalogTypeGroup> _groupProductsByCatalogType(
  List<PublicCatalogProduct> products,
) {
  const fallbackType = 'อื่นๆ';
  const fallbackTypeSort = 999999;
  final byType = <String, List<PublicCatalogProduct>>{};
  final typeLabels = <String, String>{};
  final typeSortByKey = <String, int>{};

  for (final product in products) {
    final typeLabel = _readProductTypeLabel(product.data);
    final typeKey = _readCatalogSlug(null, typeLabel);

    typeLabels[typeKey] = typeLabel;
    byType.putIfAbsent(typeKey, () => <PublicCatalogProduct>[]).add(product);

    final sort = _parseCatalogSort(product.data['catalogTypeSort']);
    if (typeLabel != fallbackType && sort != null) {
      typeSortByKey[typeKey] = sort;
    }
  }

  final groups =
      byType.entries
          .map((entry) {
            final typeLabel = typeLabels[entry.key] ?? fallbackType;
            final isFallback = typeLabel == fallbackType;
            return _CatalogTypeGroup(
              type: typeLabel,
              typeKey: entry.key,
              sortOrder: isFallback
                  ? fallbackTypeSort
                  : (typeSortByKey[entry.key] ??
                        _defaultCatalogTypeSort(typeLabel)),
              headings: _groupProductsByCatalogHeading(entry.value),
            );
          })
          .toList(growable: false)
        ..sort((left, right) {
          final sortCompare = left.sortOrder.compareTo(right.sortOrder);
          if (sortCompare != 0) {
            return sortCompare;
          }
          return left.type.compareTo(right.type);
        });

  return groups;
}

List<_CatalogHeadingGroup> _groupProductsByCatalogHeading(
  List<PublicCatalogProduct> products,
) {
  const fallbackHeading = 'อื่นๆ';
  const fallbackSort = 999999;
  final grouped = <String, List<PublicCatalogProduct>>{};
  final headingLabels = <String, String>{};
  final sortByHeading = <String, int>{};

  for (final product in products) {
    final heading = _readProductHeadingLabel(product.data, fallbackHeading);
    final headingKey = _readCatalogSlug(
      product.data['catalogHeadingSlug'],
      heading,
    );

    headingLabels[headingKey] = heading;
    grouped
        .putIfAbsent(headingKey, () => <PublicCatalogProduct>[])
        .add(product);

    final sort = _parseCatalogSort(product.data['catalogHeadingSort']);
    if (heading != fallbackHeading && sort != null) {
      sortByHeading[headingKey] = sort;
    }
  }

  final groups =
      grouped.entries
          .map((entry) {
            final headingLabel = headingLabels[entry.key] ?? fallbackHeading;
            final isFallback = headingLabel == fallbackHeading;
            return _CatalogHeadingGroup(
              heading: headingLabel,
              sortOrder: isFallback
                  ? fallbackSort
                  : (sortByHeading[entry.key] ??
                        _defaultCatalogHeadingSort(headingLabel)),
              products: entry.value,
            );
          })
          .toList(growable: false)
        ..sort((left, right) {
          final sortCompare = left.sortOrder.compareTo(right.sortOrder);
          if (sortCompare != 0) {
            return sortCompare;
          }
          return left.heading.compareTo(right.heading);
        });

  return groups;
}

String _readProductTypeLabel(Map<String, dynamic> data) {
  const fallbackType = 'อื่นๆ';
  if (_usesStoredCatalogClassification(data)) {
    final storedType = data['catalogType']?.toString().trim();
    if (storedType != null && storedType.isNotEmpty) {
      return storedType;
    }
  }
  final serviceType = _readCatalogServiceTypeLabel(data);
  final source = [
    data['name'],
    data['description'],
    data['productName'],
    data['productCategory'],
    data['aiProductType'],
    data['productType'],
    data['catalogHeading'],
    data['catalogType'],
  ].map((value) => value?.toString().trim() ?? '').join(' ').toLowerCase();

  final requiredType = _readRequiredProductTypeOverride(source);
  if (requiredType != null) {
    return requiredType;
  }

  final existingType = _readExistingCatalogTypeLabel(data);

  if (serviceType == 'ร้านขายยา' && _readPharmacyHeadingLabel(source) != null) {
    return 'ยาและเวชภัณฑ์';
  }

  if (serviceType == 'ตลาด') {
    final marketType = _readMarketCatalogTypeLabel(source);
    if (marketType != null) {
      return marketType;
    }
  }

  if (existingType != null) {
    return existingType;
  }

  return fallbackType;
}

String catalogTypeForProductDataForRegressionTest(Map<String, dynamic> data) {
  return _readProductTypeLabel(data);
}

String catalogHeadingForProductDataForRegressionTest(
  Map<String, dynamic> data, {
  String fallbackHeading = 'อื่นๆ',
}) {
  return _readProductHeadingLabel(data, fallbackHeading);
}

String? _readRequiredProductTypeOverride(String source) {
  if (_containsAny(source, const <String>['แก้วมังกร', 'dragon fruit'])) {
    return 'ผลไม้';
  }

  final isFreshMeat = _containsAny(source, const <String>[
    'เนื้อไก่สด',
    'ไก่สด',
    'เนื้อสด',
    'หมูสด',
    'เป็ดสด',
    'fresh chicken',
    'fresh meat',
    'fresh pork',
    'raw chicken',
    'raw meat',
  ]);
  if (isFreshMeat) {
    return 'ของสด';
  }

  return null;
}

String _readProductHeadingLabel(
  Map<String, dynamic> data,
  String fallbackHeading,
) {
  if (_usesStoredCatalogClassification(data)) {
    final storedHeading = data['catalogHeading']?.toString().trim();
    if (storedHeading != null && storedHeading.isNotEmpty) {
      return storedHeading;
    }
  }
  final serviceType = _readCatalogServiceTypeLabel(data);
  final source = [
    data['name'],
    data['description'],
    data['productName'],
    data['productCategory'],
    data['aiProductType'],
    data['productType'],
    data['catalogHeading'],
    data['catalogType'],
  ].map((value) => value?.toString().trim() ?? '').join(' ').toLowerCase();

  if (serviceType == 'ร้านขายยา') {
    final pharmacyHeading = _readPharmacyHeadingLabel(source);
    if (pharmacyHeading != null) {
      return pharmacyHeading;
    }
  }

  if (serviceType == 'ตลาด') {
    final marketHeading = _readMarketCatalogHeadingLabel(source);
    if (marketHeading != null) {
      return marketHeading;
    }
  }

  final headingRaw = (data['catalogHeading'] ?? '').toString().trim();
  return headingRaw.isNotEmpty ? headingRaw : fallbackHeading;
}

String? _readExistingCatalogTypeLabel(Map<String, dynamic> data) {
  for (final key in <String>['catalogType', 'aiProductType', 'productType']) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _readCatalogServiceTypeLabel(Map<String, dynamic> data) {
  for (final key in <String>[
    'serviceType',
    'service_type',
    'shopServiceType',
    'shop_type',
    'storeType',
    'store_type',
    'businessType',
    'businessCategory',
    'business_category',
    'registrationType',
    'registration_type',
  ]) {
    final normalized = _normalizeCatalogServiceType(data[key]);
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }

  return '';
}

String _normalizeCatalogServiceType(Object? rawValue) {
  final normalized = rawValue?.toString().trim().toLowerCase() ?? '';
  if (normalized.isEmpty) {
    return '';
  }
  if (normalized.contains('ร้านอาหาร') ||
      normalized.contains('restaurant') ||
      normalized == 'food') {
    return 'ร้านอาหาร';
  }
  if (normalized.contains('ตลาด') || normalized.contains('market')) {
    return 'ตลาด';
  }
  if (normalized.contains('ร้านขายยา') ||
      normalized == 'ยาและเวชภัณฑ์' ||
      normalized == 'ยา' ||
      normalized.contains('pharmacy') ||
      normalized.contains('drugstore') ||
      normalized.contains('drug_store')) {
    return 'ร้านขายยา';
  }
  if (normalized.contains('ร้านค้า') ||
      normalized.contains('shop') ||
      normalized.contains('store') ||
      normalized.contains('retail') ||
      normalized.contains('mini_mart') ||
      normalized.contains('mini mart') ||
      normalized.contains('ของชำ') ||
      normalized.contains('ร้านชำ')) {
    return 'ร้านค้า';
  }
  return '';
}

String? _readMarketCatalogTypeLabel(String source) {
  final isSeafood = _containsAny(source, const <String>[
    'ปลา',
    'กุ้ง',
    'ปู',
    'หอย',
    'ปลาหมึก',
    'อาหารทะเล',
    'seafood',
    'fish',
    'shrimp',
    'crab',
    'squid',
    'shellfish',
  ]);
  final isDriedOrProcessed = _containsAny(source, const <String>[
    'อาหารทะเลแปรรูป',
    'แปรรูป',
    'ของแห้ง',
    'แห้ง',
    'อบแห้ง',
    'ตากแห้ง',
    'แดดเดียว',
    'เค็ม',
    'รมควัน',
    'ถนอมอาหาร',
    'processed',
    'dried',
    'dry',
    'smoked',
    'salted',
  ]);

  if (isSeafood && isDriedOrProcessed) {
    return 'อาหารทะเลแปรรูป';
  }
  if (isSeafood) {
    return 'อาหารทะเลสด';
  }
  if (_containsAny(source, const <String>[
    'เนื้อ',
    'หมู',
    'ไก่',
    'เป็ด',
    'วัว',
    'beef',
    'meat',
    'chicken',
    'pork',
    'duck',
  ])) {
    return 'ของสด';
  }
  if (_containsAny(source, const <String>['ไข่', 'เต้าหู้', 'tofu', 'egg'])) {
    return 'ไข่ / เต้าหู้';
  }
  if (_containsAny(source, const <String>[
    'แก้วมังกร',
    'มังกร',
    'ผลไม้',
    'fruit',
    'มะม่วง',
    'กล้วย',
    'ส้ม',
    'ทุเรียน',
    'แอปเปิล',
    'แอปเปิ้ล',
    'องุ่น',
    'แตงโม',
    'สับปะรด',
    'ลำไย',
    'ลิ้นจี่',
    'ฝรั่ง',
    'มังคุด',
    'เงาะ',
  ])) {
    return 'ผลไม้';
  }
  if (_containsAny(source, const <String>[
    'ผัก',
    'ผักสด',
    'vegetable',
    'คะน้า',
    'กะหล่ำ',
    'ผักบุ้ง',
    'แตงกวา',
    'มะเขือ',
    'ต้นหอม',
    'ผักชี',
    'พริก',
  ])) {
    return 'ผักสด';
  }
  if (_containsAny(source, const <String>[
    'เครื่องปรุง',
    'น้ำปลา',
    'ซีอิ๊ว',
    'ซอส',
    'น้ำมันหอย',
    'ผงชูรส',
    'เกลือ',
    'น้ำตาล',
    'กะปิ',
    'ปลาร้า',
    'seasoning',
    'sauce',
  ])) {
    return 'เครื่องปรุง / ซอส';
  }
  if (isDriedOrProcessed ||
      _containsAny(source, const <String>[
        'ข้าวสาร',
        'แป้ง',
        'ถั่ว',
        'ธัญพืช',
        'เส้นหมี่',
        'วุ้นเส้น',
        'บะหมี่',
        'มาม่า',
        'กะทิ',
        'วัตถุดิบ',
        'grocery',
        'pantry',
      ])) {
    return 'ของแห้ง / วัตถุดิบ';
  }
  if (_containsAny(source, const <String>[
    'อาหารพร้อมทาน',
    'พร้อมทาน',
    'ข้าวกล่อง',
    'ข้าวแกง',
    'แกง',
    'ผัด',
    'ทอด',
    'ต้ม',
    'ยำ',
    'กับข้าว',
    'prepared',
    'cooked',
  ])) {
    return 'อาหารพร้อมทาน';
  }
  if (_containsAny(source, const <String>[
    'ขนม',
    'เบเกอรี่',
    'เค้ก',
    'ปัง',
    'คุกกี้',
    'ของหวาน',
    'snack',
    'bakery',
    'dessert',
  ])) {
    return 'ขนม / เบเกอรี่';
  }
  if (_containsAny(source, const <String>[
    'เครื่องดื่ม',
    'น้ำดื่ม',
    'น้ำอัดลม',
    'ชา',
    'กาแฟ',
    'นม',
    'beverage',
    'drink',
    'coffee',
    'tea',
  ])) {
    return 'เครื่องดื่ม';
  }
  if (_containsAny(source, const <String>[
    'ชุดนักเรียน',
    'เครื่องแบบ',
    'uniform',
  ])) {
    return 'ชุดนักเรียน / เครื่องแบบ';
  }
  if (_containsAny(source, const <String>[
    'รองเท้า',
    'กระเป๋า',
    'แตะ',
    'sneaker',
    'shoe',
    'bag',
  ])) {
    return 'รองเท้า / กระเป๋า';
  }
  if (_containsAny(source, const <String>[
    'เสื้อ',
    'กางเกง',
    'กระโปรง',
    'เดรส',
    'ผ้า',
    'เสื้อผ้า',
    'clothes',
    'shirt',
    'pants',
    'dress',
  ])) {
    return 'เสื้อผ้า';
  }
  if (_containsAny(source, const <String>[
    'สมุด',
    'หนังสือ',
    'ดินสอ',
    'ปากกา',
    'ยางลบ',
    'ไม้บรรทัด',
    'เครื่องเขียน',
    'อุปกรณ์เรียน',
    'stationery',
    'notebook',
    'pencil',
    'pen',
  ])) {
    return 'เครื่องเขียน / อุปกรณ์เรียน';
  }
  if (_containsAny(source, const <String>[
    'น้ำยาล้างจาน',
    'ผงซักฟอก',
    'น้ำยาปรับผ้านุ่ม',
    'ไม้กวาด',
    'ถุงขยะ',
    'ทิชชู่',
    'ของใช้ในบ้าน',
    'household',
    'detergent',
  ])) {
    return 'ของใช้ในบ้าน';
  }
  if (_containsAny(source, const <String>[
    'สบู่',
    'แชมพู',
    'ยาสีฟัน',
    'แปรงสีฟัน',
    'ครีม',
    'โลชั่น',
    'ของใช้ส่วนตัว',
    'personal care',
    'shampoo',
    'soap',
  ])) {
    return 'ของใช้ส่วนตัว';
  }
  return null;
}

String? _readMarketCatalogHeadingLabel(String source) {
  if (_containsAny(source, const <String>['ชุดนักเรียน', 'เครื่องแบบ'])) {
    return 'ชุดนักเรียน';
  }
  if (_containsAny(source, const <String>['รองเท้านักเรียน'])) {
    return 'รองเท้านักเรียน';
  }
  if (_containsAny(source, const <String>['รองเท้า'])) {
    return 'รองเท้า';
  }
  if (_containsAny(source, const <String>['กระเป๋า'])) {
    return 'กระเป๋า';
  }
  if (_containsAny(source, const <String>['สมุด', 'กระดาษ'])) {
    return 'สมุด / กระดาษ';
  }
  if (_containsAny(source, const <String>[
    'ปากกา',
    'ดินสอ',
    'ยางลบ',
    'ไม้บรรทัด',
  ])) {
    return 'ปากกา / ดินสอ';
  }
  if (_containsAny(source, const <String>['เสื้อ'])) {
    return 'เสื้อ';
  }
  if (_containsAny(source, const <String>['กางเกง'])) {
    return 'กางเกง';
  }
  if (_containsAny(source, const <String>['กระโปรง'])) {
    return 'กระโปรง';
  }
  if (_containsAny(source, const <String>['หมู'])) {
    return 'หมูสด';
  }
  if (_containsAny(source, const <String>['ไก่'])) {
    return 'ไก่สด';
  }
  if (_containsAny(source, const <String>['เนื้อ', 'beef'])) {
    return 'เนื้อสด';
  }
  if (_containsAny(source, const <String>['กุ้ง'])) {
    return 'กุ้งสด';
  }
  if (_containsAny(source, const <String>['ปู'])) {
    return 'ปูสด';
  }
  if (_containsAny(source, const <String>['หอย'])) {
    return 'หอยสด';
  }
  if (_containsAny(source, const <String>['ปลาหมึกแห้ง'])) {
    return 'ปลาหมึกแห้ง';
  }
  if (_containsAny(source, const <String>['ปลาหมึก'])) {
    return 'ปลาหมึกสด';
  }
  if (_containsAny(source, const <String>['ปลาแห้ง', 'ปลาแดดเดียว'])) {
    return 'ปลาแห้ง / ปลาแดดเดียว';
  }
  if (_containsAny(source, const <String>['ปลา'])) {
    return 'ปลาสด';
  }
  if (_containsAny(source, const <String>['ไข่'])) {
    return 'ไข่';
  }
  if (_containsAny(source, const <String>['เต้าหู้'])) {
    return 'เต้าหู้';
  }
  if (_containsAny(source, const <String>['น้ำปลา'])) {
    return 'น้ำปลา';
  }
  if (_containsAny(source, const <String>['ซีอิ๊ว', 'ซอส', 'น้ำมันหอย'])) {
    return 'ซอส / ซีอิ๊ว';
  }
  if (_containsAny(source, const <String>['ข้าวสาร'])) {
    return 'ข้าวสาร';
  }
  if (_containsAny(source, const <String>[
    'เส้นหมี่',
    'วุ้นเส้น',
    'บะหมี่',
    'มาม่า',
  ])) {
    return 'เส้น / บะหมี่';
  }
  if (_containsAny(source, const <String>['ขนม'])) {
    return 'ขนม';
  }
  if (_containsAny(source, const <String>['เบเกอรี่', 'เค้ก', 'ปัง'])) {
    return 'เบเกอรี่';
  }
  if (_containsAny(source, const <String>['น้ำดื่ม', 'น้ำเปล่า'])) {
    return 'น้ำดื่ม';
  }
  if (_containsAny(source, const <String>['ชา'])) {
    return 'ชา';
  }
  if (_containsAny(source, const <String>['กาแฟ'])) {
    return 'กาแฟ';
  }
  if (_containsAny(source, const <String>[
    'แก้วมังกร',
    'มะม่วง',
    'กล้วย',
    'ส้ม',
    'ทุเรียน',
    'ผลไม้สด',
  ])) {
    return 'ผลไม้สด';
  }
  if (_containsAny(source, const <String>['ผงซักฟอก', 'น้ำยาปรับผ้านุ่ม'])) {
    return 'ซักผ้า';
  }
  if (_containsAny(source, const <String>['น้ำยาล้างจาน'])) {
    return 'ล้างจาน';
  }
  if (_containsAny(source, const <String>[
    'สบู่',
    'แชมพู',
    'ยาสีฟัน',
    'แปรงสีฟัน',
  ])) {
    return 'ของใช้ส่วนตัว';
  }
  return null;
}

String? _readPharmacyHeadingLabel(String source) {
  final hasPharmacySignal = _containsAny(source, const <String>[
    'ยา',
    'เวชภัณฑ์',
    'เภสัช',
    'pharmacy',
    'medicine',
    'drug',
    'medical',
    'พารา',
    'paracetamol',
    'ibuprofen',
    'ไอบู',
    'แก้แพ้',
    'loratadine',
    'cetirizine',
    'แก้ไอ',
    'ลดน้ำมูก',
    'ท้องเสีย',
    'ลดกรด',
    'ยาระบาย',
    'เกลือแร่',
    'ยาหม่อง',
    'เบตาดีน',
    'betadine',
    'พลาสเตอร์',
    'ผ้าก๊อซ',
    'สำลี',
    'แอลกอฮอล์',
    'หน้ากาก',
    'ถุงมือ',
    'ปรอทวัดไข้',
    'เครื่องวัดความดัน',
    'วิตามิน',
    'อาหารเสริม',
    'คอลลาเจน',
    'แคลเซียม',
    'ผ้าอ้อม',
    'ขวดนม',
    'นมผง',
    'ยาสีฟัน',
    'แปรงสีฟัน',
    'น้ำยาบ้วนปาก',
    'ครีมกันแดด',
    'โลชั่น',
    'โฟมล้างหน้า',
    'น้ำเกลือ',
  ]);
  if (!hasPharmacySignal) {
    return null;
  }

  if (_containsAny(source, const <String>[
    'พารา',
    'paracetamol',
    'ไอบู',
    'ibuprofen',
    'แก้ปวด',
    'ลดไข้',
    'ปวดหัว',
    'ปวดเมื่อย',
    'ไข้',
  ])) {
    return 'ยาแก้ปวด / ลดไข้';
  }
  if (_containsAny(source, const <String>[
    'แก้แพ้',
    'loratadine',
    'cetirizine',
    'หวัด',
    'แก้ไอ',
    'ไอ',
    'ลดน้ำมูก',
    'คัดจมูก',
    'เจ็บคอ',
  ])) {
    return 'ยาแก้แพ้ / หวัด / ไอ';
  }
  if (_containsAny(source, const <String>[
    'ท้องเสีย',
    'ลดกรด',
    'กรดไหลย้อน',
    'ยาระบาย',
    'เกลือแร่',
    'ors',
    'ท้องอืด',
    'ย่อยอาหาร',
    'คลื่นไส้',
    'อาเจียน',
  ])) {
    return 'ยาทางเดินอาหาร';
  }
  if (_containsAny(source, const <String>[
    'ยาทา',
    'ยาหม่อง',
    'เบตาดีน',
    'betadine',
    'ครีมยา',
    'ขี้ผึ้ง',
    'แผล',
    'เชื้อรา',
    'ผื่น',
    'สเปรย์ยา',
    'บาล์ม',
  ])) {
    return 'ยาภายนอก';
  }
  if (_containsAny(source, const <String>[
    'ผ้าก๊อซ',
    'ก๊อซ',
    'สำลี',
    'พลาสเตอร์',
    'แอลกอฮอล์',
    'น้ำเกลือ',
    'povidone',
    'cotton',
    'gauze',
    'bandage',
  ])) {
    return 'เวชภัณฑ์';
  }
  if (_containsAny(source, const <String>[
    'หน้ากาก',
    'ถุงมือ',
    'ปรอทวัดไข้',
    'เครื่องวัดความดัน',
    'เทอร์โมมิเตอร์',
    'ชุดตรวจ',
    'เครื่องพ่นยา',
    'อุปกรณ์การแพทย์',
  ])) {
    return 'อุปกรณ์การแพทย์';
  }
  if (_containsAny(source, const <String>[
    'วิตามิน',
    'อาหารเสริม',
    'คอลลาเจน',
    'แคลเซียม',
    'ซิงค์',
    'zinc',
    'วิตามินซี',
    'vitamin',
    'supplement',
    'fish oil',
    'น้ำมันปลา',
  ])) {
    return 'วิตามิน / อาหารเสริม';
  }
  if (_containsAny(source, const <String>[
    'แม่และเด็ก',
    'เด็ก',
    'ทารก',
    'ผ้าอ้อม',
    'ขวดนม',
    'นมผง',
    'จุกนม',
    'baby',
    'infant',
  ])) {
    return 'แม่และเด็ก';
  }
  if (_containsAny(source, const <String>[
    'ยาสีฟัน',
    'แปรงสีฟัน',
    'น้ำยาบ้วนปาก',
    'ไหมขัดฟัน',
    'ช่องปาก',
    'oral',
    'tooth',
    'mouthwash',
  ])) {
    return 'สุขภาพช่องปาก';
  }
  if (_containsAny(source, const <String>[
    'ครีมกันแดด',
    'โลชั่น',
    'สบู่',
    'แชมพู',
    'โฟมล้างหน้า',
    'เจลล้างมือ',
    'สกินแคร์',
    'ดูแลผิว',
    'ของใช้ส่วนตัว',
    'skincare',
    'sunscreen',
    'lotion',
    'shampoo',
  ])) {
    return 'ดูแลผิว / ของใช้ส่วนตัว';
  }

  return 'ยาและเวชภัณฑ์';
}

int _defaultCatalogTypeSort(String label) {
  switch (label.trim()) {
    case 'ผักสด':
      return 10;
    case 'ผลไม้':
      return 20;
    case 'เนื้อสัตว์':
      return 30;
    case 'อาหารทะเลสด':
      return 40;
    case 'อาหารทะเลแปรรูป':
      return 50;
    case 'ไข่ / เต้าหู้':
      return 60;
    case 'อาหารพร้อมทาน':
      return 70;
    case 'ของแห้ง / วัตถุดิบ':
    case 'ของแห้ง':
      return 80;
    case 'เครื่องปรุง / ซอส':
      return 90;
    case 'ขนม / เบเกอรี่':
      return 100;
    case 'เครื่องดื่ม':
      return 110;
    case 'เสื้อผ้า':
      return 120;
    case 'ชุดนักเรียน / เครื่องแบบ':
      return 130;
    case 'รองเท้า / กระเป๋า':
      return 140;
    case 'ของใช้ในบ้าน':
      return 150;
    case 'ของใช้ส่วนตัว':
      return 160;
    case 'เครื่องเขียน / อุปกรณ์เรียน':
      return 170;
    case 'ยาและเวชภัณฑ์':
      return 180;
    case 'ของสด':
      return 190;
    default:
      return 500000;
  }
}

int _defaultCatalogHeadingSort(String label) {
  switch (label.trim()) {
    case 'ผักใบ':
      return 10;
    case 'ผักสวนครัว':
      return 20;
    case 'ผลไม้สด':
      return 30;
    case 'หมูสด':
      return 40;
    case 'ไก่สด':
      return 50;
    case 'เนื้อสด':
      return 60;
    case 'ปลาสด':
      return 70;
    case 'กุ้งสด':
      return 80;
    case 'ปูสด':
      return 90;
    case 'หอยสด':
      return 100;
    case 'ปลาหมึกสด':
      return 110;
    case 'ปลาหมึกแห้ง':
      return 120;
    case 'ปลาแห้ง / ปลาแดดเดียว':
      return 130;
    case 'ไข่':
      return 140;
    case 'เต้าหู้':
      return 150;
    case 'ข้าวสาร':
      return 160;
    case 'เส้น / บะหมี่':
      return 170;
    case 'น้ำปลา':
      return 180;
    case 'ซอส / ซีอิ๊ว':
      return 190;
    case 'ขนม':
      return 200;
    case 'เบเกอรี่':
      return 210;
    case 'น้ำดื่ม':
      return 220;
    case 'ชา':
      return 230;
    case 'กาแฟ':
      return 240;
    case 'เสื้อ':
      return 250;
    case 'กางเกง':
      return 260;
    case 'กระโปรง':
      return 270;
    case 'ชุดนักเรียน':
      return 280;
    case 'รองเท้านักเรียน':
      return 290;
    case 'รองเท้า':
      return 300;
    case 'กระเป๋า':
      return 310;
    case 'สมุด / กระดาษ':
      return 320;
    case 'ปากกา / ดินสอ':
      return 330;
    case 'ซักผ้า':
      return 340;
    case 'ล้างจาน':
      return 350;
    case 'ของใช้ส่วนตัว':
      return 360;
    case 'ยาแก้ปวด / ลดไข้':
      return 400;
    case 'ยาแก้แพ้ / หวัด / ไอ':
      return 410;
    case 'ยาทางเดินอาหาร':
      return 420;
    case 'ยาภายนอก':
      return 430;
    case 'เวชภัณฑ์':
      return 440;
    case 'อุปกรณ์การแพทย์':
      return 450;
    case 'วิตามิน / อาหารเสริม':
      return 460;
    case 'แม่และเด็ก':
      return 470;
    case 'สุขภาพช่องปาก':
      return 480;
    case 'ดูแลผิว / ของใช้ส่วนตัว':
      return 490;
    default:
      return 500000;
  }
}

bool _containsAny(String source, List<String> values) {
  return values.any((value) => source.contains(value));
}

bool _usesStoredCatalogClassification(Map<String, dynamic> data) {
  if (data['catalogAdminLocked'] == true) {
    return true;
  }
  return data['catalogReviewStatus']?.toString().trim() == 'approved';
}

String _readCatalogSlug(Object? slugValue, String fallbackLabel) {
  final slug = slugValue?.toString().trim();
  if (slug != null && slug.isNotEmpty) {
    return slug;
  }
  return fallbackLabel;
}

int? _parseCatalogSort(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}
