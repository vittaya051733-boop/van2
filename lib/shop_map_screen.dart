import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlng;

import 'category_catalog_screen.dart';
import 'public_catalog_service.dart';
import 'widgets/cached_app_image.dart';

class ShopMapScreen extends StatefulWidget {
  const ShopMapScreen({
    super.key,
    required this.userLatitude,
    required this.userLongitude,
    required this.userLocationLabel,
  });

  final double userLatitude;
  final double userLongitude;
  final String userLocationLabel;

  @override
  State<ShopMapScreen> createState() => _ShopMapScreenState();
}

class _ShopMapScreenState extends State<ShopMapScreen> {
  static const double _initialZoom = 13;
  static const double _shopImageRadiusKmThreshold = 1.0;
  static const double _marketRadiusMeters = 10000;
  static const String _marketCenterLabel =
      'ตลาดโนนสูง ตำบลโนนสูง อำเภอเมือง จังหวัดอุดรธานี';
  static const latlng.LatLng _marketCenterFallback = latlng.LatLng(
    17.4138,
    102.8366,
  );

  final MapController _mapController = MapController();
  String? _selectedShopId;
  double _currentZoom = _initialZoom;
  late latlng.LatLng _currentCenter;
  latlng.LatLng? _marketCenter;
  bool _isResolvingMarketCenter = true;
  bool _isMapReady = false;
  bool _isShopListCollapsed = false;
  latlng.LatLng? _pendingCenter;
  double? _pendingZoom;

  @override
  void initState() {
    super.initState();
    _currentCenter = latlng.LatLng(widget.userLatitude, widget.userLongitude);
    _resolveMarketCenter();
  }

  Future<void> _resolveMarketCenter() async {
    try {
      final locations = await locationFromAddress(_marketCenterLabel);
      if (!mounted) {
        return;
      }

      final location = locations.isNotEmpty ? locations.first : null;
      final marketCenter = location == null
          ? _marketCenterFallback
          : latlng.LatLng(location.latitude, location.longitude);

      setState(() {
        _marketCenter = marketCenter;
        _currentCenter = marketCenter;
        _isResolvingMarketCenter = false;
      });
      _moveMapWhenReady(marketCenter, _initialZoom);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _marketCenter = _marketCenterFallback;
        _currentCenter = _marketCenterFallback;
        _isResolvingMarketCenter = false;
      });
      _moveMapWhenReady(_marketCenterFallback, _initialZoom);
    }
  }

  void _moveMapWhenReady(latlng.LatLng center, double zoom) {
    if (!_isMapReady) {
      _pendingCenter = center;
      _pendingZoom = zoom;
      return;
    }

    _mapController.move(center, zoom);
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
      });
    }
  }

  void _selectShop(PublicCatalogSection shop) {
    final shopLatitude = shop.shopLatitude;
    final shopLongitude = shop.shopLongitude;
    if (shopLatitude == null || shopLongitude == null) {
      return;
    }

    setState(() => _selectedShopId = shop.shopId);
    _moveMapWhenReady(
      latlng.LatLng(shopLatitude, shopLongitude),
      _currentZoom < 15 ? 15 : _currentZoom,
    );
  }

  void _handlePositionChanged(dynamic position, bool hasGesture) {
    final zoom = position.zoom as double?;
    final center = position.center as latlng.LatLng?;
    final zoomUnchanged = zoom == null || (zoom - _currentZoom).abs() < 0.01;
    final centerUnchanged =
        center == null ||
        (center.latitude - _currentCenter.latitude).abs() < 0.00001 &&
            (center.longitude - _currentCenter.longitude).abs() < 0.00001;
    if (zoomUnchanged && centerUnchanged) {
      return;
    }
    setState(() {
      if (zoom != null) {
        _currentZoom = zoom;
      }
      if (center != null) {
        _currentCenter = center;
      }
    });
  }

  void _zoomBy(double delta) {
    final nextZoom = (_currentZoom + delta).clamp(5.0, 19.5);
    final cameraCenter = _isMapReady ? _mapController.camera.center : _currentCenter;
    _moveMapWhenReady(cameraCenter, nextZoom);
    setState(() {
      _currentZoom = nextZoom;
      _currentCenter = cameraCenter;
    });
  }

  void _toggleShopListCollapsed() {
    setState(() {
      _isShopListCollapsed = !_isShopListCollapsed;
    });
  }

  double _visibleRadiusKm(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    final mapWidthPx = mediaSize.width;
    final mapHeightPx = mediaSize.height * 0.45;
    final viewportRadiusPx = math.min(mapWidthPx, mapHeightPx) / 2;
    final latitudeRadians = _currentCenter.latitude * math.pi / 180;
    final metersPerPixel =
        156543.03392 * math.cos(latitudeRadians) / math.pow(2, _currentZoom);
    final radiusMeters = viewportRadiusPx * metersPerPixel;
    return radiusMeters / 1000;
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
    final userPosition = latlng.LatLng(widget.userLatitude, widget.userLongitude);
    final showShopImageMarkers =
        _visibleRadiusKm(context) <= _shopImageRadiusKmThreshold;
    final marketCenter = _marketCenter ?? _marketCenterFallback;
    final screenHeight = MediaQuery.of(context).size.height;
    final expandedShopListHeight = math.min(screenHeight * 0.38, 360.0);
    const collapsedShopListHeight = 104.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        title: const Text('แผนที่ร้าน'),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<PublicCatalogSection>>(
        stream: PublicCatalogService.streamAllSections(),
        builder: (context, snapshot) {
          if (_isResolvingMarketCenter && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'ไม่สามารถโหลดตำแหน่งร้านได้ กรุณาตรวจสอบการเชื่อมต่อหรือลองใหม่\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final sections = snapshot.data ?? const <PublicCatalogSection>[];
          final shops = sections.where((section) {
            return section.shopLatitude != null && section.shopLongitude != null;
          }).toList(growable: false)
            ..sort((left, right) {
              final leftDistance = _distanceKmTo(left) ?? double.infinity;
              final rightDistance = _distanceKmTo(right) ?? double.infinity;
              return leftDistance.compareTo(rightDistance);
            });

          final selectedShop = shops.cast<PublicCatalogSection?>().firstWhere(
                (shop) => shop?.shopId == _selectedShopId,
                orElse: () => shops.isNotEmpty ? shops.first : null,
              );

          if (shops.isEmpty) {
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

          final featuredShop = selectedShop ?? shops.first;

          return Column(
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: selectedShop != null
                            ? latlng.LatLng(
                                selectedShop.shopLatitude!,
                                selectedShop.shopLongitude!,
                              )
                            : marketCenter,
                        initialZoom: _initialZoom,
                        onMapReady: _handleMapReady,
                        onPositionChanged: _handlePositionChanged,
                      ),
                      children: <Widget>[
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.van2',
                        ),
                        CircleLayer(
                          circles: <CircleMarker>[
                            CircleMarker(
                              point: marketCenter,
                              radius: _marketRadiusMeters,
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
                              point: marketCenter,
                              width: 180,
                              height: 84,
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
                              point: userPosition,
                              width: 72,
                              height: 72,
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
                            ...shops.map((shop) {
                              final isSelected = shop.shopId == selectedShop?.shopId;
                              return Marker(
                                point: latlng.LatLng(shop.shopLatitude!, shop.shopLongitude!),
                                width: showShopImageMarkers ? 92 : 54,
                                height: showShopImageMarkers ? 108 : 54,
                                child: GestureDetector(
                                  onTap: () => _openShopFromMarker(shop),
                                  child: showShopImageMarkers
                                      ? _ShopImageMarker(
                                          shop: shop,
                                          isSelected: isSelected,
                                        )
                                      : _ShopPinMarker(isSelected: isSelected),
                                ),
                              );
                            }),
                          ],
                        ),
                        RichAttributionWidget(
                          attributions: const <SourceAttribution>[
                            TextSourceAttribution('OpenStreetMap contributors'),
                          ],
                        ),
                      ],
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
          child: ClipOval(
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