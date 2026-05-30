part of 'category_catalog_screen.dart';

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

class _CatalogShopPager extends StatefulWidget {
  const _CatalogShopPager({
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
  State<_CatalogShopPager> createState() => _CatalogShopPagerState();
}

class _CatalogShopPagerState extends State<_CatalogShopPager> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CatalogShopPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxIndex = widget.sections.length - 1;
    if (maxIndex >= 0 && _currentPage > maxIndex) {
      setState(() => _currentPage = maxIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(maxIndex);
        }
      });
    }
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
              'ร้าน ${_currentPage + 1} / $total',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF9A3412),
                  ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(total, (index) {
              final isActive = index == _currentPage;
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
              'ปัดซ้าย-ขวาเพื่อเปลี่ยนร้าน',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              return _ShopCatalogPage(
                section: widget.sections[index],
                customerLatitude: widget.customerLatitude,
                customerLongitude: widget.customerLongitude,
                onConfirmOrder: widget.onConfirmOrder,
                onNavigateToCart: widget.onNavigateToCart,
              );
            },
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
    final shopDistanceKm = computeCatalogShopDistanceKm(
      customerLatitude: customerLatitude,
      customerLongitude: customerLongitude,
      shopLatitude: section.shopLatitude,
      shopLongitude: section.shopLongitude,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ShopHeaderBanner(
            shopName: section.shopName,
            shopImageUrl: section.shopImageUrl,
            shopDistanceKm: shopDistanceKm,
            shopDescription: section.shopDescription,
            isNew: _isRecentlyUpdatedShop(section.shopUpdatedAt),
          ),
          const SizedBox(height: 16),
          _ShopProductsPanel(
            section: section,
            shopDistanceKm: shopDistanceKm,
            onConfirmOrder: onConfirmOrder,
            onNavigateToCart: onNavigateToCart,
          ),
        ],
      ),
    );
  }
}

class _ShopHeaderBanner extends StatelessWidget {
  const _ShopHeaderBanner({
    required this.shopName,
    required this.shopImageUrl,
    required this.shopDescription,
    required this.shopDistanceKm,
    required this.isNew,
  });

  final String? shopName;
  final String? shopImageUrl;
  final String? shopDescription;
  final double? shopDistanceKm;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final displayName =
        shopName?.trim().isNotEmpty == true ? shopName!.trim() : 'ร้านค้า';
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
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 1.35,
            child: hasImage
                ? CachedNetworkImage(
                    imageUrl: shopImageUrl!,
                    cacheManager: _localFirstImageCacheManager,
                    useOldImageOnUrlChange: true,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const ColoredBox(
                      color: Color(0xFFFFEDD5),
                      child: Center(
                        child: Icon(
                          Icons.storefront,
                          size: 48,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                    ),
                  )
                : const ColoredBox(
                    color: Color(0xFFFFEDD5),
                    child: Center(
                      child: Icon(
                        Icons.storefront,
                        size: 48,
                        color: Color(0xFF9A3412),
                      ),
                    ),
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
            if (isNew) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'ใหม่',
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
                'ห่าง $distanceText',
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
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final PublicCatalogSection section;
  final double? shopDistanceKm;
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
    final showTypeFilters = typeGroups.length > 1 ||
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
                    label: const Text('ทั้งหมด'),
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
                      label: Text(typeGroup.type),
                      selected: _selectedTypeKey == typeGroup.typeKey,
                      onSelected: (_) => setState(
                        () => _selectedTypeKey = typeGroup.typeKey,
                      ),
                      selectedColor: const Color(0xFFFFEDD5),
                      checkmarkColor: const Color(0xFF9A3412),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final typeGroup in visibleTypeGroups) ...<Widget>[
          if (_selectedTypeKey == null && showTypeFilters)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                typeGroup.type,
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
                padding: const EdgeInsets.only(top: 4, bottom: 8),
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
                itemCount: headingGroup.products.length,
                separatorBuilder: (_, __) => const SizedBox(width: spacing),
                itemBuilder: (context, index) {
                  final product = headingGroup.products[index];
                  return SizedBox(
                    width: cardSize.width,
                    height: cardSize.height,
                    child: CatalogProductCard(
                      product: product,
                      shopProducts: widget.section.products,
                      shopLatitude: widget.section.shopLatitude,
                      shopLongitude: widget.section.shopLongitude,
                      shopDistanceKm: widget.shopDistanceKm,
                      onConfirmOrder: widget.onConfirmOrder,
                      onNavigateToCart: widget.onNavigateToCart,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
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

  final groups = byType.entries
      .map((entry) {
        final typeLabel = typeLabels[entry.key] ?? fallbackType;
        final isFallback = typeLabel == fallbackType;
        return _CatalogTypeGroup(
          type: typeLabel,
          typeKey: entry.key,
          sortOrder:
              isFallback ? fallbackTypeSort : (typeSortByKey[entry.key] ?? 500000),
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
    final headingRaw = (product.data['catalogHeading'] ?? '').toString().trim();
    final heading = headingRaw.isNotEmpty ? headingRaw : fallbackHeading;
    final headingKey = _readCatalogSlug(
      product.data['catalogHeadingSlug'],
      heading,
    );

    headingLabels[headingKey] = heading;
    grouped.putIfAbsent(headingKey, () => <PublicCatalogProduct>[]).add(product);

    final sort = _parseCatalogSort(product.data['catalogHeadingSort']);
    if (heading != fallbackHeading && sort != null) {
      sortByHeading[headingKey] = sort;
    }
  }

  final groups = grouped.entries
      .map((entry) {
        final headingLabel = headingLabels[entry.key] ?? fallbackHeading;
        final isFallback = headingLabel == fallbackHeading;
        return _CatalogHeadingGroup(
          heading: headingLabel,
          sortOrder: isFallback ? fallbackSort : (sortByHeading[entry.key] ?? 500000),
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
    'เนื้อ',
    'หมู',
    'ไก่',
    'ปลา',
    'กุ้ง',
    'ปู',
    'หอย',
    'ปลาหมึก',
    'อาหารทะเล',
    'seafood',
    'meat',
    'chicken',
    'pork',
    'beef',
    'fish',
  ])) {
    return 'ของสด';
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
  ])) {
    return 'ผักสด';
  }

  if (_containsAny(source, const <String>[
    'เครื่องดื่ม',
    'น้ำ',
    'ชา',
    'กาแฟ',
    'beverage',
    'drink',
  ])) {
    return 'เครื่องดื่ม';
  }

  final catalogType = (data['catalogType'] ?? '').toString().trim();
  if (catalogType.isNotEmpty) {
    return catalogType;
  }
  final aiType = (data['aiProductType'] ?? '').toString().trim();
  if (aiType.isNotEmpty) {
    return aiType;
  }
  final productType = (data['productType'] ?? '').toString().trim();
  if (productType.isNotEmpty) {
    return productType;
  }
  return fallbackType;
}

bool _containsAny(String source, List<String> values) {
  return values.any((value) => source.contains(value));
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
