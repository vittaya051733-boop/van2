import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/rider_vehicle_profile.dart';
import '../services/locale_service.dart';
import '../utils/catalog_product_image_url.dart';
import 'cached_app_image.dart';
import 'travel_driver_profile_card.dart';

const ShapeBorder _kHistoryCardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(14)),
  side: BorderSide(color: Color(0xFFE5E7EB)),
);

Widget _historyCard({required Widget child}) {
  return Card(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: _kHistoryCardShape,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class OrderHistoryProductLine {
  const OrderHistoryProductLine({
    required this.name,
    this.imageUrl,
    this.quantity = 1,
  });

  final String name;
  final String? imageUrl;
  final int quantity;
}

class OrderHistoryCompactProductCard extends StatelessWidget {
  const OrderHistoryCompactProductCard({
    super.key,
    required this.orderId,
    required this.orderCode,
    required this.shopName,
    required this.shopImageUrl,
    required this.totalAmount,
    required this.products,
    this.isBusy = false,
    this.isClaimReplacement = false,
    this.onReorder,
  });

  final String orderId;
  final String? orderCode;
  final String? shopName;
  final String? shopImageUrl;
  final num totalAmount;
  final List<OrderHistoryProductLine> products;
  final bool isBusy;
  final bool isClaimReplacement;
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    final title = orderCode?.trim().isNotEmpty == true
        ? (L10n.en ? 'Order $orderCode' : 'ออเดอร์ $orderCode')
        : (L10n.en ? 'Order $orderId' : 'ออเดอร์ $orderId');
    final orderIdLabel =
        L10n.en ? 'Order ID: $orderId' : 'รหัสออเดอร์: $orderId';

    return _historyCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _HistoryAvatarImage(imageUrl: shopImageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        orderIdLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isClaimReplacement)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            L10n.substituteNoCharge,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF9A3412),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              L10n.shopLabel(
                shopName?.trim().isNotEmpty == true ? shopName!.trim() : '-',
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isClaimReplacement
                  ? L10n.noChargeSubstitute
                  : L10n.paymentTotalThb(totalAmount.toDouble()),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            if (products.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                L10n.orderProducts,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: products
                    .map((product) => _HistoryProductThumb(product: product))
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isBusy ? null : onReorder,
                icon: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.replay, size: 18),
                label: Text(L10n.orderAgain),
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

class OrderHistoryCompactTravelCard extends StatelessWidget {
  const OrderHistoryCompactTravelCard({
    super.key,
    required this.orderId,
    required this.orderCode,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.totalAmount,
    required this.vehicleLabel,
    required this.scheduleLabel,
    required this.firestore,
    this.driverId,
    this.driverName,
    this.onTravelAgain,
  });

  final String orderId;
  final String? orderCode;
  final String? pickupLabel;
  final String? destinationLabel;
  final num totalAmount;
  final String? vehicleLabel;
  final String? scheduleLabel;
  final FirebaseFirestore firestore;
  final String? driverId;
  final String? driverName;
  final VoidCallback? onTravelAgain;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    final title = orderCode?.trim().isNotEmpty == true
        ? (L10n.en ? 'Order $orderCode' : 'ออเดอร์ $orderCode')
        : (L10n.en ? 'Order $orderId' : 'ออเดอร์ $orderId');
    final orderIdLabel =
        L10n.en ? 'Order ID: $orderId' : 'รหัสออเดอร์: $orderId';

    return _historyCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (driverId?.isNotEmpty == true)
              FutureBuilder<RiderVehicleProfile?>(
                future: _loadRiderProfile(),
                builder: (context, snapshot) {
                  final rider = snapshot.data;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    );
                  }
                  if (rider == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TravelDriverProfileCard(rider: rider),
                  );
                },
              ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              orderIdLabel,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _HistoryDetailLine(
              label: L10n.pickupPointShort,
              value: pickupLabel?.trim().isNotEmpty == true
                  ? pickupLabel!.trim()
                  : '-',
            ),
            _HistoryDetailLine(
              label: L10n.dropoffPointShort,
              value: destinationLabel?.trim().isNotEmpty == true
                  ? destinationLabel!.trim()
                  : '-',
            ),
            _HistoryDetailLine(
              label: L10n.paymentAmountLabel,
              value: 'THB $totalAmount',
            ),
            _HistoryDetailLine(
              label: L10n.vehicleType,
              value: vehicleLabel?.trim().isNotEmpty == true
                  ? vehicleLabel!.trim()
                  : '-',
            ),
            _HistoryDetailLine(
              label: L10n.travelTime,
              value: scheduleLabel?.trim().isNotEmpty == true
                  ? scheduleLabel!.trim()
                  : '-',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onTravelAgain,
                icon: const Icon(Icons.directions_bike_outlined, size: 18),
                label: Text(L10n.travelAgain),
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  Future<RiderVehicleProfile?> _loadRiderProfile() async {
    final trimmedDriverId = driverId?.trim();
    if (trimmedDriverId == null || trimmedDriverId.isEmpty) {
      return null;
    }

    final fallbackName = driverName?.trim().isNotEmpty == true
        ? driverName!.trim()
        : L10n.rider;

    try {
      final doc = await firestore.collection('riders').doc(trimmedDriverId).get();
      if (doc.exists) {
        return RiderVehicleProfile.fromFirestore(trimmedDriverId, doc.data());
      }
    } catch (_) {
      // Fall back to order snapshot fields below.
    }

    return RiderVehicleProfile(
      riderId: trimmedDriverId,
      displayName: fallbackName,
    );
  }
}

class _HistoryDetailLine extends StatelessWidget {
  const _HistoryDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF374151),
        ),
      ),
    );
  }
}

class _HistoryAvatarImage extends StatelessWidget {
  const _HistoryAvatarImage({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final trimmed = imageUrl?.trim();
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFF3F4F6),
      backgroundImage: trimmed != null && trimmed.isNotEmpty
          ? NetworkImage(trimmed)
          : null,
      child: trimmed == null || trimmed.isEmpty
          ? const Icon(Icons.storefront_outlined, color: Color(0xFF9CA3AF))
          : null,
    );
  }
}

class _HistoryProductThumb extends StatelessWidget {
  const _HistoryProductThumb({required this.product});

  final OrderHistoryProductLine product;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.imageUrl?.trim();
    return SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 72,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedAppImage(
                      imageUrl: imageUrl,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      lightweight: true,
                      errorWidget: const ColoredBox(
                        color: Color(0xFFF3F4F6),
                        child: Icon(
                          Icons.fastfood_outlined,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    )
                  : const ColoredBox(
                      color: Color(0xFFF3F4F6),
                      child: Icon(
                        Icons.fastfood_outlined,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            product.quantity > 1
                ? '${product.name} ×${product.quantity}'
                : product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

List<OrderHistoryProductLine> buildHistoryProductLines(
  Map<String, dynamic> data,
) {
  final rawProducts = data['products'];
  if (rawProducts is! List) {
    return const <OrderHistoryProductLine>[];
  }

  final results = <OrderHistoryProductLine>[];
  for (final rawProduct in rawProducts) {
    if (rawProduct is! Map) {
      continue;
    }

    final productId = (rawProduct['productId'] ?? rawProduct['id'] ?? '')
        .toString()
        .trim();
    if (productId == 'travel_passenger_service') {
      continue;
    }

    final name = (rawProduct['name'] ??
            rawProduct['productName'] ??
            rawProduct['title'] ??
            L10n.productFallback)
        .toString()
        .trim();
    final imageUrl = readCatalogProductImageUrl(
      Map<String, dynamic>.from(rawProduct),
    );
    final quantityRaw = rawProduct['quantity'];
    final quantity = quantityRaw is num
        ? quantityRaw.toInt()
        : int.tryParse('${quantityRaw ?? ''}'.trim()) ?? 1;

    results.add(
      OrderHistoryProductLine(
        name: name.isEmpty ? L10n.productFallback : name,
        imageUrl: imageUrl,
        quantity: quantity.clamp(1, 99),
      ),
    );
  }

  return results;
}
