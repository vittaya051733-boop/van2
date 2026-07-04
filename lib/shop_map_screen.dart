import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlng;

import 'category_catalog_screen.dart';
import 'pricing_config_service.dart';
import 'public_catalog_service.dart';
import 'widgets/cached_app_image.dart';

class ShopMapScreen extends StatefulWidget {
  const ShopMapScreen({
    super.key,
    required this.userLatitude,
    required this.userLongitude,
    required this.userLocationLabel,
    this.onConfirmOrder,
    this.onNavigateToCart,
  });

  final double userLatitude;
  final double userLongitude;
  final String userLocationLabel;
  final ValueChanged<CartProductSelection>? onConfirmOrder;
  final VoidCallback? onNavigateToCart;

  @override
  State<ShopMapScreen> createState() => _ShopMapScreenState();
}

class _ShopMapScreenState extends State<ShopMapScreen> {
  static const double _initialZoom = 13;
  static const double _shopImageRadiusKmThreshold = 1.0;
  static const double _serviceAreaRadiusMeters = 10000;
  static const String _marketCenterLabel =
      'ตลาดโนนสูง ตำบลโนนสูง อำเภอเมืองอุดรธานี จังหวัดอุดรธานี';

  String? _selectedShopId;
  double _currentZoom = _initialZoom;
  late latlng.LatLng _currentCenter;
  late latlng.LatLng _marketCenter;
  bool _isShopListCollapsed = false;
  List<PublicCatalogSection> _shops = const <PublicCatalogSection>[];
  StreamSubscription<List<PublicCatalogSection>>? _sectionsSubscription;
  final GlobalKey<_ShopMapCanvasState> _mapCanvasKey = GlobalKey<_ShopMapCanvasState>();

  latlng.LatLng _readMarketCenter() {
    final config = PricingConfigService.instance.current;
    return latlng.LatLng(
      config.marketHubLatitude,
      config.marketHubLongitude,
    );
  }

  @override
  void initState() {
    super.initState();
    _marketCenter = _readMarketCenter();
    _currentCenter = _marketCenter;
    PricingConfigService.instance.addListener(_handlePricingConfigChanged);
    _sectionsSubscription = PublicCatalogService.streamAllSections().listen(
      _applySections,
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    PricingConfigService.instance.removeListener(_handlePricingConfigChanged);
    _sectionsSubscription?.cancel();
    super.dispose();
  }

  void _handlePricingConfigChanged() {
    final marketCenter = _readMarketCenter();
    if (!mounted) {
      return;
    }

    setState(() {
      _marketCenter = marketCenter;
      _currentCenter = marketCenter;
    });
    _mapCanvasKey.currentState?.moveTo(marketCenter, _currentZoom);
  }

  void _applySections(List<PublicCatalogSection> sections) {
    final shops = sections.where((section) {
      return section.shopLatitude != null && section.shopLongitude != null;
    }).toList(growable: false)
      ..sort((left, right) {
        final leftDistance = _distanceKmTo(left) ?? double.infinity;
        final rightDistance = _distanceKmTo(right) ?? double.infinity;
        return leftDistance.compareTo(rightDistance);
      });

    if (!mounted) {
      return;
    }

    setState(() => _shops = shops);
  }

  void _handleMapZoomChanged(double zoom, latlng.LatLng center) {
    final previousZoom = _currentZoom;
    final previousCenter = _currentCenter;
    _currentZoom = zoom;
    _currentCenter = center;

    if (kIsWeb) {
      if (!mounted || _mapViewportSize == Size.zero) {
        return;
      }
      final wasImageMode = _shouldShowShopImageMarkers(
        context,
        zoom: previousZoom,
        center: previousCenter,
      );
      final isImageMode = _shouldShowShopImageMarkers(
        context,
        zoom: zoom,
        center: center,
      );
      if (wasImageMode != isImageMode) {
        setState(() {});
      }
      return;
    }

    final zoomUnchanged = (zoom - previousZoom).abs() < 0.01;
    final centerUnchanged =
        (center.latitude - previousCenter.latitude).abs() < 0.00001 &&
            (center.longitude - previousCenter.longitude).abs() < 0.00001;
    if (zoomUnchanged && centerUnchanged) {
      return;
    }

    setState(() {});
  }

  void _selectShop(PublicCatalogSection shop) {
    final shopLatitude = shop.shopLatitude;
    final shopLongitude = shop.shopLongitude;
    if (shopLatitude == null || shopLongitude == null) {
      return;
    }

    setState(() => _selectedShopId = shop.shopId);
    final nextZoom = _currentZoom < 15 ? 15.0 : _currentZoom;
    _mapCanvasKey.currentState?.moveTo(
      latlng.LatLng(shopLatitude, shopLongitude),
      nextZoom,
    );
    if (kIsWeb) {
      _currentZoom = nextZoom;
      _currentCenter = latlng.LatLng(shopLatitude, shopLongitude);
    }
  }

  void _zoomBy(double delta) {
    final nextZoom = (_currentZoom + delta).clamp(5.0, 19.5);
    _mapCanvasKey.currentState?.zoomTo(nextZoom);
    if (!kIsWeb) {
      setState(() => _currentZoom = nextZoom);
    } else {
      _currentZoom = nextZoom;
    }
  }

  void _toggleShopListCollapsed() {
    setState(() {
      _isShopListCollapsed = !_isShopListCollapsed;
    });
  }

  Size _mapViewportSize = Size.zero;

  double _visibleRadiusKm(
    BuildContext context, {
    double? zoom,
    latlng.LatLng? center,
  }) {
    final mediaSize = _mapViewportSize == Size.zero
        ? MediaQuery.sizeOf(context)
        : _mapViewportSize;
    final mapWidthPx = mediaSize.width;
    final mapHeightPx = mediaSize.height * 0.45;
    final viewportRadiusPx = math.min(mapWidthPx, mapHeightPx) / 2;
    final mapCenter = center ?? _currentCenter;
    final mapZoom = zoom ?? _currentZoom;
    final latitudeRadians = mapCenter.latitude * math.pi / 180;
    final metersPerPixel =
        156543.03392 * math.cos(latitudeRadians) / math.pow(2, mapZoom);
    final radiusMeters = viewportRadiusPx * metersPerPixel;
    return radiusMeters / 1000;
  }

  bool _shouldShowShopImageMarkers(
    BuildContext context, {
    double? zoom,
    latlng.LatLng? center,
  }) {
    return _visibleRadiusKm(context, zoom: zoom, center: center) <=
        _shopImageRadiusKmThreshold;
  }

  void _openShopCatalog(PublicCatalogSection shop) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryCatalogScreen(
          title: shop.shopName?.trim().isNotEmpty == true
              ? shop.shopName!.trim()
              : 'ร้านค้า',
          shopIdFilter: shop.shopId,
          customerLatitude: widget.userLatitude,
          customerLongitude: widget.userLongitude,
          onConfirmOrder: widget.onConfirmOrder,
          onNavigateToCart: widget.onNavigateToCart,
        ),
      ),
    );
  }

  void _openShopFromMarker(PublicCatalogSection shop) {
    _selectShop(shop);
    _openShopCatalog(shop);
  }

  double? _distanceKmTo(PublicCatalogSection shop) {
    final shopLatitude = shop.shopLatitude;
    final shopLongitude = shop.shopLongitude;
    if (shopLatitude == null || shopLongitude == null) {
      return null;
    }

    final meters = Geolocator.distanceBetween(
      widget.userLatitude,
      widget.userLongitude,
      shopLatitude,
      shopLongitude,
    );
    return meters / 1000;
  }

  @override
  Widget build(BuildContext context) {
    _mapViewportSize = MediaQuery.sizeOf(context);
    final userPosition = latlng.LatLng(widget.userLatitude, widget.userLongitude);

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: const Text('แผนที่ร้าน'),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
      ),
      body: Builder(
        builder: (context) {
          if (_shops.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'ยังไม่พบร้านค้าที่มีพิกัดสำหรับแสดงบนแผนที่',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            );
          }

          final shops = _shops;
          final selectedShop = shops.cast<PublicCatalogSection?>().firstWhere(
                (shop) => shop?.shopId == _selectedShopId,
                orElse: () => shops.isNotEmpty ? shops.first : null,
              );
          final featuredShop = selectedShop ?? shops.first;
          final showShopImageMarkers =
              _shouldShowShopImageMarkers(context);
          final marketCenter = _marketCenter;
          final screenHeight = MediaQuery.of(context).size.height;
          final expandedShopListHeight = math.min(screenHeight * 0.38, 360.0);
          const collapsedShopListHeight = 104.0;

          return Column(
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    _ShopMapCanvas(
                      key: _mapCanvasKey,
                      shops: shops,
                      marketCenter: marketCenter,
                      serviceAreaRadiusMeters: _serviceAreaRadiusMeters,
                      userPosition: userPosition,
                      selectedShopId: selectedShop?.shopId,
                      showShopImageMarkers: showShopImageMarkers,
                      onShopTap: _openShopFromMarker,
                      onZoomChanged: _handleMapZoomChanged,
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'ร้านในพื้นที่ของคุณ',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF9A3412),
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${shops.length} ร้าน • ศูนย์กลาง $_marketCenterLabel',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF7C2D12),
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'วงกลมรัศมี 10 กม. จากตลาดโนนสูง',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF0F766E),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                showShopImageMarkers
                                    ? 'โหมดรูปร้าน: รัศมีที่แสดงไม่เกิน 1 กม.'
                                    : 'ซูมเข้าอีกเพื่อดูรูปร้านในรัศมี 1 กม.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF9A3412),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              onPressed: () => _zoomBy(1),
                              icon: const Icon(Icons.add),
                            ),
                            const Divider(height: 1),
                            IconButton(
                              onPressed: () => _zoomBy(-1),
                              icon: const Icon(Icons.remove),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: _isShopListCollapsed
                    ? collapsedShopListHeight
                    : expandedShopListHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 16,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 12),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleShopListCollapsed,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: <Widget>[
                              Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5E7EB),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      _isShopListCollapsed
                                          ? 'ย่อแถบร้านอยู่ แตะเพื่อขยาย'
                                          : 'ร้านใกล้คุณ ${shops.length} ร้าน',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF374151),
                                          ),
                                    ),
                                  ),
                                  Icon(
                                    _isShopListCollapsed
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_isShopListCollapsed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: _BottomShopListTile(
                            shop: featuredShop,
                            isSelected: true,
                            distanceKm: _distanceKmTo(featuredShop),
                            onTap: () => _selectShop(featuredShop),
                            onOpen: () => _openShopCatalog(featuredShop),
                            compact: true,
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: shops.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final shop = shops[index];
                              return _BottomShopListTile(
                                shop: shop,
                                isSelected: shop.shopId == selectedShop?.shopId,
                                distanceKm: _distanceKmTo(shop),
                                onTap: () => _selectShop(shop),
                                onOpen: () => _openShopCatalog(shop),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShopMapCanvas extends StatefulWidget {
  const _ShopMapCanvas({
    super.key,
    required this.shops,
    required this.marketCenter,
    required this.serviceAreaRadiusMeters,
    required this.userPosition,
    required this.selectedShopId,
    required this.showShopImageMarkers,
    required this.onShopTap,
    required this.onZoomChanged,
  });

  final List<PublicCatalogSection> shops;
  final latlng.LatLng marketCenter;
  final double serviceAreaRadiusMeters;
  final latlng.LatLng userPosition;
  final String? selectedShopId;
  final bool showShopImageMarkers;
  final ValueChanged<PublicCatalogSection> onShopTap;
  final void Function(double zoom, latlng.LatLng center) onZoomChanged;

  @override
  State<_ShopMapCanvas> createState() => _ShopMapCanvasState();
}

class _ShopMapCanvasState extends State<_ShopMapCanvas> {
  static const double _initialZoom = 13;
  static const String _marketCenterLabel =
      'ตลาดโนนสูง ตำบลโนนสูง อำเภอเมืองอุดรธานี จังหวัดอุดรธานี';

  final MapController _mapController = MapController();
  bool _isMapReady = false;
  latlng.LatLng? _pendingCenter;
  double? _pendingZoom;

  void moveTo(latlng.LatLng center, double zoom) {
    if (!_isMapReady) {
      _pendingCenter = center;
      _pendingZoom = zoom;
      return;
    }

    _mapController.move(center, zoom);
    _scheduleWebLayerRefresh();
  }

  void zoomTo(double zoom) {
    if (!_isMapReady) {
      _pendingZoom = zoom;
      return;
    }

    _mapController.move(_mapController.camera.center, zoom);
    _scheduleWebLayerRefresh();
  }

  void _scheduleWebLayerRefresh() {
    if (!kIsWeb || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _handleMapReady() {
    _isMapReady = true;
    final pendingCenter = _pendingCenter;
    final pendingZoom = _pendingZoom;
    if (pendingCenter != null && pendingZoom != null) {
      _pendingCenter = null;
      _pendingZoom = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isMapReady) {
          return;
        }
        _mapController.move(pendingCenter, pendingZoom);
        _scheduleWebLayerRefresh();
      });
    } else {
      _scheduleWebLayerRefresh();
    }
  }

  @override
  void didUpdateWidget(covariant _ShopMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marketCenter.latitude != widget.marketCenter.latitude ||
        oldWidget.marketCenter.longitude != widget.marketCenter.longitude) {
      moveTo(widget.marketCenter, _mapController.camera.zoom);
    }
    if (kIsWeb &&
        (oldWidget.shops.length != widget.shops.length ||
            oldWidget.selectedShopId != widget.selectedShopId ||
            oldWidget.showShopImageMarkers != widget.showShopImageMarkers ||
            oldWidget.marketCenter.latitude != widget.marketCenter.latitude ||
            oldWidget.marketCenter.longitude != widget.marketCenter.longitude)) {
      _scheduleWebLayerRefresh();
    }
  }

  void _handlePositionChanged(dynamic position, bool hasGesture) {
    final zoom = position.zoom as double?;
    final center = position.center as latlng.LatLng?;
    if (zoom == null || center == null) {
      return;
    }

    widget.onZoomChanged(zoom, center);
  }

  @override
  Widget build(BuildContext context) {
    final shopMarkers = widget.shops.map((shop) {
      final isSelected = shop.shopId == widget.selectedShopId;
      return Marker(
        point: latlng.LatLng(shop.shopLatitude!, shop.shopLongitude!),
        width: widget.showShopImageMarkers ? 92 : 54,
        height: widget.showShopImageMarkers ? 108 : 54,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () => widget.onShopTap(shop),
          child: widget.showShopImageMarkers
              ? _ShopImageMarker(
                  shop: shop,
                  isSelected: isSelected,
                )
              : _ShopPinMarker(isSelected: isSelected),
        ),
      );
    }).toList(growable: false);

    return FlutterMap(
      key: const ValueKey('van2-shop-map-canvas'),
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.marketCenter,
        initialZoom: _initialZoom,
        onMapReady: _handleMapReady,
        onPositionChanged: _handlePositionChanged,
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: kIsWeb
              ? 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: kIsWeb
              ? const <String>['a', 'b', 'c', 'd']
              : const <String>[],
          userAgentPackageName: 'com.vantalad.van2',
        ),
        CircleLayer(
          circles: <CircleMarker>[
            CircleMarker(
              point: widget.marketCenter,
              radius: widget.serviceAreaRadiusMeters,
              useRadiusInMeter: true,
              color: const Color(0x2558BFC1),
              borderColor: const Color(0xFF0F766E),
              borderStrokeWidth: 2,
            ),
          ],
        ),
        MarkerLayer(
          markers: <Marker>[
            Marker(
              point: widget.marketCenter,
              width: 180,
              height: 84,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      'ศูนย์กลาง $_marketCenterLabel',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const Icon(
                    Icons.place_rounded,
                    color: Color(0xFF0F766E),
                    size: 34,
                  ),
                ],
              ),
            ),
            Marker(
              point: widget.userPosition,
              width: 72,
              height: 72,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      'คุณอยู่ที่นี่',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F766E),
                          ),
                    ),
                  ),
                  const Icon(
                    Icons.my_location_rounded,
                    color: Color(0xFF0F766E),
                    size: 34,
                  ),
                ],
              ),
            ),
            ...shopMarkers,
          ],
        ),
        RichAttributionWidget(
          attributions: const <SourceAttribution>[
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

class _BottomShopListTile extends StatelessWidget {
  const _BottomShopListTile({
    required this.shop,
    required this.isSelected,
    required this.distanceKm,
    required this.onTap,
    required this.onOpen,
    this.compact = false,
  });

  final PublicCatalogSection shop;
  final bool isSelected;
  final double? distanceKm;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final shopName = shop.shopName?.trim().isNotEmpty == true
        ? shop.shopName!.trim()
        : 'ร้านค้า';
    final titleStyle = compact
        ? Theme.of(context).textTheme.titleSmall
        : Theme.of(context).textTheme.titleMedium;
    final subtitleStyle = compact
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;
    final imageSize = compact ? 40.0 : 48.0;
    final buttonPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 12);

    return Material(
      color: isSelected ? const Color(0xFFFFF3E0) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(compact ? 18 : 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: Row(
            children: <Widget>[
              Container(
                width: imageSize,
                height: imageSize,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFF57C00)
                      : const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(compact ? 14 : 16),
                ),
                clipBehavior: Clip.antiAlias,
                child: shop.shopImageUrl?.trim().isNotEmpty == true
                    ? CachedAppImage(
                        imageUrl: shop.shopImageUrl!.trim(),
                        width: imageSize,
                        height: imageSize,
                        fit: BoxFit.cover,
                        lightweight: true,
                        errorWidget: _BottomShopImageFallback(
                          isSelected: isSelected,
                        ),
                        placeholder: _BottomShopImageFallback(
                          isSelected: isSelected,
                        ),
                      )
                    : _BottomShopImageFallback(
                        isSelected: isSelected,
                      ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      distanceKm == null
                          ? 'ไม่พบระยะทาง'
                          : 'ห่างจากคุณ ${distanceKm!.toStringAsFixed(1)} กม.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF57C00),
                  foregroundColor: Colors.white,
                  padding: buttonPadding,
                  visualDensity: compact
                      ? const VisualDensity(horizontal: -1, vertical: -1)
                      : VisualDensity.standard,
                ),
                child: const Text('เข้าร้าน'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomShopImageFallback extends StatelessWidget {
  const _BottomShopImageFallback({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.store_mall_directory_outlined,
        color: isSelected ? Colors.white : const Color(0xFFEA580C),
      ),
    );
  }
}

class _ShopPinMarker extends StatelessWidget {
  const _ShopPinMarker({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.location_on,
      color: isSelected ? const Color(0xFFD84315) : const Color(0xFFEA580C),
      size: isSelected ? 42 : 36,
    );
  }
}

class _ShopImageMarker extends StatelessWidget {
  const _ShopImageMarker({required this.shop, required this.isSelected});

  final PublicCatalogSection shop;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final shopName = shop.shopName?.trim().isNotEmpty == true
        ? shop.shopName!.trim()
        : 'ร้านค้า';
    final markerSize = isSelected ? 56.0 : 50.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(maxWidth: 88),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF57C00) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 8,
              ),
            ],
          ),
          child: Text(
            shopName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF7C2D12),
                ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: markerSize,
          height: markerSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? const Color(0xFFF57C00) : Colors.white,
              width: 3,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
              ),
            ],
          ),
          child: kIsWeb
              ? (shop.shopImageUrl?.trim().isNotEmpty == true
                  ? CachedAppImage(
                      imageUrl: shop.shopImageUrl!.trim(),
                      width: markerSize,
                      height: markerSize,
                      fit: BoxFit.cover,
                      lightweight: true,
                      borderRadius: BorderRadius.circular(markerSize / 2),
                      errorWidget: _ShopImageFallback(isSelected: isSelected),
                    )
                  : _ShopImageFallback(isSelected: isSelected))
              : ClipOval(
                  child: shop.shopImageUrl?.trim().isNotEmpty == true
                      ? CachedAppImage(
                          imageUrl: shop.shopImageUrl!.trim(),
                          width: markerSize,
                          height: markerSize,
                          fit: BoxFit.cover,
                          lightweight: true,
                          errorWidget: _ShopImageFallback(isSelected: isSelected),
                          placeholder: _ShopImageFallback(isSelected: isSelected),
                        )
                      : _ShopImageFallback(isSelected: isSelected),
                ),
        ),
        Icon(
          Icons.location_on,
          color: isSelected ? const Color(0xFFD84315) : const Color(0xFFEA580C),
          size: 18,
        ),
      ],
    );
  }
}

class _ShopImageFallback extends StatelessWidget {
  const _ShopImageFallback({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFFEDD5) : const Color(0xFFF8FAFC),
      ),
      child: const Center(
        child: Icon(
          Icons.storefront,
          color: Color(0xFFEA580C),
          size: 26,
        ),
      ),
    );
  }
}