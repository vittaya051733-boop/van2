import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartLineItem {
  const CartLineItem({
    required this.productId,
    required this.shopId,
    required this.shopName,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.productName,
    required this.unitPrice,
    required this.imageUrl,
    required this.selectedToppings,
    required this.quantity,
    required this.availableStock,
  });

  final String productId;
  final String shopId;
  final String shopName;
  final double? shopLatitude;
  final double? shopLongitude;
  final String productName;
  final num unitPrice;
  final String? imageUrl;
  final List<String> selectedToppings;
  final int quantity;
  final int? availableStock;
}

class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.cartItems,
    required this.customerLatitude,
    required this.customerLongitude,
    required this.customerLocationLabel,
  });

  final List<CartLineItem> cartItems;
  final double customerLatitude;
  final double customerLongitude;
  final String customerLocationLabel;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const Duration _routeCacheTtl = Duration(hours: 24);
  static const String _routeCachePrefix = 'routes_cache_v1:';

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  _PaymentMethod _selectedPaymentMethod = _PaymentMethod.cashOnDelivery;
  late Future<_ShippingSummary> _shippingSummaryFuture;
  String _shippingKey = '';

  @override
  void initState() {
    super.initState();
    _refreshShippingIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant CartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshShippingIfNeeded();
  }

  void _refreshShippingIfNeeded({bool force = false}) {
    final nextKey = _buildShippingKey(
      cartItems: widget.cartItems,
      customerLatitude: widget.customerLatitude,
      customerLongitude: widget.customerLongitude,
    );
    if (!force && nextKey == _shippingKey) {
      return;
    }
    _shippingKey = nextKey;
    _shippingSummaryFuture = _calculateShipping(
      cartItems: widget.cartItems,
      customerLatitude: widget.customerLatitude,
      customerLongitude: widget.customerLongitude,
    );
  }

  String _buildShippingKey({
    required List<CartLineItem> cartItems,
    required double customerLatitude,
    required double customerLongitude,
  }) {
    final sorted = cartItems.toList()
      ..sort((a, b) {
        final byShop = a.shopId.compareTo(b.shopId);
        if (byShop != 0) {
          return byShop;
        }
        return a.productId.compareTo(b.productId);
      });
    final keyParts = sorted
        .map(
          (item) =>
              '${item.shopId}:${item.shopLatitude ?? 'na'}:${item.shopLongitude ?? 'na'}:${item.unitPrice}',
        )
        .join('|');
    return '${customerLatitude.toStringAsFixed(6)},${customerLongitude.toStringAsFixed(6)}|$keyParts';
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = widget.cartItems;

    if (cartItems.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: <Widget>[
              const _RiderOnlineStatusCard(),
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.shopping_cart_outlined, size: 42, color: Color(0xFF9CA3AF)),
                        SizedBox(height: 10),
                        Text(
                          'ตะกร้า',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                            fontSize: 24,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'ยังไม่มีสินค้าในตะกร้า',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final subtotal = cartItems.fold<num>(
      0,
      (subtotalAcc, item) => subtotalAcc + (item.unitPrice * item.quantity),
    );
    final itemCount = cartItems.fold<int>(0, (sum, item) => sum + item.quantity);
    return FutureBuilder<_ShippingSummary>(
      future: _shippingSummaryFuture,
      builder: (context, snapshot) {
        final shippingSummary = snapshot.data ?? _ShippingSummary.zero;
        final isCalculatingShipping = snapshot.connectionState != ConnectionState.done;
        final grandTotal = subtotal + shippingSummary.fee;

        return SafeArea(
          child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: _RiderOnlineStatusCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _CustomerLocationCard(
              label: widget.customerLocationLabel,
              latitude: widget.customerLatitude,
              longitude: widget.customerLongitude,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(
              children: <Widget>[
                Text(
                  'ตะกร้าของฉัน',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                ),
                const Spacer(),
                Text(
                  '$itemCount ชิ้น',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: cartItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = cartItems[index];
                final lineTotal = item.unitPrice * item.quantity;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 58,
                          height: 58,
                          child: item.imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: item.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const ColoredBox(
                                    color: Color(0xFFFFEDD5),
                                    child: Icon(Icons.fastfood, color: Color(0xFF9A3412)),
                                  ),
                                )
                              : const ColoredBox(
                                  color: Color(0xFFFFEDD5),
                                  child: Icon(Icons.fastfood, color: Color(0xFF9A3412)),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF6B7280),
                                  ),
                            ),
                            if (item.selectedToppings.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                'ท็อปปิ้ง: ${item.selectedToppings.join(', ')}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF4B5563),
                                    ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'จำนวน ${item.quantity} x ฿${item.unitPrice.toStringAsFixed(0)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF6B7280),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '฿${lineTotal.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFE55A00),
                            ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: const BoxDecoration(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'รวมค่าสินค้า',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '฿${subtotal.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFE55A00),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Text(
                      'ค่าส่ง',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1F2937),
                          ),
                    ),
                    const Spacer(),
                    Text(
                      isCalculatingShipping
                          ? 'กำลังคำนวณ...'
                          : '฿${_formatMoney(shippingSummary.fee)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isCalculatingShipping
                      ? 'กำลังคำนวณระยะทางจาก Google Routes API'
                      : shippingSummary.shopCount <= 1
                          ? 'ระยะทางร้านถึงลูกค้า ${_formatDistanceKm(shippingSummary.totalDistanceKm)} กม. • เวลา ${_formatMinutes(shippingSummary.totalDurationMinutes)} นาที'
                          : 'รวม ${shippingSummary.shopCount} ร้าน ระยะทางรวม ${_formatDistanceKm(shippingSummary.totalDistanceKm)} กม. • เวลา ${_formatMinutes(shippingSummary.totalDurationMinutes)} นาที',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                ),
                if (shippingSummary.byShop.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'รายละเอียดค่าส่งแยกร้าน',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1F2937),
                        ),
                  ),
                  const SizedBox(height: 4),
                  ...shippingSummary.byShop.map((shop) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${shop.shopName} • ${_formatDistanceKm(shop.distanceKm)} กม. • ${_formatMinutes(shop.durationMinutes)} นาที',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF4B5563),
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '฿${_formatMoney(shop.fee)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827),
                                ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                if (shippingSummary.missingShopCoordinates > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'บางร้านยังไม่มีพิกัด จึงคิดค่าส่งขั้นต่ำ 25 บาทให้ ${shippingSummary.missingShopCoordinates} ร้าน',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB45309),
                        ),
                  ),
                ],
                if (shippingSummary.routeUnavailableShops > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'บางร้านคำนวณเส้นทางไม่ได้ จึงใช้ระยะทางเส้นตรงในการคิดค่าส่งให้ ${shippingSummary.routeUnavailableShops} ร้าน',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB45309),
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Text(
                      'ยอดชำระทั้งหมด',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                    ),
                    const Spacer(),
                    Text(
                      isCalculatingShipping ? '...' : '฿${_formatMoney(grandTotal)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFE55A00),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'วิธีจ่าย',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937),
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _PaymentMethodChip(
                      label: 'จ่ายปลายทาง',
                      selected: _selectedPaymentMethod == _PaymentMethod.cashOnDelivery,
                      onTap: () {
                        setState(() => _selectedPaymentMethod = _PaymentMethod.cashOnDelivery);
                      },
                    ),
                    _PaymentMethodChip(
                      label: 'จ่ายผ่านบัตร',
                      selected: _selectedPaymentMethod == _PaymentMethod.card,
                      onTap: () {
                        setState(() => _selectedPaymentMethod = _PaymentMethod.card);
                      },
                    ),
                    _PaymentMethodChip(
                      label: 'จ่ายด้วยทรูมันนี่',
                      selected: _selectedPaymentMethod == _PaymentMethod.trueMoney,
                      onTap: () {
                        setState(() => _selectedPaymentMethod = _PaymentMethod.trueMoney);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
          ),
        );
      },
    );
  }

  Future<_ShippingSummary> _calculateShipping({
    required List<CartLineItem> cartItems,
    required double customerLatitude,
    required double customerLongitude,
  }) async {
    final uniqueByShop = <String, CartLineItem>{};
    for (final item in cartItems) {
      final existing = uniqueByShop[item.shopId];
      if (existing == null) {
        uniqueByShop[item.shopId] = item;
        continue;
      }

      final existingHasCoords = existing.shopLatitude != null && existing.shopLongitude != null;
      final nextHasCoords = item.shopLatitude != null && item.shopLongitude != null;
      if (!existingHasCoords && nextHasCoords) {
        uniqueByShop[item.shopId] = item;
      }
    }

    double shippingFee = 0;
    var missing = 0;
    var routeUnavailableShops = 0;
    var totalDistanceKm = 0.0;
    var totalDurationMinutes = 0.0;
    var shopCount = 0;
    final byShop = <_ShopShippingFee>[];

    for (final item in uniqueByShop.values) {
      final shopLat = item.shopLatitude;
      final shopLng = item.shopLongitude;
      if (shopLat == null || shopLng == null) {
        missing += 1;
        shopCount += 1;
        shippingFee += 25;
        byShop.add(
          _ShopShippingFee(
            shopName: item.shopName,
            distanceKm: 0,
            durationMinutes: 0,
            fee: 25,
          ),
        );
        continue;
      }

      final route = await _getRouteMetrics(
        originLatitude: shopLat,
        originLongitude: shopLng,
        destinationLatitude: customerLatitude,
        destinationLongitude: customerLongitude,
      );
      final metrics =
          route ??
          _buildFallbackRouteMetrics(
            originLatitude: shopLat,
            originLongitude: shopLng,
            destinationLatitude: customerLatitude,
            destinationLongitude: customerLongitude,
          );
      if (route == null) {
        routeUnavailableShops += 1;
      }

      final km = metrics.distanceKm;
      totalDistanceKm += km;
      totalDurationMinutes += metrics.durationMinutes;
      shopCount += 1;
      // 0-1 km must always cost 25 THB; after 1 km, add 12.5 THB per extra km.
      final billableKm = km < 1 ? 1.0 : km;
      final fee = 25 + ((billableKm - 1) * 12.5);
      shippingFee += fee;
      byShop.add(
        _ShopShippingFee(
          shopName: item.shopName,
          distanceKm: km,
          durationMinutes: metrics.durationMinutes,
          fee: fee,
        ),
      );
    }

    return _ShippingSummary(
      fee: shippingFee,
      missingShopCoordinates: missing,
      routeUnavailableShops: routeUnavailableShops,
      totalDistanceKm: totalDistanceKm,
      totalDurationMinutes: totalDurationMinutes,
      shopCount: shopCount,
      byShop: byShop,
    );
  }

  Future<_RouteMetrics?> _getRouteMetrics({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    final cacheKey = _buildRouteCacheKey(
      originLatitude: originLatitude,
      originLongitude: originLongitude,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
    );
    final cached = await _readRouteCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    try {
      final callable = _functions.httpsCallable('computeRouteMetrics');
      final result = await callable
          .call(<String, Object>{
            'originLatitude': originLatitude,
            'originLongitude': originLongitude,
            'destinationLatitude': destinationLatitude,
            'destinationLongitude': destinationLongitude,
          })
          .timeout(const Duration(seconds: 8));

      final payload = result.data;
      if (payload is! Map) {
        return null;
      }
      final distanceMeters = payload['distanceMeters'];
      final durationSeconds = payload['durationSeconds'];
      if (distanceMeters is! num || durationSeconds is! num) {
        return null;
      }

      final metrics = _RouteMetrics(
        distanceKm: distanceMeters / 1000.0,
        durationMinutes: durationSeconds.toDouble() / 60.0,
      );
      await _writeRouteCache(cacheKey, metrics);
      return metrics;
    } catch (_) {
      return null;
    }
  }

  _RouteMetrics _buildFallbackRouteMetrics({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) {
    final distanceMeters = Geolocator.distanceBetween(
      originLatitude,
      originLongitude,
      destinationLatitude,
      destinationLongitude,
    );
    final distanceKm = distanceMeters / 1000.0;
    final durationMinutes = distanceKm <= 0 ? 0.0 : (distanceKm / 30.0) * 60.0;
    return _RouteMetrics(
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
    );
  }

  String _buildRouteCacheKey({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) {
    return '${originLatitude.toStringAsFixed(5)},${originLongitude.toStringAsFixed(5)}->${destinationLatitude.toStringAsFixed(5)},${destinationLongitude.toStringAsFixed(5)}';
  }

  Future<_RouteMetrics?> _readRouteCache(String routeKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_routeCachePrefix$routeKey');
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final expiresAtMs = decoded['expiresAt'];
      final distanceKm = decoded['distanceKm'];
      final durationMinutes = decoded['durationMinutes'];
      if (expiresAtMs is! num || distanceKm is! num || durationMinutes is! num) {
        return null;
      }

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs.toInt());
      if (DateTime.now().isAfter(expiresAt)) {
        await prefs.remove('$_routeCachePrefix$routeKey');
        return null;
      }

      return _RouteMetrics(
        distanceKm: distanceKm.toDouble(),
        durationMinutes: durationMinutes.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeRouteCache(String routeKey, _RouteMetrics metrics) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(<String, Object>{
      'distanceKm': metrics.distanceKm,
      'durationMinutes': metrics.durationMinutes,
      'expiresAt': DateTime.now().add(_routeCacheTtl).millisecondsSinceEpoch,
    });
    await prefs.setString('$_routeCachePrefix$routeKey', payload);
  }

  String _formatMoney(num value) {
    final fixed = value.toStringAsFixed(1);
    if (fixed.endsWith('.0')) {
      return fixed.substring(0, fixed.length - 2);
    }
    return fixed;
  }

  String _formatDistanceKm(double value) {
    return value.toStringAsFixed(2);
  }

  String _formatMinutes(double value) {
    return value.toStringAsFixed(0);
  }
}

class _ShippingSummary {
  const _ShippingSummary({
    required this.fee,
    required this.missingShopCoordinates,
    required this.routeUnavailableShops,
    required this.totalDistanceKm,
    required this.totalDurationMinutes,
    required this.shopCount,
    required this.byShop,
  });

  final double fee;
  final int missingShopCoordinates;
  final int routeUnavailableShops;
  final double totalDistanceKm;
  final double totalDurationMinutes;
  final int shopCount;
  final List<_ShopShippingFee> byShop;

  static const zero = _ShippingSummary(
    fee: 0,
    missingShopCoordinates: 0,
    routeUnavailableShops: 0,
    totalDistanceKm: 0,
    totalDurationMinutes: 0,
    shopCount: 0,
    byShop: <_ShopShippingFee>[],
  );
}

class _ShopShippingFee {
  const _ShopShippingFee({
    required this.shopName,
    required this.distanceKm,
    required this.durationMinutes,
    required this.fee,
  });

  final String shopName;
  final double distanceKm;
  final double durationMinutes;
  final double fee;
}

class _RouteMetrics {
  const _RouteMetrics({
    required this.distanceKm,
    required this.durationMinutes,
  });

  final double distanceKm;
  final double durationMinutes;
}

enum _PaymentMethod {
  cashOnDelivery,
  card,
  trueMoney,
}

class _PaymentMethodChip extends StatelessWidget {
  const _PaymentMethodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFEDD5) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFE55A00) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF9A3412) : const Color(0xFF374151),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _RiderOnlineStatusCard extends StatelessWidget {
  const _RiderOnlineStatusCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('riders')
            .where('onlineReady', isEqualTo: true)
            .snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          final onlineCount = snapshot.data?.docs.length ?? 0;
          final hasError = snapshot.hasError;
          final isLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

          final title = hasError
              ? 'สถานะไรเดอร์ไม่พร้อมใช้งาน'
              : isLoading
                  ? 'กำลังตรวจสอบสถานะไรเดอร์...'
                  : onlineCount > 0
                      ? 'ไรเดอร์ออนไลน์ $onlineCount คน'
                      : 'ยังไม่มีไรเดอร์ออนไลน์';

          final subtitle = hasError
              ? 'เช็กสิทธิ์หรือโครงสร้างข้อมูล riders/onlineReady'
              : onlineCount > 0
                  ? 'พร้อมรับออเดอร์จากตะกร้าของคุณ'
                  : 'รอไรเดอร์ออนไลน์เพื่อรับงาน';

          return Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: hasError
                      ? const Color(0xFFFEE2E2)
                      : onlineCount > 0
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF3F4F6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delivery_dining,
                  size: 18,
                  color: hasError
                      ? const Color(0xFFDC2626)
                      : onlineCount > 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1F2937),
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'อัปเดตสด',
                            style: TextStyle(
                              color: Color(0xFF166534),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6B7280),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CustomerLocationCard extends StatelessWidget {
  const _CustomerLocationCard({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'พิกัดลูกค้าที่ใช้งาน',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF374151),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Lat ${latitude.toStringAsFixed(6)} • Lng ${longitude.toStringAsFixed(6)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
          ),
        ],
      ),
    );
  }
}
