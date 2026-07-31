import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:promptpay_qrcode_generate/promptpay_qrcode_generate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/payment_collection_config.dart';
import 'services/catalog_share.dart';
import 'services/favorites_service.dart';
import 'services/payment_qr_service.dart';
import 'services/app_image_prefetch.dart';
import 'market_pricing_policy.dart';
import 'models/promotion_models.dart';
import 'services/promotion_display_config_service.dart';
import 'shipping_pricing_policy.dart';
import 'utils/web_blob_download.dart';
import 'utils/app_check_guard.dart';
import 'widgets/cached_app_image.dart';
import 'widgets/online_rider_slider.dart';
import 'widgets/payment_brand_strip.dart';
import 'widgets/payment_checkout_sheet.dart';
import 'widgets/promotion_cart_panel.dart';
import 'models/omise_payment_channel.dart';

class CartLineItem {
  const CartLineItem({
    required this.productId,
    required this.shopId,
    required this.shopName,
    required this.shopLatitude,
    required this.shopLongitude,
    required this.productName,
    required this.unitPrice,
    required this.merchantBasePrice,
    required this.discountPercent,
    required this.merchantUnitPayout,
    required this.imageUrl,
    required this.selectedToppings,
    required this.quantity,
    required this.availableStock,
    required this.preparationTimeMinutes,
    this.parcelWeightGrams = 1000,
    this.parcelLengthCm,
    this.parcelWidthCm,
    this.parcelHeightCm,
  });

  final String productId;
  final String shopId;
  final String shopName;
  final double? shopLatitude;
  final double? shopLongitude;
  final String productName;
  final num unitPrice;
  final num merchantBasePrice;
  final double discountPercent;
  final num merchantUnitPayout;
  final String? imageUrl;
  final List<String> selectedToppings;
  final int quantity;
  final int? availableStock;
  final int preparationTimeMinutes;
  final int parcelWeightGrams;
  final double? parcelLengthCm;
  final double? parcelWidthCm;
  final double? parcelHeightCm;
}

class PaymentSlipSubmissionRequest {
  const PaymentSlipSubmissionRequest({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.grandTotal,
    this.checkoutContext,
  });

  final Uint8List bytes;
  final String fileName;
  final String? contentType;
  final int sizeBytes;
  final double grandTotal;
  final CartCheckoutContext? checkoutContext;
}

class PaymentSlipSubmissionResult {
  const PaymentSlipSubmissionResult({
    required this.orderIds,
    required this.message,
    required this.verificationStatus,
  });

  final List<String> orderIds;
  final String message;
  final String verificationStatus;
}

class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.cartItems,
    required this.customerLatitude,
    required this.customerLongitude,
    required this.customerLocationLabel,
    required this.onRemoveItem,
    required this.onPickCustomerLocation,
    required this.onApplySharedLocation,
    this.onConfirmCashOnDelivery,
    this.onSubmitOmisePayment,
    this.onOpenOrderRoadmap,
  });

  final List<CartLineItem> cartItems;
  final double customerLatitude;
  final double customerLongitude;
  final String customerLocationLabel;
  final void Function(int index) onRemoveItem;
  final VoidCallback onPickCustomerLocation;
  final VoidCallback onApplySharedLocation;
  final Future<List<String>> Function(CartCheckoutContext context)?
      onConfirmCashOnDelivery;
  final Future<List<String>> Function(
    OmisePaymentChannel channel,
    CartCheckoutContext context,
    double grandTotal,
  )? onSubmitOmisePayment;
  final Future<void> Function(List<String> orderIds)? onOpenOrderRoadmap;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with WidgetsBindingObserver {
  static const Duration _routeCacheTtl = Duration(days: 7);
  static const String _routeCachePrefix = 'routes_cache_v2:';

  /// Urban road distance is typically ~1.3–1.4× straight-line; used only when Routes API fails.
  static const double _haversineRoadFactor = 1.35;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  late Future<_ShippingSummary> _shippingSummaryFuture;
  late Future<_ServerCartTotals> _serverTotalsFuture;
  String _shippingKey = '';
  String _serverTotalsKey = '';
  final TextEditingController _couponController = TextEditingController();
  String? _appliedCouponCode;
  String? _pendingCouponCode;
  bool _isSubmittingCashOnDelivery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prefetchCartImages();
    _refreshShippingIfNeeded(force: true);
    _refreshServerTotalsIfNeeded(force: true);
  }

  void _prefetchCartImages() {
    AppImagePrefetch.scheduleImageUrlsPrefetch(
      widget.cartItems.map((item) => item.imageUrl),
      dedupeKey: 'cart:${widget.cartItems.map((item) => item.productId).join(',')}',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _couponController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cartItems != widget.cartItems) {
      _prefetchCartImages();
    }
    _refreshShippingIfNeeded();
    _refreshServerTotalsIfNeeded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
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

  void _refreshServerTotalsIfNeeded({bool force = false}) {
    final nextKey = _buildServerTotalsKey(
      cartItems: widget.cartItems,
      customerLatitude: widget.customerLatitude,
      customerLongitude: widget.customerLongitude,
    );
    if (!force && nextKey == _serverTotalsKey) {
      return;
    }
    _serverTotalsKey = nextKey;
    _serverTotalsFuture = _calculateServerTotals(
      cartItems: widget.cartItems,
      customerLatitude: widget.customerLatitude,
      customerLongitude: widget.customerLongitude,
      couponCode: _pendingCouponCode,
    );
  }

  void _retryServerTotals() {
    setState(() => _refreshServerTotalsIfNeeded(force: true));
  }

  CatalogFavorite _favoriteFromCartItem(CartLineItem item) {
    return CatalogFavorite(
      kind: CatalogFavorite.kindProduct,
      id: item.productId,
      shopId: item.shopId,
      title: item.productName,
      subtitle: item.shopName,
      imageUrl: item.imageUrl,
      productData: <String, dynamic>{
        'name': item.productName,
        'price': item.unitPrice,
      },
      shopName: item.shopName,
      shopLatitude: item.shopLatitude,
      shopLongitude: item.shopLongitude,
      addedAt: DateTime.now(),
    );
  }

  Future<void> _showCartItemDetails(CartLineItem item) async {
    final favorite = _favoriteFromCartItem(item);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final lineTotal = item.unitPrice * item.quantity;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.productName,
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    CatalogFavoriteToggleButton(favorite: favorite),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.shopName,
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.selectedToppings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'ท็อปปิ้ง: ${item.selectedToppings.join(', ')}',
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'จำนวน ${item.quantity} x ฿${item.unitPrice.toStringAsFixed(0)} = ฿${lineTotal.toStringAsFixed(0)}',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFE55A00),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => shareCartLineItem(
                    item,
                    context: sheetContext,
                  ),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('แชร์สินค้า'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    return '${customerLatitude.toStringAsFixed(4)},${customerLongitude.toStringAsFixed(4)}|$keyParts';
  }

  void _applyCouponCode() {
    final code = _couponController.text.trim();
    if (code.isEmpty) {
      return;
    }
    setState(() {
      _pendingCouponCode = code.toUpperCase();
      _refreshServerTotalsIfNeeded(force: true);
    });
  }

  void _clearCouponCode() {
    setState(() {
      _couponController.clear();
      _appliedCouponCode = null;
      _pendingCouponCode = null;
      _refreshServerTotalsIfNeeded(force: true);
    });
  }

  String _buildServerTotalsKey({
    required List<CartLineItem> cartItems,
    required double customerLatitude,
    required double customerLongitude,
  }) {
    final sorted = cartItems.toList()
      ..sort((a, b) {
        final byProduct = a.productId.compareTo(b.productId);
        if (byProduct != 0) {
          return byProduct;
        }
        final byShop = a.shopId.compareTo(b.shopId);
        if (byShop != 0) {
          return byShop;
        }
        return a.productName.compareTo(b.productName);
      });

    final keyParts = sorted
        .map(
          (item) =>
              '${item.productId}:${item.shopId}:${item.quantity}:${item.selectedToppings.join(',')}:${item.shopLatitude ?? 'na'}:${item.shopLongitude ?? 'na'}',
        )
        .join('|');
    final couponPart = _pendingCouponCode ?? '';
    return '${customerLatitude.toStringAsFixed(4)},${customerLongitude.toStringAsFixed(4)}|$couponPart|$keyParts';
  }

  @override
  Widget build(BuildContext context) {
    final displayConfig = PromotionDisplayConfigService.instance.current;
    final cartItems = widget.cartItems;

    if (cartItems.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: <Widget>[
              _CartHeaderRow(
                cartItems: cartItems,
                customerLatitude: widget.customerLatitude,
                customerLongitude: widget.customerLongitude,
                customerLocationLabel: widget.customerLocationLabel,
                onPickCustomerLocation: widget.onPickCustomerLocation,
                onApplySharedLocation: widget.onApplySharedLocation,
              ),
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 42,
                          color: Color(0xFF9CA3AF),
                        ),
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

    final localSubtotal = cartItems.fold<num>(
      0,
      (subtotalAcc, item) => subtotalAcc + (item.unitPrice * item.quantity),
    );
    final itemCount = cartItems.fold<int>(
      0,
      (countAcc, item) => countAcc + item.quantity,
    );
    return FutureBuilder<_ShippingSummary>(
      future: _shippingSummaryFuture,
      builder: (context, snapshot) {
        final shippingSummary = snapshot.data ?? _ShippingSummary.zero;
        final isCalculatingShipping =
            snapshot.connectionState != ConnectionState.done;
        final localGrandTotal =
            localSubtotal + shippingSummary.fee + shippingSummary.marketTotalFees;

        return FutureBuilder<_ServerCartTotals>(
          future: _serverTotalsFuture,
          builder: (context, serverSnapshot) {
            final serverTotals = serverSnapshot.data;
            final isCalculatingServerTotals =
                serverSnapshot.connectionState != ConnectionState.done;
            final isServerTotalTrusted = serverTotals?.trusted == true;
            final subtotal = serverTotals?.subtotal ?? localSubtotal.toDouble();
            final shippingFee =
                serverTotals?.shippingFee ?? shippingSummary.fee;
            final marketCollectionFee =
                serverTotals?.marketCollectionFee ??
                shippingSummary.marketCollectionFee;
            final marketServiceFee =
                serverTotals?.marketServiceFee ?? shippingSummary.marketServiceFee;
            final discounts =
                serverTotals?.discounts ?? CartDiscountSnapshot.empty;
            final appliedCouponCode =
                discounts.appliedCouponCode ?? _appliedCouponCode;
            final grandTotal =
                serverTotals?.grandTotal ?? localGrandTotal.toDouble();
            final checkoutQuoteId = serverTotals?.checkoutQuoteId;
            final canCheckout =
                isServerTotalTrusted &&
                !isCalculatingServerTotals &&
                checkoutQuoteId != null &&
                checkoutQuoteId.isNotEmpty;

            return SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: _CartHeaderRow(
                      cartItems: cartItems,
                      customerLatitude: widget.customerLatitude,
                      customerLongitude: widget.customerLongitude,
                      customerLocationLabel: widget.customerLocationLabel,
                      onPickCustomerLocation: widget.onPickCustomerLocation,
                      onApplySharedLocation: widget.onApplySharedLocation,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                    child: Row(
                      children: <Widget>[
                        Text(
                          'ตะกร้าของฉัน',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF111827),
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '$itemCount ชิ้น',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF6B7280)),
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
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _showCartItemDetails(item),
                            child: Container(
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
                                          ? CachedAppImage(
                                              imageUrl: item.imageUrl!,
                                              width: 58,
                                              height: 58,
                                              fit: BoxFit.cover,
                                              lightweight: true,
                                              errorWidget: const ColoredBox(
                                                color: Color(0xFFFFEDD5),
                                                child: Icon(
                                                  Icons.fastfood,
                                                  color: Color(0xFF9A3412),
                                                ),
                                              ),
                                            )
                                          : const ColoredBox(
                                              color: Color(0xFFFFEDD5),
                                              child: Icon(
                                                Icons.fastfood,
                                                color: Color(0xFF9A3412),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          item.productName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item.shopName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF6B7280),
                                              ),
                                        ),
                                        if (item
                                            .selectedToppings
                                            .isNotEmpty) ...<Widget>[
                                          const SizedBox(height: 4),
                                          Text(
                                            'ท็อปปิ้ง: ${item.selectedToppings.join(', ')}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xFF4B5563,
                                                  ),
                                                ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          'จำนวน ${item.quantity} x ฿${item.unitPrice.toStringAsFixed(0)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF6B7280),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: <Widget>[
                                      Text(
                                        '฿${lineTotal.toStringAsFixed(0)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFFE55A00),
                                            ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            widget.onRemoveItem(index),
                                        tooltip: 'ลบสินค้า',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Color(0xFFDC2626),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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
                        PromotionCartPanel(
                          config: displayConfig,
                          discounts: discounts,
                          couponController: _couponController,
                          appliedCouponCode: appliedCouponCode,
                          isApplyingCoupon: isCalculatingServerTotals,
                          onApplyCoupon: _applyCouponCode,
                          onClearCoupon: _clearCouponCode,
                        ),
                        Row(
                          children: <Widget>[
                            Text(
                              'รวมค่าสินค้า',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            Text(
                              '฿${subtotal.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
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
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1F2937),
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              isCalculatingShipping
                                  ? 'กำลังคำนวณ...'
                                  : '฿${_formatMoney(shippingFee)}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
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
                              : 'ค่าส่งรวม ${_formatDistanceKm(shippingSummary.totalDistanceKm)} กม. • เวลา ${_formatMinutes(shippingSummary.totalDurationMinutes)} นาที',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF6B7280)),
                        ),
                        if (marketCollectionFee > 0) ...<Widget>[
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              Text(
                                'ค่ารวบรวมสินค้าหลายร้าน (ตลาด)',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1F2937),
                                    ),
                              ),
                              const Spacer(),
                              Text(
                                '฿${_formatMoney(marketCollectionFee)}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF111827),
                                    ),
                              ),
                            ],
                          ),
                        ],
                        if (marketServiceFee > 0) ...<Widget>[
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              Text(
                                'ค่าบริการ (ตลาด)',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1F2937),
                                    ),
                              ),
                              const Spacer(),
                              Text(
                                '฿${_formatMoney(marketServiceFee)}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF111827),
                                    ),
                              ),
                            ],
                          ),
                        ],
                        PromotionDiscountBreakdown(discounts: discounts),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Text(
                              'ยอดชำระทั้งหมด',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF111827),
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              isCalculatingShipping
                                  ? '...'
                                  : '฿${_formatMoney(grandTotal)}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFFE55A00),
                                  ),
                            ),
                          ],
                        ),
                        if (!isServerTotalTrusted) ...<Widget>[
                          const SizedBox(height: 10),
                          _UntrustedCartTotalWarning(
                            isLoading: isCalculatingServerTotals,
                            onRetry: _retryServerTotals,
                          ),
                        ],
                        const SizedBox(height: 12),
                        const PaymentBrandStrip(compact: true),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: !canCheckout
                                ? null
                                : () {
                                    _openPaymentSheet(
                                      subtotal: subtotal,
                                      shippingFee: shippingFee,
                                      grandTotal: grandTotal,
                                      discounts: discounts,
                                      appliedCouponCode: appliedCouponCode,
                                      checkoutQuoteId: checkoutQuoteId,
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: const Color(0xFFE55A00),
                            ),
                            child: const Text(
                              'ชำระ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<_ServerCartTotals> _calculateServerTotals({
    required List<CartLineItem> cartItems,
    required double customerLatitude,
    required double customerLongitude,
    String? couponCode,
  }) async {
    if (cartItems.isEmpty) {
      return _ServerCartTotals.zero;
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await AppCheckGuard.ensureCheckoutReady();
        final callable = _functions.httpsCallable('calculateCartTotals');
        final response = await callable
            .call(<String, dynamic>{
              'customerLatitude': customerLatitude,
              'customerLongitude': customerLongitude,
              'persistQuote': true,
              if (couponCode != null && couponCode.isNotEmpty)
                'couponCode': couponCode,
              'items': cartItems
                  .map(
                    (item) => <String, dynamic>{
                      'productId': item.productId,
                      'shopId': item.shopId,
                      'quantity': item.quantity,
                      'selectedToppings': item.selectedToppings,
                      'shopLatitude': item.shopLatitude,
                      'shopLongitude': item.shopLongitude,
                    },
                  )
                  .toList(growable: false),
            })
            .timeout(const Duration(seconds: 10));

        final payload = response.data;
        if (payload is! Map) {
          continue;
        }

        final subtotal = (payload['subtotal'] as num?)?.toDouble() ?? 0;
        final shippingFee = (payload['shippingFee'] as num?)?.toDouble() ?? 0;
        final marketCollectionFee =
            (payload['marketCollectionFee'] as num?)?.toDouble() ?? 0;
        final marketServiceFee =
            (payload['marketServiceFee'] as num?)?.toDouble() ?? 0;
        final grandTotal = (payload['grandTotal'] as num?)?.toDouble() ?? 0;
        final discounts = CartDiscountSnapshot.fromServerPayload(
          Map<String, dynamic>.from(payload),
        );
        final checkoutQuoteId = payload['checkoutQuoteId']?.toString().trim();
        if (mounted) {
          final appliedCode = discounts.appliedCouponCode;
          if (appliedCode != null && appliedCode.isNotEmpty) {
            _appliedCouponCode = appliedCode;
            _pendingCouponCode = appliedCode;
          } else if (couponCode != null &&
              couponCode.isNotEmpty &&
              discounts.couponError != null) {
            _appliedCouponCode = null;
          }
        }
        return _ServerCartTotals(
          subtotal: subtotal,
          shippingFee: shippingFee,
          marketCollectionFee: marketCollectionFee,
          marketServiceFee: marketServiceFee,
          grandTotal: grandTotal,
          discounts: discounts,
          trusted: true,
          checkoutQuoteId:
              checkoutQuoteId != null && checkoutQuoteId.isNotEmpty
                  ? checkoutQuoteId
                  : null,
        );
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 600 * (attempt + 1)),
          );
        }
      }
    }

    return _ServerCartTotals.zero;
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

      final existingHasCoords =
          existing.shopLatitude != null && existing.shopLongitude != null;
      final nextHasCoords =
          item.shopLatitude != null && item.shopLongitude != null;
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
      if (shopLat == null ||
          shopLng == null ||
          (shopLat == 0 && shopLng == 0)) {
        missing += 1;
        shopCount += 1;
        final missingFee = ShippingPricingPolicy.shippingMissingCoordsFee;
        shippingFee += missingFee;
        byShop.add(
          _ShopShippingFee(
            shopName: item.shopName,
            distanceKm: 0,
            durationMinutes: 0,
            fee: missingFee,
          ),
        );
        continue;
      }

      final metrics = await _resolveRouteMetrics(
        originLatitude: shopLat,
        originLongitude: shopLng,
        destinationLatitude: customerLatitude,
        destinationLongitude: customerLongitude,
      );
      if (metrics.usedFallback) {
        routeUnavailableShops += 1;
      }

      final km = metrics.distanceKm;
      totalDistanceKm += km;
      totalDurationMinutes += metrics.durationMinutes;
      shopCount += 1;
      final fee = ShippingPricingPolicy.computeLocalShippingFee(km);
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

    final marketFees = MarketPricingPolicy.computeCheckoutFees(
      uniqueByShop.values.map(
        (item) => MarketShopLocation(
          shopId: item.shopId,
          latitude: item.shopLatitude,
          longitude: item.shopLongitude,
        ),
      ),
    );

    return _ShippingSummary(
      fee: shippingFee,
      missingShopCoordinates: missing,
      routeUnavailableShops: routeUnavailableShops,
      totalDistanceKm: totalDistanceKm,
      totalDurationMinutes: totalDurationMinutes,
      shopCount: shopCount,
      byShop: byShop,
      marketCollectionFee: marketFees.collectionFee,
      marketServiceFee: marketFees.serviceFeeTotal,
      marketQualifyingShopCount: marketFees.qualifyingShopCount,
    );
  }

  Future<_ResolvedRouteMetrics> _resolveRouteMetrics({
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

    final memoryHit = _RouteMetricsCacheStore.readMemory(cacheKey);
    if (memoryHit != null) {
      return memoryHit;
    }

    final persisted = await _readRouteCache(cacheKey);
    if (persisted != null) {
      _RouteMetricsCacheStore.writeMemory(cacheKey, persisted);
      return persisted;
    }

    final inFlight = _RouteMetricsCacheStore.readInFlight(cacheKey);
    if (inFlight != null) {
      final shared = await inFlight;
      if (shared != null) {
        return shared;
      }
    }

    final fetchFuture = _fetchRouteMetricsFromServer(
      originLatitude: originLatitude,
      originLongitude: originLongitude,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
    );
    _RouteMetricsCacheStore.trackInFlight(cacheKey, fetchFuture);

    final resolved = await fetchFuture;
    if (resolved != null) {
      _RouteMetricsCacheStore.writeMemory(cacheKey, resolved);
      await _writeRouteCache(cacheKey, resolved);
      return resolved;
    }

    return _buildFallbackRouteMetrics(
      originLatitude: originLatitude,
      originLongitude: originLongitude,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
    );
  }

  Future<_ResolvedRouteMetrics?> _fetchRouteMetricsFromServer({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    try {
      final callable = _functions.httpsCallable('computeRouteMetrics');
      final result = await callable
          .call(<String, Object>{
            'originLatitude': originLatitude,
            'originLongitude': originLongitude,
            'destinationLatitude': destinationLatitude,
            'destinationLongitude': destinationLongitude,
          })
          .timeout(const Duration(seconds: 10));

      final payload = result.data;
      if (payload is! Map) {
        return null;
      }
      final distanceMeters = payload['distanceMeters'];
      final durationSeconds = payload['durationSeconds'];
      if (distanceMeters is! num || durationSeconds is! num) {
        return null;
      }

      return _ResolvedRouteMetrics(
        distanceKm: distanceMeters / 1000.0,
        durationMinutes: durationSeconds.toDouble() / 60.0,
        usedFallback: false,
      );
    } catch (_) {
      return null;
    }
  }

  _ResolvedRouteMetrics _buildFallbackRouteMetrics({
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
    final distanceKm = (distanceMeters / 1000.0) * _haversineRoadFactor;
    final durationMinutes = distanceKm <= 0 ? 0.0 : (distanceKm / 30.0) * 60.0;
    return _ResolvedRouteMetrics(
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      usedFallback: true,
    );
  }

  String _buildRouteCacheKey({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) {
    String roundCoord(double value) => value.toStringAsFixed(4);
    return '${roundCoord(originLatitude)},${roundCoord(originLongitude)}->${roundCoord(destinationLatitude)},${roundCoord(destinationLongitude)}';
  }

  Future<_ResolvedRouteMetrics?> _readRouteCache(String routeKey) async {
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
      if (expiresAtMs is! num ||
          distanceKm is! num ||
          durationMinutes is! num) {
        return null;
      }

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs.toInt(),
      );
      if (DateTime.now().isAfter(expiresAt)) {
        await prefs.remove('$_routeCachePrefix$routeKey');
        return null;
      }

      return _ResolvedRouteMetrics(
        distanceKm: distanceKm.toDouble(),
        durationMinutes: durationMinutes.toDouble(),
        usedFallback: false,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeRouteCache(
    String routeKey,
    _ResolvedRouteMetrics metrics,
  ) async {
    if (metrics.usedFallback) {
      return;
    }
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

  int _shortfallQty(CartLineItem item) {
    final available = item.availableStock;
    if (available == null) {
      return 0;
    }
    final shortfall = item.quantity - available;
    return shortfall > 0 ? shortfall : 0;
  }

  Future<void> _openPaymentSheet({
    required double subtotal,
    required double shippingFee,
    required double grandTotal,
    required CartDiscountSnapshot discounts,
    required String? appliedCouponCode,
    required String? checkoutQuoteId,
  }) async {
    final checkoutContext = CartCheckoutContext(
      couponCode: appliedCouponCode,
      discounts: discounts,
      checkoutQuoteId: checkoutQuoteId,
    );

    await showPaymentCheckoutSheet(
      context: context,
      grandTotal: grandTotal,
      subtitle: 'เลือกวิธีชำระเงินที่ต้องการ',
      onCashOnDelivery: widget.onConfirmCashOnDelivery == null
          ? null
          : () => _confirmCashOnDelivery(
                subtotal: subtotal,
                shippingFee: shippingFee,
                grandTotal: grandTotal,
                discounts: discounts,
                checkoutQuoteId: checkoutQuoteId,
              ),
      onOmisePayment: (channel) async {
        final callback = widget.onSubmitOmisePayment;
        if (callback == null) {
          throw Exception('ระบบชำระเงิน Omise ยังไม่พร้อม');
        }
        final orderIds = await callback(
          channel,
          checkoutContext,
          grandTotal,
        );
        if (orderIds.isEmpty) {
          throw Exception('ไม่สามารถสร้างออเดอร์ได้');
        }
        final openRoadmap = widget.onOpenOrderRoadmap;
        if (openRoadmap != null) {
          await openRoadmap(orderIds);
        }
      },
    );
  }

  Future<void> _confirmCashOnDelivery({
    required double subtotal,
    required double shippingFee,
    required double grandTotal,
    required CartDiscountSnapshot discounts,
    required String? checkoutQuoteId,
  }) async {
    if (_isSubmittingCashOnDelivery) {
      return;
    }

    final items = List<CartLineItem>.from(widget.cartItems);
    if (items.isEmpty) {
      return;
    }

    final totalShortfall = items.fold<int>(
      0,
      (shortfallAcc, item) => shortfallAcc + _shortfallQty(item),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ยืนยันคำสั่งซื้อแบบจ่ายปลายทาง'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('รายการสินค้า'),
                  const SizedBox(height: 8),
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '${item.productName} (${item.shopName})',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('x${item.quantity}'),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'ราคา ฿${_formatMoney(item.unitPrice)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF6B7280)),
                            ),
                          ),
                          if (_shortfallQty(item) > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'จำนวนเกินสต๊อก ${_shortfallQty(item)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFB45309),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const Divider(height: 18),
                  Text('จำนวนเกินสต๊อกรวม: $totalShortfall'),
                  const SizedBox(height: 8),
                  Text('ค่าสินค้า: ฿${_formatMoney(subtotal)}'),
                  Text('ค่าส่ง: ฿${_formatMoney(shippingFee)}'),
                  if (discounts.discountTotal > 0) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'ส่วนลดรวม: -฿${_formatMoney(discounts.discountTotal)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFE55A00),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (discounts.stackNote != null)
                      Text(
                        discounts.stackNote!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB45309),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Text('จัดส่งที่: ${widget.customerLocationLabel}'),
                  Text(
                    'พิกัด ${widget.customerLatitude.toStringAsFixed(6)} • ${widget.customerLongitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ยอดที่ต้องชำระ: ฿${_formatMoney(grandTotal)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ยืนยันสั่งซื้อ'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (mounted) {
      setState(() => _isSubmittingCashOnDelivery = true);
    }

    List<String> createdOrderIds = <String>[];
    String? createError;
    try {
      if (widget.onConfirmCashOnDelivery != null) {
        createdOrderIds = await widget.onConfirmCashOnDelivery!.call(
          CartCheckoutContext(
            couponCode: discounts.appliedCouponCode ?? _appliedCouponCode,
            discounts: discounts,
            checkoutQuoteId: checkoutQuoteId,
          ),
        );
      }
    } catch (e) {
      createError = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isSubmittingCashOnDelivery = false);
      }
    }

    if (!mounted) {
      return;
    }

    if (confirmed == true &&
        createdOrderIds.isNotEmpty &&
        widget.onOpenOrderRoadmap != null) {
      await widget.onOpenOrderRoadmap!(createdOrderIds);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          createdOrderIds.isNotEmpty
              ? 'Order created: ${createdOrderIds.join(', ')}'
              : createError != null
              ? 'Unable to create order: $createError'
              : 'Cash on delivery selected. Order ID pending.',
        ),
      ),
    );
  }
}

class TrueMoneyQrDialogContent extends StatefulWidget {
  const TrueMoneyQrDialogContent({
    super.key,
    required this.grandTotal,
    this.checkoutContext,
    required this.initialAttachedSlip,
    required this.onAttachedSlipChanged,
    required this.onCloseRequested,
    required this.onSubmitPromptPaySlip,
    required this.onSubmissionCompleted,
    required this.onSubmissionSucceeded,
  });

  final double grandTotal;
  final CartCheckoutContext? checkoutContext;
  final PlatformFile? initialAttachedSlip;
  final ValueChanged<PlatformFile?> onAttachedSlipChanged;
  final VoidCallback onCloseRequested;
  final Future<PaymentSlipSubmissionResult> Function(
    PaymentSlipSubmissionRequest request,
  )?
  onSubmitPromptPaySlip;
  final Future<void> Function(List<String> orderIds)? onSubmissionCompleted;
  final VoidCallback onSubmissionSucceeded;

  @override
  State<TrueMoneyQrDialogContent> createState() =>
      _TrueMoneyQrDialogContentState();
}

class _TrueMoneyQrDialogContentState extends State<TrueMoneyQrDialogContent> {
  final GlobalKey _qrBoundaryKey = GlobalKey();

  bool _isSavingQr = false;
  bool _isSubmittingSlip = false;
  PlatformFile? _attachedSlip;

  @override
  void initState() {
    super.initState();
    _attachedSlip = widget.initialAttachedSlip;
  }

  String _formatDialogMoney(num value) {
    final fixed = value.toStringAsFixed(1);
    if (fixed.endsWith('.0')) {
      return fixed.substring(0, fixed.length - 2);
    }
    return fixed;
  }

  Future<void> _saveQrCode() async {
    final messenger = ScaffoldMessenger.of(context);
    final boundary =
        _qrBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;

    if (boundary == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('ยังจับภาพคิวอาร์โค้ดไม่ได้ ลองใหม่อีกครั้ง'),
        ),
      );
      return;
    }

    setState(() => _isSavingQr = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();

      if (pngBytes == null) {
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(
          const SnackBar(content: Text('สร้างไฟล์คิวอาร์โค้ดไม่สำเร็จ')),
        );
        return;
      }

      if (kIsWeb) {
        final downloaded = await downloadBytesInBrowser(
          pngBytes,
          'van2_qr_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              downloaded
                  ? 'ดาวน์โหลดคิวอาร์โค้ดแล้ว'
                  : 'ดาวน์โหลดคิวอาร์โค้ดไม่สำเร็จ ลองใหม่อีกครั้ง',
            ),
          ),
        );
        return;
      }

      final permissionGranted = await _ensureGalleryPermission();
      if (!permissionGranted) {
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(
          const SnackBar(content: Text('ไม่ได้รับสิทธิ์บันทึกรูปลงเครื่อง')),
        );
        return;
      }

      final result = await ImageGallerySaverPlus.saveImage(
        pngBytes,
        quality: 100,
        name: 'van2_qr_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) {
        return;
      }

      final succeeded =
          result != null && result.toString().toLowerCase() != 'false';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            succeeded
                ? 'บันทึกคิวอาร์โค้ดลงเครื่องแล้ว'
                : 'บันทึกคิวอาร์โค้ดไม่สำเร็จ ลองใหม่อีกครั้ง',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('บันทึกคิวอาร์โค้ดไม่สำเร็จ ลองใหม่อีกครั้ง'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingQr = false);
      }
    }
  }

  Future<bool> _ensureGalleryPermission() async {
    if (kIsWeb) {
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final status = await Permission.photosAddOnly.request();
      return status.isGranted || status.isLimited;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted || photosStatus.isLimited) {
        return true;
      }

      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }

    return true;
  }

  Future<void> _pickSlipImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp'],
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final slip = result.files.single;
    setState(() => _attachedSlip = slip);
    widget.onAttachedSlipChanged(slip);
  }

  String? _inferSlipContentType(PlatformFile file) {
    final extension = (file.extension ?? '').toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'jfif':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  String _verificationTitle(String status) {
    switch (status) {
      case 'verified':
        return 'Slip OK ตรวจสอบผ่าน';
      case 'failed':
        return 'Slip OK ตรวจสอบไม่ผ่าน';
      case 'error':
      case 'slip_verification_error':
        return 'Slip OK ส่งกลับข้อผิดพลาด';
      default:
        return 'ผลการตรวจสลิป';
    }
  }

  Future<void> _showVerificationFeedback(
    PaymentSlipSubmissionResult result,
  ) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(_verificationTitle(result.verificationStatus)),
          content: Text(result.message),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('รับทราบ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitSlipForVerification() async {
    final submitCallback = widget.onSubmitPromptPaySlip;
    final navigator = Navigator.of(context);
    final attachedSlip = _attachedSlip;
    final slipBytes = attachedSlip?.bytes;

    if (submitCallback == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ระบบส่งสลิปยังไม่พร้อมใช้งาน')),
      );
      return;
    }

    if (attachedSlip == null || slipBytes == null || slipBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรูปสลิปก่อนส่งตรวจ')),
      );
      return;
    }

    setState(() => _isSubmittingSlip = true);
    try {
      final result = await submitCallback(
        PaymentSlipSubmissionRequest(
          bytes: slipBytes,
          fileName: attachedSlip.name,
          contentType: _inferSlipContentType(attachedSlip),
          sizeBytes: attachedSlip.size,
          grandTotal: widget.grandTotal,
          checkoutContext: widget.checkoutContext,
        ),
      );

      if (!mounted) {
        return;
      }

      await _showVerificationFeedback(result);

      if (!mounted) {
        return;
      }

      if (result.verificationStatus == 'verified') {
        widget.onSubmissionSucceeded();
        navigator.pop();

        if (result.orderIds.isNotEmpty &&
            widget.onSubmissionCompleted != null) {
          await widget.onSubmissionCompleted!(result.orderIds);
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ส่งสลิปไม่สำเร็จ: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmittingSlip = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: FutureBuilder<PaymentCollectionSettings>(
        initialData: PaymentCollectionSettings.defaults,
        future: PaymentCollectionConfigService.instance.loadOnce(),
        builder: (context, snapshot) {
          final settings = PaymentQrService.resolveSettingsForQr(
            snapshot.data ?? PaymentCollectionSettings.defaults,
          );
          final channel = PaymentQrService.pickDefaultChannel(
            amount: widget.grandTotal,
            config: settings,
          );
          final hasPromptPayQr =
              settings.promptPayPhoneNumber?.trim().isNotEmpty == true ||
              settings.promptPayNationalIdOrTaxId?.trim().isNotEmpty == true;
          final canSaveQr = channel.qrPayload != null || hasPromptPayQr;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'ยอดที่ต้องชำระ ฿${_formatDialogMoney(widget.grandTotal)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFE55A00),
                ),
              ),
              const SizedBox(height: 10),
              _TrueMoneyQrCard(
                qrBoundaryKey: _qrBoundaryKey,
                channel: channel,
                amount: widget.grandTotal,
                settings: settings,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canSaveQr && !_isSavingQr ? _saveQrCode : null,
                  icon: _isSavingQr
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(
                    _isSavingQr
                        ? 'กำลังบันทึก...'
                        : 'บันทึกคิวอาร์โค้ดลงเครื่อง',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SlipAttachmentSection(
                slip: _attachedSlip,
                onAttach: _pickSlipImage,
                onClear: _attachedSlip == null
                    ? null
                    : () {
                        setState(() => _attachedSlip = null);
                        widget.onAttachedSlipChanged(null);
                      },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmittingSlip
                      ? null
                      : _submitSlipForVerification,
                  icon: _isSubmittingSlip
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long_rounded),
                  label: Text(
                    _isSubmittingSlip
                        ? 'กำลังส่งสลิป...'
                        : 'ส่งสลิปเพื่อตรวจสอบ',
                  ),
                ),
              ),
              if (channel.qrPayload == null && !hasPromptPayQr) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'ยังไม่มีข้อมูล PromptPay หรือ Merchant QR สำหรับสร้างคิวอาร์โค้ดจริง',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFB45309),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'ให้ใส่ค่าใน Firestore ที่ payment_config/collection แล้วคิวอาร์โค้ดจะผูกยอดให้อัตโนมัติ',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              ],
            ],
          );
        },
      ),
    );
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
    required this.marketCollectionFee,
    required this.marketServiceFee,
    required this.marketQualifyingShopCount,
  });

  final double fee;
  final int missingShopCoordinates;
  final int routeUnavailableShops;
  final double totalDistanceKm;
  final double totalDurationMinutes;
  final int shopCount;
  final List<_ShopShippingFee> byShop;
  final double marketCollectionFee;
  final double marketServiceFee;
  final int marketQualifyingShopCount;

  double get marketTotalFees => marketCollectionFee + marketServiceFee;

  static const zero = _ShippingSummary(
    fee: 0,
    missingShopCoordinates: 0,
    routeUnavailableShops: 0,
    totalDistanceKm: 0,
    totalDurationMinutes: 0,
    shopCount: 0,
    byShop: <_ShopShippingFee>[],
    marketCollectionFee: 0,
    marketServiceFee: 0,
    marketQualifyingShopCount: 0,
  );
}

class _ServerCartTotals {
  const _ServerCartTotals({
    required this.subtotal,
    required this.shippingFee,
    required this.marketCollectionFee,
    required this.marketServiceFee,
    required this.grandTotal,
    required this.discounts,
    required this.trusted,
    this.checkoutQuoteId,
  });

  final double subtotal;
  final double shippingFee;
  final double marketCollectionFee;
  final double marketServiceFee;
  final double grandTotal;
  final CartDiscountSnapshot discounts;
  final bool trusted;
  final String? checkoutQuoteId;

  static const zero = _ServerCartTotals(
    subtotal: 0,
    shippingFee: 0,
    marketCollectionFee: 0,
    marketServiceFee: 0,
    grandTotal: 0,
    discounts: CartDiscountSnapshot.empty,
    trusted: false,
    checkoutQuoteId: null,
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

class _RouteMetricsCacheStore {
  _RouteMetricsCacheStore._();

  static final Map<String, _ResolvedRouteMetrics> _memory = {};
  static final Map<String, Future<_ResolvedRouteMetrics?>> _inFlight = {};

  static _ResolvedRouteMetrics? readMemory(String key) => _memory[key];

  static void writeMemory(String key, _ResolvedRouteMetrics metrics) {
    _memory[key] = metrics;
  }

  static Future<_ResolvedRouteMetrics?>? readInFlight(String key) =>
      _inFlight[key];

  static void trackInFlight(String key, Future<_ResolvedRouteMetrics?> future) {
    _inFlight[key] = future;
    future.whenComplete(() => _inFlight.remove(key));
  }
}

class _ResolvedRouteMetrics {
  const _ResolvedRouteMetrics({
    required this.distanceKm,
    required this.durationMinutes,
    required this.usedFallback,
  });

  final double distanceKm;
  final double durationMinutes;
  final bool usedFallback;
}

class _UntrustedCartTotalWarning extends StatelessWidget {
  const _UntrustedCartTotalWarning({
    required this.isLoading,
    required this.onRetry,
  });

  final bool isLoading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.wifi_tethering_error_rounded,
            color: Color(0xFFB45309),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLoading
                  ? 'กำลังยืนยันยอดจาก server กรุณารอสักครู่'
                  : 'ยอดนี้เป็นประมาณการจากเครื่อง ยังชำระไม่ได้ กรุณาเชื่อมต่ออินเทอร์เน็ตแล้วคำนวณใหม่',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF92400E),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: isLoading ? null : onRetry,
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }
}

class _TrueMoneyQrCard extends StatelessWidget {
  const _TrueMoneyQrCard({
    required this.qrBoundaryKey,
    required this.channel,
    required this.amount,
    required this.settings,
  });

  final GlobalKey qrBoundaryKey;
  final PaymentChannelDefinition channel;
  final double amount;
  final PaymentCollectionSettings settings;

  @override
  Widget build(BuildContext context) {
    final hasQr =
        channel.qrPayload != null && channel.qrPayload!.trim().isNotEmpty;
    final promptPayId = channel.type == PaymentChannelType.promptPayPhone
        ? settings.promptPayPhoneNumber?.trim()
        : channel.type == PaymentChannelType.promptPayNationalId
        ? settings.promptPayNationalIdOrTaxId?.trim()
        : null;
    final hasPromptPayLibraryQr = promptPayId != null && promptPayId.isNotEmpty;
    final amountLabel = amount.toStringAsFixed(
      amount.truncateToDouble() == amount ? 0 : 1,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'คิวอาร์โค้ดตามยอด',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (channel.destinationLabel != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              channel.destinationLabel!,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          RepaintBoundary(
            key: qrBoundaryKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final qrSize = constraints.maxWidth >= 260
                    ? 220.0
                    : (constraints.maxWidth - 32)
                          .clamp(160.0, 220.0)
                          .toDouble();

                return Center(
                  child: hasPromptPayLibraryQr
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: QRCodeGenerate(
                                promptPayId: promptPayId,
                                amount: amount,
                                width: qrSize,
                                height: qrSize,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'สแกนเพื่อชำระ ฿$amountLabel',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'PromptPay ผูกกับเลข $promptPayId',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : hasQr
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: QrImageView(
                                data: channel.qrPayload!,
                                size: qrSize,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'สแกนเพื่อชำระ ฿$amountLabel',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.qr_code_2_rounded,
                                size: 42,
                                color: Color(0xFF9CA3AF),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'ยังไม่สามารถสร้างคิวอาร์โค้ดได้',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SlipAttachmentSection extends StatelessWidget {
  const _SlipAttachmentSection({
    required this.slip,
    required this.onAttach,
    required this.onClear,
  });

  final PlatformFile? slip;
  final VoidCallback onAttach;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final previewBytes = slip?.bytes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'แนบสลิป',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'เลือกรูปสลิปจากเครื่องเพื่อเตรียมส่งตรวจการชำระเงิน',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          if (previewBytes != null) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                previewBytes,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              slip?.name ?? '-',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              '${((slip?.size ?? 0) / 1024).toStringAsFixed(1)} KB',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAttach,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(
                    previewBytes == null ? 'เลือกรูปสลิป' : 'เปลี่ยนรูปสลิป',
                  ),
                ),
              ),
              if (onClear != null) ...<Widget>[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClear,
                  tooltip: 'ลบสลิป',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CartHeaderRow extends StatelessWidget {
  const _CartHeaderRow({
    required this.cartItems,
    required this.customerLatitude,
    required this.customerLongitude,
    required this.customerLocationLabel,
    required this.onPickCustomerLocation,
    required this.onApplySharedLocation,
  });

  final List<CartLineItem> cartItems;
  final double customerLatitude;
  final double customerLongitude;
  final String customerLocationLabel;
  final VoidCallback onPickCustomerLocation;
  final VoidCallback onApplySharedLocation;

  @override
  Widget build(BuildContext context) {
    double? referenceLatitude;
    double? referenceLongitude;
    for (final item in cartItems) {
      final shopLat = item.shopLatitude;
      final shopLng = item.shopLongitude;
      if (shopLat != null && shopLng != null) {
        referenceLatitude = shopLat;
        referenceLongitude = shopLng;
        break;
      }
    }
    referenceLatitude ??= customerLatitude;
    referenceLongitude ??= customerLongitude;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: OnlineRiderCartCompact(
            referenceLatitude: referenceLatitude,
            referenceLongitude: referenceLongitude,
          ),
        ),
        const SizedBox(width: 8),
        _CartLocationButton(
          label: customerLocationLabel,
          latitude: customerLatitude,
          longitude: customerLongitude,
          onPickLocation: onPickCustomerLocation,
          onApplySharedLocation: onApplySharedLocation,
        ),
      ],
    );
  }
}

class _CartLocationButton extends StatelessWidget {
  const _CartLocationButton({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.onPickLocation,
    required this.onApplySharedLocation,
  });

  final String label;
  final double latitude;
  final double longitude;
  final VoidCallback onPickLocation;
  final VoidCallback onApplySharedLocation;

  void _showLocationOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        void runAction(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return Material(
          color: Colors.white,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                Text(
                  'เปลี่ยนพิกัดส่ง',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
                Text(
                  'Lat ${latitude.toStringAsFixed(6)} • Lng ${longitude.toStringAsFixed(6)}',
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.pin_drop_outlined),
                  title: const Text('วางพิกัด'),
                  subtitle: const Text(
                    'วางค่า latitude, longitude ที่คัดลอกมา',
                  ),
                  onTap: () => runAction(onApplySharedLocation),
                ),
                ListTile(
                  leading: const Icon(Icons.share_location_outlined),
                  title: const Text('แชร์'),
                  subtitle: const Text('วางลิงก์พิกัดที่แชร์มาจากแผนที่'),
                  onTap: () => runAction(onApplySharedLocation),
                ),
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('เปลี่ยนด้วยกูเกิลแมพ'),
                  subtitle: const Text('เปิดแผนที่เพื่อเลือกตำแหน่งใหม่'),
                  onTap: () => runAction(onPickLocation),
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final coordText =
        '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

    return OutlinedButton(
      onPressed: () => _showLocationOptions(context),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.edit_location_alt_outlined,
                size: 13,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 3),
              Text(
                'เปลี่ยนพิกัดส่ง',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 108),
            child: Text(
              coordText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF6B7280),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
