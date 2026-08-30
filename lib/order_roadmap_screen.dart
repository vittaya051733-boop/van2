import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_contact_screen.dart';
import 'call_screen.dart';
import 'l10n/l10n.dart';
import 'order_claim_request_screen.dart';
import 'chat_room_screen.dart';
import 'models/rider_vehicle_profile.dart';
import 'models/user_profile.dart';
import 'services/admin_support_config.dart';
import 'services/app_image_prefetch.dart';
import 'services/chat_warmup.dart';
import 'services/notification_service.dart';
import 'services/review_service.dart';
import 'utils/localized_product_text.dart';
import 'utils/catalog_product_image_url.dart';
import 'widgets/cached_app_image.dart';
import 'widgets/no_rider_customer_actions_banner.dart';
import 'widgets/order_refund_dialog.dart';
import 'services/customer_order_actions_service.dart';
import 'services/order_reorder_service.dart';
import 'travel_tracking_screen.dart';
import 'widgets/order_history_compact_card.dart';
import 'widgets/travel_driver_profile_card.dart';

const double _kRoadmapProductCarouselHeight = 128;

const ShapeBorder _kRoadmapCardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(14)),
  side: BorderSide(color: Color(0xFFE5E7EB)),
);

/// In-memory cache so roadmap cards skip repeat Firestore shop-image lookups.
final Map<String, String?> _roadmapShopImageByOrderId = <String, String?>{};
final Set<String> _roadmapPrefetchBatchKeys = <String>{};

Widget _roadmapOrderCard({required Widget child}) {
  return Card(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: _kRoadmapCardShape,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

List<String> _roadmapPrefetchUrlsFromOrder(Map<String, dynamic> data) {
  final urls = <String>[];
  void add(dynamic value) {
    final trimmed = value?.toString().trim();
    if (trimmed == null || trimmed.isEmpty || urls.contains(trimmed)) {
      return;
    }
    urls.add(trimmed);
  }

  for (final field in <String>['shopImageUrl', 'imageUrl', 'photoUrl']) {
    add(data[field]);
  }

  final shopSnapshot = data['shopSnapshot'];
  if (shopSnapshot is Map) {
    for (final field in <String>['shopImageUrl', 'imageUrl', 'photoUrl']) {
      add(shopSnapshot[field]);
    }
  }

  final rawProducts = data['products'];
  if (rawProducts is List) {
    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }
      for (final field in <String>[
        'imageUrl',
        'productImage',
        'photoUrl',
        'shopImageUrl',
        'shop_image_url',
        'storeImageUrl',
      ]) {
        add(rawProduct[field]);
      }
      final productShopSnapshot = rawProduct['shopSnapshot'];
      if (productShopSnapshot is Map) {
        for (final field in <String>['shopImageUrl', 'imageUrl', 'photoUrl']) {
          add(productShopSnapshot[field]);
        }
      }
    }
  }

  add(data['deliveryProofImageUrl']);
  return urls;
}

void _scheduleRoadmapOrdersPrefetch({
  required List<String> orderIds,
  required Iterable<Map<String, dynamic>> orders,
}) {
  if (orderIds.isEmpty) {
    return;
  }
  final key = orderIds.join(',');
  if (!_roadmapPrefetchBatchKeys.add(key)) {
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final urls = <String>[];
    for (final data in orders) {
      urls.addAll(_roadmapPrefetchUrlsFromOrder(data));
    }
    if (urls.isEmpty) {
      return;
    }
    AppImagePrefetch.scheduleImageUrlsPrefetch(
      urls,
      dedupeKey: 'roadmap:$key',
      delayMs: 0,
      limit: urls.length.clamp(1, 96),
    );
  });
}

const Set<String> _kCancelledRoadmapOrderStatuses = <String>{
  'cancelled',
  'canceled',
  'refund',
  'refunded',
};

bool _isDeliveredRoadmapOrder(Map<String, dynamic> data) {
  final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
  return status == 'delivered';
}

bool _isCancelledRoadmapOrder(Map<String, dynamic> data) {
  final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
  return _kCancelledRoadmapOrderStatuses.contains(status);
}

bool _isHistoryRoadmapOrder(Map<String, dynamic> data) {
  return _isDeliveredRoadmapOrder(data) || _isCancelledRoadmapOrder(data);
}

bool _isActiveRoadmapOrder(Map<String, dynamic> data) {
  return !_isHistoryRoadmapOrder(data);
}

String? _currentCustomerUid() {
  try {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    return FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {
    return null;
  }
}

int _historyOrderSortMs(Map<String, dynamic> data) {
  for (final field in <String>[
    'deliveredAt',
    'cancelledAt',
    'updatedAt',
    'createdAt',
  ]) {
    final value = data[field];
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
  }
  return 0;
}

const List<String> _kOrderShopLookupFields = <String>[
  'ownerUid',
  'ownerId',
  'owner_id',
  'shopId',
  'shop_id',
  'shopOwnerId',
  'shopOwnerUid',
  'merchantId',
  'merchantUid',
  'owner',
  'uid',
];

class OrderRoadmapScreen extends StatelessWidget {
  OrderRoadmapScreen({
    super.key,
    this.orderIds = const <String>[],
    this.showHistory = false,
    this.onReorderProducts,
    this.onTravelAgain,
    FirebaseFirestore? firestore,
    CustomerOrderActionsService? orderActions,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        orderActions = orderActions ?? CustomerOrderActionsService.production();

  final List<String> orderIds;
  final bool showHistory;
  final Future<void> Function(Map<String, dynamic> orderData)? onReorderProducts;
  final VoidCallback? onTravelAgain;
  final FirebaseFirestore firestore;
  final CustomerOrderActionsService orderActions;

  void _openHistory(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OrderRoadmapScreen(
          showHistory: true,
          onReorderProducts: onReorderProducts,
          onTravelAgain: onTravelAgain,
          firestore: firestore,
          orderActions: orderActions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _currentCustomerUid();

    if (showHistory) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: Text(L10n.orderHistoryTitle),
        ),
        body: _CustomerHistoryRoadmapList(
          uid: uid,
          firestore: firestore,
          onReorderProducts: onReorderProducts,
          onTravelAgain: onTravelAgain,
          orderActions: orderActions,
        ),
      );
    }

    final uniqueOrderIds = orderIds.toSet().toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(L10n.deliveryRoadmapTitle),
        actions: [
          TextButton.icon(
            onPressed: () => _openHistory(context),
            icon: const Icon(Icons.history, size: 20),
            label: Text(L10n.history),
          ),
        ],
      ),
      body: _CustomerActiveRoadmapList(
        preferredOrderIds: uniqueOrderIds,
        uid: uid,
        firestore: firestore,
        onOpenHistory: () => _openHistory(context),
        orderActions: orderActions,
      ),
    );
  }
}

class _RoadmapList extends StatelessWidget {
  const _RoadmapList({
    required this.orderIds,
    required this.firestore,
    required this.orderActions,
  });

  final List<String> orderIds;
  final FirebaseFirestore firestore;
  final CustomerOrderActionsService orderActions;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orderIds.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final orderId = orderIds[index];
        return _OrderRoadmapCard(
          orderId: orderId,
          firestore: firestore,
          orderActions: orderActions,
        );
      },
    );
  }
}

Stream<QuerySnapshot<Map<String, dynamic>>> _activeRoadmapOrdersStream({
  required FirebaseFirestore firestore,
  required List<String> preferredOrderIds,
  required String? uid,
}) {
  if (uid != null && uid.isNotEmpty) {
    return firestore
        .collection('orders')
        .where('customerId', isEqualTo: uid)
        .snapshots();
  }
  if (preferredOrderIds.isNotEmpty) {
    final ids = preferredOrderIds.take(30).toList(growable: false);
    return firestore
        .collection('orders')
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots();
  }
  return firestore.collection('orders').limit(0).snapshots();
}

int _preferredOrderRank(String orderId, List<String> preferredOrderIds) {
  final index = preferredOrderIds.indexOf(orderId);
  return index >= 0 ? index : preferredOrderIds.length + 1;
}

class _CustomerActiveRoadmapList extends StatelessWidget {
  const _CustomerActiveRoadmapList({
    required this.preferredOrderIds,
    required this.uid,
    required this.firestore,
    required this.onOpenHistory,
    required this.orderActions,
  });

  final List<String> preferredOrderIds;
  final String? uid;
  final FirebaseFirestore firestore;
  final VoidCallback onOpenHistory;
  final CustomerOrderActionsService orderActions;

  @override
  Widget build(BuildContext context) {
    if ((uid == null || uid!.isEmpty) && preferredOrderIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(L10n.signInRequiredForOrders),
        ),
      );
    }

    final stream = _activeRoadmapOrdersStream(
      firestore: firestore,
      preferredOrderIds: preferredOrderIds,
      uid: uid,
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(L10n.loadRoadmapFailed(snapshot.error!)),
            ),
          );
        }

        final docs =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .toList(growable: false);

        final activeDocs = docs
            .where((doc) => _isActiveRoadmapOrder(doc.data()))
            .toList(growable: false);

        activeDocs.sort((a, b) {
          final aPreferred = _preferredOrderRank(a.id, preferredOrderIds);
          final bPreferred = _preferredOrderRank(b.id, preferredOrderIds);
          if (aPreferred != bPreferred) {
            return aPreferred.compareTo(bPreferred);
          }

          final aTs = a.data()['createdAt'];
          final bTs = b.data()['createdAt'];
          final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
          final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
          return bMs.compareTo(aMs);
        });

        final orderIds = activeDocs.map((doc) => doc.id).toList(growable: false);

        _scheduleRoadmapOrdersPrefetch(
          orderIds: orderIds,
          orders: docs.map((doc) => doc.data()),
        );

        if (orderIds.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.noActiveOrders,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    L10n.completedOrdersInHistory,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onOpenHistory,
                    icon: const Icon(Icons.history),
                    label: Text(L10n.viewOrderHistory),
                  ),
                ],
              ),
            ),
          );
        }

        return _RoadmapList(
          orderIds: orderIds,
          firestore: firestore,
          orderActions: orderActions,
        );
      },
    );
  }
}

String? _readHistoryShopImageUrl(Map<String, dynamic> data) {
  for (final field in <String>['shopImageUrl', 'imageUrl', 'photoUrl']) {
    final trimmed = data[field]?.toString().trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  final shopSnapshot = data['shopSnapshot'];
  if (shopSnapshot is Map) {
    for (final field in <String>['shopImageUrl', 'imageUrl', 'photoUrl']) {
      final trimmed = shopSnapshot[field]?.toString().trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
  }

  final rawProducts = data['products'];
  if (rawProducts is List) {
    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }
      for (final field in <String>['shopImageUrl', 'imageUrl', 'photoUrl']) {
        final trimmed = rawProduct[field]?.toString().trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
  }

  return null;
}

class _CustomerHistoryRoadmapList extends StatefulWidget {
  const _CustomerHistoryRoadmapList({
    required this.uid,
    required this.firestore,
    this.onReorderProducts,
    this.onTravelAgain,
    this.orderActions,
  });

  final String? uid;
  final FirebaseFirestore firestore;
  final Future<void> Function(Map<String, dynamic> orderData)? onReorderProducts;
  final VoidCallback? onTravelAgain;
  final CustomerOrderActionsService? orderActions;

  @override
  State<_CustomerHistoryRoadmapList> createState() =>
      _CustomerHistoryRoadmapListState();
}

class _CustomerHistoryRoadmapListState
    extends State<_CustomerHistoryRoadmapList> {
  String? _reorderingOrderId;

  Future<void> _handleReorder(
    Map<String, dynamic> orderData,
    String orderId,
  ) async {
    final handler = widget.onReorderProducts;
    if (handler == null) {
      return;
    }

    setState(() => _reorderingOrderId = orderId);
    try {
      await handler(orderData);
    } finally {
      if (mounted) {
        setState(() => _reorderingOrderId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final firestore = widget.firestore;

    if (uid == null || uid.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(L10n.signInRequiredForHistory),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('orders')
          .where('customerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(L10n.loadHistoryFailed(snapshot.error!)),
            ),
          );
        }

        final docs =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .toList(growable: false);
        final historyDocs = docs
            .where((doc) => _isHistoryRoadmapOrder(doc.data()))
            .toList(growable: false)
          ..sort(
            (a, b) => _historyOrderSortMs(
              b.data(),
            ).compareTo(_historyOrderSortMs(a.data())),
          );

        final productEntries = <({String id, Map<String, dynamic> data})>[];
        final travelEntries = <({String id, Map<String, dynamic> data})>[];
        for (final doc in historyDocs) {
          final data = doc.data();
          final entry = (id: doc.id, data: data);
          if (isTravelPassengerOrderData(data)) {
            travelEntries.add(entry);
          } else {
            productEntries.add(entry);
          }
        }

        _scheduleRoadmapOrdersPrefetch(
          orderIds: historyDocs.map((doc) => doc.id).toList(growable: false),
          orders: docs.map((doc) => doc.data()),
        );

        if (historyDocs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(L10n.noCompletedOrderHistory),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            if (productEntries.isNotEmpty) ...<Widget>[
              _HistorySectionHeader(title: L10n.historyProductsSection),
              const SizedBox(height: 8),
              for (final entry in productEntries) ...<Widget>[
                OrderHistoryCompactProductCard(
                  orderId: entry.id,
                  orderCode: (entry.data['orderCode'] as String?)?.trim(),
                  shopName: (entry.data['shopName'] as String?)?.trim(),
                  shopImageUrl: _readHistoryShopImageUrl(entry.data),
                  totalAmount: (entry.data['grandTotal'] as num?) ??
                      (entry.data['totalPrice'] as num?) ??
                      0,
                  products: buildHistoryProductLines(entry.data),
                  isBusy: _reorderingOrderId == entry.id,
                  isClaimReplacement:
                      (entry.data['orderType'] as String?)?.trim() ==
                          'claim_replacement',
                  onReorder: widget.onReorderProducts == null
                      ? null
                      : () => _handleReorder(entry.data, entry.id),
                ),
                const SizedBox(height: 10),
              ],
            ],
            if (travelEntries.isNotEmpty) ...<Widget>[
              if (productEntries.isNotEmpty) const SizedBox(height: 6),
              _HistorySectionHeader(title: L10n.historyTravelSection),
              const SizedBox(height: 8),
              for (final entry in travelEntries) ...<Widget>[
                OrderHistoryCompactTravelCard(
                  orderId: entry.id,
                  orderCode: (entry.data['orderCode'] as String?)?.trim(),
                  pickupLabel: _readTravelPickupLabel(entry.data),
                  destinationLabel: _readTravelDestinationLabel(entry.data),
                  totalAmount: (entry.data['grandTotal'] as num?) ??
                      (entry.data['totalPrice'] as num?) ??
                      0,
                  vehicleLabel: _readTravelVehicleLabel(entry.data),
                  scheduleLabel: _readTravelScheduleLabel(entry.data),
                  firestore: firestore,
                  driverId: (entry.data['driverId'] as String?)?.trim(),
                  driverName: (entry.data['driverName'] as String?)?.trim(),
                  onTravelAgain: widget.onTravelAgain,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _HistorySectionHeader extends StatelessWidget {
  const _HistorySectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: Color(0xFF111827),
        ),
      ),
    );
  }
}

class _OrderRoadmapCard extends StatelessWidget {
  const _OrderRoadmapCard({
    required this.orderId,
    required this.firestore,
    required this.orderActions,
  });

  final String orderId;
  final FirebaseFirestore firestore;
  final CustomerOrderActionsService orderActions;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('orders').doc(orderId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _roadmapOrderCard(
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return _roadmapOrderCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(L10n.loadOrderFailed(orderId, snapshot.error!)),
            ),
          );
        }

        final data = snapshot.data?.data();
        if (data == null) {
          return _roadmapOrderCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(L10n.orderNotFound(orderId)),
            ),
          );
        }

        _scheduleRoadmapOrdersPrefetch(
          orderIds: <String>[orderId],
          orders: <Map<String, dynamic>>[data],
        );

        final roadmap = _buildRoadmapState(data);
        final isTravelOrder = _isTravelPassengerOrder(data);
        final isClaimReplacement = _isClaimReplacementOrder(data);
        final shopName = (data['shopName'] as String?)?.trim();
        final orderCode = (data['orderCode'] as String?)?.trim();
        final total =
            (data['grandTotal'] as num?) ?? (data['totalPrice'] as num?) ?? 0;
        final driverId = (data['driverId'] as String?)?.trim();
        final shopImageUrl = _readShopImageUrl(data);
        final productEntries = _readProductEntries(data);
        final deliveryProofImageUrl = (data['deliveryProofImageUrl'] as String?)
            ?.trim();
        final deliveryProofMeta = _buildDeliveryProofMeta(data);
        final pickupLabel = isTravelOrder ? _readTravelPickupLabel(data) : null;
        final destinationLabel = isTravelOrder
            ? _readTravelDestinationLabel(data)
            : null;
        final travelVehicleLabel = isTravelOrder
            ? _readTravelVehicleLabel(data)
            : null;
        final travelScheduleLabel = isTravelOrder
            ? _readTravelScheduleLabel(data)
            : null;

        return _roadmapOrderCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isTravelOrder &&
                    driverId != null &&
                    driverId.isNotEmpty) ...[
                  FutureBuilder<RiderVehicleProfile?>(
                    future: _loadRiderVehicleProfile(data),
                    builder: (context, riderSnapshot) {
                      final riderProfile = riderSnapshot.data;
                      if (riderSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(minHeight: 2),
                        );
                      }
                      if (riderProfile == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TravelDriverProfileCard(rider: riderProfile),
                      );
                    },
                  ),
                ],
                FutureBuilder<String?>(
                  future: _resolveShopImageUrl(data),
                  builder: (context, shopImageSnapshot) {
                    final resolvedShopImageUrl =
                        shopImageSnapshot.data ?? shopImageUrl;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (resolvedShopImageUrl != null) ...[
                          _ShopRoadmapImage(imageUrl: resolvedShopImageUrl),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                orderCode?.isNotEmpty == true
                                    ? 'Order $orderCode'
                                    : 'Order $orderId',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                'Order ID: $orderId',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  isTravelOrder
                      ? L10n.pickupPointLabel(pickupLabel ?? '')
                      : L10n.shopLabel(shopName ?? ''),
                ),
                if (isTravelOrder)
                  Text(
                    L10n.dropoffLabel(destinationLabel ?? ''),
                  ),
                Text(
                  isClaimReplacement
                      ? L10n.substituteNoCharge
                      : L10n.paymentTotalThb(total.toDouble()),
                ),
                if (isTravelOrder && travelVehicleLabel != null)
                  Text(L10n.vehicleTypeLabel(travelVehicleLabel!)),
                if (isTravelOrder && travelScheduleLabel != null)
                  Text(L10n.travelScheduleLabel(travelScheduleLabel!)),
                if (productEntries.isNotEmpty && !isTravelOrder) ...[
                  const SizedBox(height: 10),
                  Text(
                    isTravelOrder
                        ? L10n.travelDetails
                        : L10n.orderProducts,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: _kRoadmapProductCarouselHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: productEntries.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final product = productEntries[index];
                        return _RoadmapProductImageCard(
                          name: product.name,
                          quantity: product.quantity,
                          imageUrl: product.imageUrl,
                        );
                      },
                    ),
                  ),
                ],
                if (deliveryProofImageUrl != null &&
                    deliveryProofImageUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    L10n.riderProofPhoto,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedAppImage(
                      imageUrl: deliveryProofImageUrl,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                      errorWidget: Container(
                        height: 120,
                        color: const Color(0xFFF3F4F6),
                        alignment: Alignment.center,
                        child: Text(L10n.proofPhotoLoadFailed),
                      ),
                    ),
                  ),
                  if (deliveryProofMeta != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      deliveryProofMeta,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                FutureBuilder<_RiderContactState>(
                  future: _loadRiderContactState(data),
                  builder: (context, contactSnapshot) {
                    final contact = contactSnapshot.data;
                    final hasRider = driverId != null && driverId.isNotEmpty;
                    final canChat = contact?.profile != null;
                    final canCall =
                        hasRider || (contact?.phone?.isNotEmpty ?? false);

                    return Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: !hasRider || !canChat
                                ? null
                                : () async {
                                    final riderProfile = contact?.profile;
                                    if (riderProfile == null) return;
                                    ChatWarmup.prefetchRoom(
                                      myUid: FirebaseAuth.instance.currentUser!.uid,
                                      peer: riderProfile,
                                    );
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ChatRoomScreen(
                                          friendProfile: riderProfile,
                                          orderId: orderId,
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: Text(L10n.chatRider),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: !hasRider || !canCall
                                ? null
                                : () async {
                                    await _startOrderCall(
                                      context,
                                      orderData: data,
                                      contact: contact,
                                    );
                                  },
                            icon: const Icon(Icons.phone_in_talk_outlined),
                            label: Text(
                              canCall ? L10n.callRider : L10n.callRiderUnavailable,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                if (_canRequestProductClaim(data))
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => OrderClaimRequestScreen(
                              orderId: orderId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: Text(L10n.claimProduct),
                    ),
                  ),
                if (_canRequestProductClaim(data)) const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AdminContactScreen(
                            config: kVan2AdminSupportConfig,
                            orderId: orderId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.support_agent_outlined),
                    label: Text(L10n.contactAdminAboutOrder),
                  ),
                ),
                if (isActiveTravelTrackingOrder(data)) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        showTravelTrackingScreen(
                          context: context,
                          orderId: orderId,
                        );
                      },
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: Text(L10n.mapLabel),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                NoRiderCustomerActionsBanner(
                  orderId: orderId,
                  data: data,
                  firestore: firestore,
                  orderActions: orderActions,
                ),
                if (!isTravelOrder)
                  _AwaitingShopDecisionBanner(
                    orderId: orderId,
                    data: data,
                    firestore: firestore,
                    orderActions: orderActions,
                  ),
                _TimelineStepTile(
                  label: L10n.riderAcceptedOrder,
                  status: roadmap.riderAccepted,
                  leadingIcon: Icons.assignment_turned_in_outlined,
                ),
                _TimelineStepTile(
                  label: isTravelOrder
                      ? L10n.riderAtPickup
                      : L10n.shopAcceptedOrder,
                  status: isTravelOrder
                      ? roadmap.riderScannedPickup
                      : roadmap.shopPreparing,
                  leadingIcon: isTravelOrder
                      ? Icons.location_on_outlined
                      : Icons.storefront_outlined,
                ),
                _TimelineStepTile(
                  label: isTravelOrder
                      ? L10n.waitingPassengerBoard
                      : L10n.riderScannedPickup,
                  status: isTravelOrder
                      ? roadmap.shopPreparing
                      : roadmap.riderScannedPickup,
                  leadingIcon: isTravelOrder
                      ? Icons.airline_seat_recline_normal_outlined
                      : Icons.qr_code_scanner_outlined,
                ),
                _TimelineStepTile(
                  label: isTravelOrder
                      ? L10n.travelingToDropoff
                      : L10n.riderDelivering,
                  status: roadmap.delivering,
                  leadingIcon: isTravelOrder
                      ? Icons.directions_car_outlined
                      : Icons.delivery_dining_outlined,
                ),
                _TimelineStepTile(
                  label: isTravelOrder
                      ? L10n.arrivedAtDestination
                      : L10n.deliveredToCustomer,
                  status: roadmap.delivered,
                  leadingIcon: isTravelOrder
                      ? Icons.flag_outlined
                      : Icons.task_alt_outlined,
                  isLast: true,
                ),
                if (!isTravelOrder && roadmap.delivered)
                  _OrderReviewPanel(
                    orderId: orderId,
                    data: data,
                    products: productEntries,
                    firestore: firestore,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _buildDeliveryProofMeta(Map<String, dynamic> data) {
    final capturedByName = _readTrimmedString(
      data['deliveryProofCapturedByName'],
      data['driverName'],
      data['riderName'],
    );
    final capturedAt = _formatProofCapturedAt(data['deliveryProofCapturedAt']);

    if (capturedByName != null && capturedAt != null) {
      return L10n.confirmedByAt(capturedByName, capturedAt);
    }
    if (capturedByName != null) {
      return L10n.confirmedBy(capturedByName);
    }
    if (capturedAt != null) {
      return L10n.capturedAt(capturedAt);
    }
    return null;
  }

  String? _readShopImageUrl(Map<String, dynamic> data) {
    final direct = _readTrimmedString(
      data['shopImageUrl'],
      data['imageUrl'],
      data['photoUrl'],
    );
    if (direct != null) {
      return direct;
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      return _readTrimmedString(
        shopSnapshot['shopImageUrl'],
        shopSnapshot['imageUrl'],
        shopSnapshot['photoUrl'],
      );
    }

    return null;
  }

  Future<String?> _resolveShopImageUrl(Map<String, dynamic> data) async {
    if (_roadmapShopImageByOrderId.containsKey(orderId)) {
      return _roadmapShopImageByOrderId[orderId];
    }

    final direct = _readShopImageUrl(data);
    if (direct != null) {
      _rememberRoadmapShopImageUrl(direct);
      return direct;
    }

    final embedded = _readShopImageUrlFromEmbeddedProducts(data);
    if (embedded != null) {
      _rememberRoadmapShopImageUrl(embedded);
      return embedded;
    }

    final loaded = await _loadShopImageUrl(data);
    _rememberRoadmapShopImageUrl(loaded);
    return loaded;
  }

  void _rememberRoadmapShopImageUrl(String? url) {
    _roadmapShopImageByOrderId[orderId] = url;
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    unawaited(
      AppImagePrefetch.prefetchUrls(
        <String>[trimmed],
        awaitPriority: false,
        parallel: 1,
      ),
    );
  }

  Future<String?> _loadShopImageUrl(Map<String, dynamic> data) async {
    final direct = _readShopImageUrl(data);
    if (direct != null) {
      return direct;
    }

    final embeddedProductImage = _readShopImageUrlFromEmbeddedProducts(data);
    if (embeddedProductImage != null) {
      return embeddedProductImage;
    }

    final shopId = _readShopLookupId(data);
    final productImage = await _loadShopImageFromProductsCollection(
      data: data,
      shopId: shopId,
    );
    if (productImage != null) {
      return productImage;
    }

    return null;
  }

  String? _readShopImageUrlFromEmbeddedProducts(Map<String, dynamic> data) {
    final rawProducts = data['products'];
    if (rawProducts is! List) {
      return null;
    }

    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }

      final productMap = Map<String, dynamic>.from(rawProduct);
      final productDirect = _readTrimmedString(
        productMap['shopImageUrl'],
        productMap['shop_image_url'],
        productMap['storeImageUrl'],
      );
      if (productDirect != null) {
        return productDirect;
      }

      final shopSnapshot = productMap['shopSnapshot'];
      if (shopSnapshot is Map) {
        final snapshotImage = _readTrimmedString(
          shopSnapshot['shopImageUrl'],
          shopSnapshot['imageUrl'],
          shopSnapshot['photoUrl'],
        );
        if (snapshotImage != null) {
          return snapshotImage;
        }
      }
    }

    return null;
  }

  Future<String?> _loadShopImageFromProductsCollection({
    required Map<String, dynamic> data,
    required String shopId,
  }) async {
    final productCollection = firestore.collection('products');

    for (final productId in _readProductIds(data)) {
      try {
        final productDoc = await productCollection.doc(productId).get();
        if (!productDoc.exists) {
          continue;
        }

        final imageUrl = _readShopImageFromProductDocument(productDoc.data());
        if (imageUrl != null) {
          return imageUrl;
        }
      } catch (_) {
        // Skip optional product enrichment failures.
      }
    }

    if (shopId.isEmpty) {
      return null;
    }

    for (final field in _shopLookupFields) {
      try {
        final query = await productCollection
            .where(field, isEqualTo: shopId)
            .limit(1)
            .get();
        for (final doc in query.docs) {
          final imageUrl = _readShopImageFromProductDocument(doc.data());
          if (imageUrl != null) {
            return imageUrl;
          }
        }
      } catch (_) {
        // Ignore optional lookup failures caused by permissions or missing indexes.
      }
    }

    return null;
  }

  String? _readShopImageFromProductDocument(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final direct = _readTrimmedString(
      data['shopImageUrl'],
      data['imageUrl'],
      data['photoUrl'],
    );
    if (direct != null) {
      return direct;
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      return _readTrimmedString(
        shopSnapshot['shopImageUrl'],
        shopSnapshot['imageUrl'],
        shopSnapshot['photoUrl'],
      );
    }

    return null;
  }

  String _readShopLookupId(Map<String, dynamic> data) {
    final direct = _readFirstNonEmptyValue(data, _shopLookupFields);
    if (direct != null) {
      return direct;
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      final fromSnapshot = _readFirstNonEmptyValue(
        Map<String, dynamic>.from(shopSnapshot),
        _shopLookupFields,
      );
      if (fromSnapshot != null) {
        return fromSnapshot;
      }
    }

    final rawProducts = data['products'];
    if (rawProducts is List) {
      for (final rawProduct in rawProducts) {
        if (rawProduct is! Map) {
          continue;
        }

        final productMap = Map<String, dynamic>.from(rawProduct);
        final productShopId = _readFirstNonEmptyValue(
          productMap,
          _shopLookupFields,
        );
        if (productShopId != null) {
          return productShopId;
        }
      }
    }

    return '';
  }

  List<String> _readProductIds(Map<String, dynamic> data) {
    final rawProducts = data['products'];
    if (rawProducts is! List) {
      return const <String>[];
    }

    final productIds = <String>{};
    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }

      final productMap = Map<String, dynamic>.from(rawProduct);
      final productId = _readFirstNonEmptyValue(productMap, const <String>[
        'productId',
        'product_id',
        'id',
        'docId',
        'documentId',
      ]);
      if (productId != null) {
        productIds.add(productId);
      }
    }

    return productIds.toList(growable: false);
  }

  String? _readFirstNonEmptyValue(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static const List<String> _shopLookupFields = _kOrderShopLookupFields;

  List<_RoadmapProductEntry> _readProductEntries(Map<String, dynamic> data) {
    final rawProducts = data['products'];
    if (rawProducts is! List) {
      return const <_RoadmapProductEntry>[];
    }

    final results = <_RoadmapProductEntry>[];
    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }

      final imageUrl = _readTrimmedString(
            rawProduct['imageUrl'],
            rawProduct['productImage'],
            rawProduct['photoUrl'],
          ) ??
          readCatalogProductImageUrl(Map<String, dynamic>.from(rawProduct));
      final productId = _readFirstNonEmptyValue(
        Map<String, dynamic>.from(rawProduct),
        const <String>['productId', 'product_id', 'id', 'docId', 'documentId'],
      );
      final name = _readTrimmedString(
        rawProduct['name'],
        rawProduct['productName'],
        rawProduct['title'],
      );
      final quantity = _readQuantity(rawProduct['quantity']);
      if (imageUrl == null && name == null) {
        continue;
      }

      results.add(
        _RoadmapProductEntry(
          productId: productId,
          name: LocalizedProductText.name(
            Map<String, dynamic>.from(rawProduct),
            productId: productId,
          ),
          imageUrl: imageUrl,
          quantity: quantity,
        ),
      );
    }

    return results;
  }

  int _readQuantity(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  String? _readTrimmedString(dynamic first, dynamic second, dynamic third) {
    final values = <dynamic>[first, second, third];
    for (final value in values) {
      final trimmed = value?.toString().trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  String? _formatProofCapturedAt(dynamic value) {
    DateTime? dateTime;
    if (value is Timestamp) {
      dateTime = value.toDate();
    } else if (value is DateTime) {
      dateTime = value;
    } else if (value is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(value);
    }

    if (dateTime == null) {
      return null;
    }

    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Future<RiderVehicleProfile?> _loadRiderVehicleProfile(
    Map<String, dynamic> data,
  ) async {
    final driverId = (data['driverId'] as String?)?.trim();
    if (driverId == null || driverId.isEmpty) {
      return null;
    }

    final fallbackName =
        ((data['driverName'] as String?)?.trim().isNotEmpty ?? false)
        ? (data['driverName'] as String).trim()
        : L10n.rider;

    try {
      final doc = await firestore.collection('riders').doc(driverId).get();
      if (doc.exists) {
        return RiderVehicleProfile.fromFirestore(driverId, doc.data());
      }
    } catch (_) {
      // Fall back to order snapshot fields below.
    }

    return RiderVehicleProfile(
      riderId: driverId,
      displayName: fallbackName,
      phoneNumber: (data['driverPhone'] as String?)?.trim(),
    );
  }

  Future<_RiderContactState> _loadRiderContactState(
    Map<String, dynamic> data,
  ) async {
    final driverId = (data['driverId'] as String?)?.trim();
    final fallbackName =
        ((data['driverName'] as String?)?.trim().isNotEmpty ?? false)
        ? (data['driverName'] as String).trim()
        : L10n.rider;
    final fallbackPhone = (data['driverPhone'] as String?)?.trim();

    if (driverId == null || driverId.isEmpty) {
      return _RiderContactState(profile: null, phone: fallbackPhone);
    }

    UserProfile? profile;
    Map<String, dynamic>? riderData;
    try {
      final doc = await firestore.collection('riders').doc(driverId).get();
      if (doc.exists) {
        riderData = doc.data();
        profile = UserProfile.fromMap(driverId, riderData);
      }
    } catch (_) {
      // Keep fallback profile when users lookup fails.
    }

    profile ??= UserProfile(
      uid: driverId,
      displayName: fallbackName,
      phoneNumber: fallbackPhone,
    );

    final phone = _pickFirstNonEmpty(<String?>[
      fallbackPhone,
      profile.phoneNumber,
      riderData?['phoneNumber'] as String?,
      riderData?['phone'] as String?,
      riderData?['contactPhone'] as String?,
      riderData?['mobile'] as String?,
    ]);

    return _RiderContactState(profile: profile, phone: phone);
  }

  String? _pickFirstNonEmpty(List<String?> candidates) {
    for (final item in candidates) {
      final text = item?.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  Future<void> _callPhone(
    String phone,
    ScaffoldMessengerState? messenger,
  ) async {
    final uri = Uri(scheme: 'tel', path: phone);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger?.showSnackBar(
        SnackBar(content: Text(L10n.cannotMakeCall)),
      );
    }
  }

  Future<void> _startOrderCall(
    BuildContext context, {
    required Map<String, dynamic> orderData,
    required _RiderContactState? contact,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final riderProfile = contact?.profile;
    final riderUid = riderProfile?.uid.trim() ?? '';
    if (riderUid.isNotEmpty) {
      try {
        final caller = await _buildCurrentUserProfile();
        if (!context.mounted) {
          return;
        }
        if (caller.uid == riderUid) {
          throw Exception(L10n.cannotCallSelf);
        }

        final callee =
            riderProfile ??
            UserProfile(
              uid: riderUid,
              displayName: L10n.rider,
              phoneNumber: contact?.phone,
            );

        final callData = await NotificationService().initiateCall(
          caller: caller,
          callee: callee,
          isVideo: false,
        );

        if (!context.mounted) {
          return;
        }

        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => CallScreen(
              channelName:
                  (callData['channelId'] as String?) ??
                  'call_${caller.uid}_$riderUid',
              isVideo: false,
              targetProfile: callee,
              appIdOverride: callData['appId'] as String?,
              tokenOverride: callData['token'] as String?,
              isIncoming: false,
            ),
          ),
        );
        return;
      } catch (error) {
        messenger?.showSnackBar(
          SnackBar(content: Text(L10n.startCallFailed(error))),
        );
      }
    }

    final phone = contact?.phone?.trim();
    if (phone != null && phone.isNotEmpty) {
      await _callPhone(phone, messenger);
      return;
    }

    messenger?.showSnackBar(
      SnackBar(content: Text(L10n.riderInfoMissingForCall)),
    );
  }

  Future<UserProfile> _buildCurrentUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception(L10n.signInRequiredBeforeCallRider);
    }

    final customerDoc = await FirebaseFirestore.instance
        .collection('customer_users')
        .doc(user.uid)
        .get();
    if (customerDoc.exists) {
      return UserProfile.fromSnapshot(customerDoc);
    }

    return UserProfile(
      uid: user.uid,
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email?.trim().isNotEmpty == true
                ? user.email!.trim()
                : L10n.customer),
      phoneNumber: user.phoneNumber,
      photoUrl: user.photoURL,
    );
  }

  _OrderRoadmapState _buildRoadmapState(Map<String, dynamic> data) {
    if (_isTravelPassengerOrder(data)) {
      return _buildTravelRoadmapState(data);
    }

    final status = (data['status'] as String?)?.trim() ?? '';
    final hasDriver =
        ((data['driverId'] as String?)?.trim().isNotEmpty ?? false);
    final riderSearch = data['riderSearch'];
    final matchedBySearch = riderSearch is Map<String, dynamic>
        ? (riderSearch['matched'] == true)
        : false;
    final hasAcceptedAt = data['acceptedAt'] != null;
    final hasScanned =
        ((data['scannedByDriverId'] as String?)?.trim().isNotEmpty ?? false) ||
        data['scannedAt'] != null;

    final riderSearchStarted =
        riderSearch is Map<String, dynamic> ||
        status == 'awaiting_rider' ||
        status == 'pending' ||
        status == 'accepted' ||
        status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final riderMatched =
        hasDriver ||
        matchedBySearch ||
        status == 'pending' ||
        status == 'accepted' ||
        status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final riderAccepted =
        hasAcceptedAt ||
        status == 'accepted' ||
        status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final riderToShop =
        status == 'accepted' ||
        status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final shopPreparing =
        status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final riderScannedPickup =
        hasScanned || status == 'delivering' || status == 'delivered';

    final delivering = status == 'delivering' || status == 'delivered';
    final delivered = status == 'delivered';

    return _OrderRoadmapState(
      riderSearchStarted: riderSearchStarted,
      riderMatched: riderMatched,
      riderAccepted: riderAccepted,
      riderToShop: riderToShop,
      shopPreparing: shopPreparing,
      riderScannedPickup: riderScannedPickup,
      delivering: delivering,
      delivered: delivered,
    );
  }

  _OrderRoadmapState _buildTravelRoadmapState(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim() ?? '';
    final hasDriver =
        ((data['driverId'] as String?)?.trim().isNotEmpty ?? false);
    final riderSearch = data['riderSearch'];
    final matchedBySearch = riderSearch is Map<String, dynamic>
        ? (riderSearch['matched'] == true)
        : false;
    final hasAcceptedAt = data['acceptedAt'] != null;
    final hasPickupArrived =
        data['pickupArrivedAt'] != null ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';
    final hasScanned =
        ((data['scannedByDriverId'] as String?)?.trim().isNotEmpty ?? false) ||
        data['scannedAt'] != null;

    final riderSearchStarted =
        riderSearch is Map<String, dynamic> ||
        status == 'awaiting_rider' ||
        status == 'pending' ||
        status == 'accepted' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final riderMatched =
        hasDriver ||
        matchedBySearch ||
        status == 'pending' ||
        status == 'accepted' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final riderAccepted =
        hasAcceptedAt ||
        status == 'accepted' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    // Step 2: ไรเดอร์ถึงจุดรับแล้ว
    final riderAtPickup = hasPickupArrived || hasScanned;

    // Step 3: ผู้โดยสารขึ้นรถแล้ว (ไม่รอที่จุดรับอีก)
    final passengerBoarded = status == 'delivering' || status == 'delivered';

    final delivering = status == 'delivering' || status == 'delivered';
    final delivered = status == 'delivered';

    return _OrderRoadmapState(
      riderSearchStarted: riderSearchStarted,
      riderMatched: riderMatched,
      riderAccepted: riderAccepted,
      riderToShop: riderAccepted,
      shopPreparing: passengerBoarded,
      riderScannedPickup: riderAtPickup,
      delivering: delivering,
      delivered: delivered,
    );
  }
}

bool _isTravelPassengerOrder(Map<String, dynamic> data) {
  final orderType = (data['orderType'] as String?)?.trim();
  final serviceType = (data['serviceType'] as String?)?.trim();
  return orderType == 'travel_passenger' || serviceType == 'travel_passenger';
}

bool _isClaimReplacementOrder(Map<String, dynamic> data) {
  return (data['orderType'] as String?)?.trim() == 'claim_replacement';
}

bool _canRequestProductClaim(Map<String, dynamic> data) {
  if (!_isDeliveredRoadmapOrder(data)) {
    return false;
  }
  if (_isTravelPassengerOrder(data)) {
    return false;
  }
  if (_isClaimReplacementOrder(data)) {
    return false;
  }
  final claimStatus = (data['claimStatus'] as String?)?.trim().toLowerCase();
  if (claimStatus == 'replaced' || claimStatus == 'credited') {
    return false;
  }
  return true;
}

String? _readTravelPickupLabel(Map<String, dynamic> data) {
  final travelRequest = data['travelRequest'];
  if (travelRequest is Map) {
    final pickup = travelRequest['pickup'];
    if (pickup is Map) {
      final title = (pickup['title'] as String?)?.trim();
      if (title != null && title.isNotEmpty) {
        return title;
      }
    }
  }
  return (data['shopName'] as String?)?.trim();
}

String? _readTravelDestinationLabel(Map<String, dynamic> data) {
  final travelRequest = data['travelRequest'];
  if (travelRequest is Map) {
    final destination = travelRequest['destination'];
    if (destination is Map) {
      final title = (destination['title'] as String?)?.trim();
      if (title != null && title.isNotEmpty) {
        return title;
      }
    }
  }

  final delivery = data['deliverySnapshot'];
  if (delivery is Map) {
    return (delivery['locationLabel'] as String?)?.trim();
  }
  return null;
}

String? _readTravelVehicleLabel(Map<String, dynamic> data) {
  final travelRequest = data['travelRequest'];
  if (travelRequest is Map) {
    return (travelRequest['vehicleTypeLabel'] as String?)?.trim();
  }
  return null;
}

String? _readTravelScheduleLabel(Map<String, dynamic> data) {
  final travelRequest = data['travelRequest'];
  if (travelRequest is Map) {
    return (travelRequest['scheduleLabel'] as String?)?.trim();
  }
  return null;
}

class _ShopRoadmapImage extends StatelessWidget {
  const _ShopRoadmapImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const ValueKey<String>('roadmap-shop-image'),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFF3F4F6),
      ),
      child: CachedAppImage(
        imageUrl: imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        lightweight: true,
        borderRadius: BorderRadius.circular(14),
        errorWidget: const Icon(
          Icons.storefront_outlined,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}

class _RoadmapProductImageCard extends StatelessWidget {
  const _RoadmapProductImageCard({
    required this.name,
    required this.quantity,
    required this.imageUrl,
  });

  final String name;
  final int quantity;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: _kRoadmapProductCarouselHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedAppImage(
            imageUrl: imageUrl,
            width: 88,
            height: 68,
            fit: BoxFit.cover,
            lightweight: true,
            borderRadius: BorderRadius.circular(12),
            errorWidget: Container(
              width: 88,
              height: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF3F4F6),
              ),
              child: const Icon(
                Icons.image_not_supported_outlined,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  L10n.quantityPiecesOrDash(quantity),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadmapProductEntry {
  const _RoadmapProductEntry({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.quantity,
  });

  final String? productId;
  final String name;
  final String? imageUrl;
  final int quantity;
}

class _OrderReviewPanel extends StatelessWidget {
  const _OrderReviewPanel({
    required this.orderId,
    required this.data,
    required this.products,
    required this.firestore,
  });

  final String orderId;
  final Map<String, dynamic> data;
  final List<_RoadmapProductEntry> products;
  final FirebaseFirestore firestore;

  @override
  Widget build(BuildContext context) {
    final customerId = _currentCustomerUid();
    final orderCustomerId = (data['customerId'] as String?)?.trim();
    final reviewableProducts = products
        .where((product) => product.productId?.trim().isNotEmpty == true)
        .toList(growable: false);
    final shopId = _readOrderShopId(data);
    final driverId = _readOrderRiderId(data);
    final hasShopReview = shopId.isNotEmpty;
    final hasRiderReview = driverId.isNotEmpty;
    final hasProductReview = reviewableProducts.isNotEmpty;

    if (customerId == null ||
        customerId.isEmpty ||
        orderCustomerId != customerId ||
        (!hasShopReview && !hasRiderReview && !hasProductReview)) {
      return const SizedBox.shrink();
    }

    final panelTitle = hasProductReview || hasShopReview
        ? (hasRiderReview
            ? L10n.reviewProductsShopRider
            : L10n.reviewProductsShop)
        : L10n.reviewRider;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.star_rate_rounded, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    panelTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF9A3412),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              L10n.reviewHelpOthers,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF92400E)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _showOrderReviewSheet(context, customerId),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF57C00),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.rate_review_outlined),
              label: Text(L10n.reviewOrEdit),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOrderReviewSheet(
    BuildContext context,
    String customerId,
  ) async {
    final shopId = _readOrderShopId(data);
    final shopOwnerId = _resolveReviewShopOwnerId(data, shopId);
    final shopName = LocalizedProductText.shopName(data);
    final hasShopReview = shopId.isNotEmpty;
    final allowedProductIds = _readOrderProductIds(data);
    final reviewableProducts = products
        .where((product) => product.productId?.trim().isNotEmpty == true)
        .where(
          (product) =>
              allowedProductIds.isEmpty ||
              allowedProductIds.contains(product.productId!.trim()),
        )
        .toList(growable: false);

    final productDrafts = <_ReviewDraft>[];
    for (final product in reviewableProducts) {
      final productId = product.productId!.trim();
      final reviewId = '${orderId}_$productId';
      final doc = await firestore
          .collection('product_reviews')
          .doc(reviewId)
          .get();
      final review = doc.data();
      productDrafts.add(
        _ReviewDraft(
          id: reviewId,
          title: product.name,
          subtitle: product.quantity > 0
              ? L10n.quantityCount(product.quantity)
              : null,
          imageUrl: product.imageUrl,
          rating: _readReviewRating(review),
          comment: (review?['comment'] as String?) ?? '',
          imageUrls: _readReviewImageUrls(review),
          exists: doc.exists,
          metadata: <String, dynamic>{
            'orderId': orderId,
            'productId': productId,
            'shopId': shopId,
            'shopOwnerId': shopOwnerId,
            'customerId': customerId,
            'productNameSnapshot': product.name,
            'productImageUrlSnapshot': product.imageUrl,
            'shopNameSnapshot': shopName,
            'status': 'visible',
          },
        ),
      );
    }

    final shopReviewId = '${orderId}_$shopId';
    final shopReviewDoc = hasShopReview
        ? await firestore.collection('shop_reviews').doc(shopReviewId).get()
        : null;
    final shopReview = shopReviewDoc?.data();
    final shopDraft = hasShopReview
        ? _ReviewDraft(
            id: shopReviewId,
            title: shopName,
            subtitle: L10n.reviewShop,
            imageUrl: _roadmapReadTrimmedString(
              data['shopImageUrl'],
              data['imageUrl'],
              data['photoUrl'],
            ),
            rating: _readReviewRating(shopReview),
            comment: (shopReview?['comment'] as String?) ?? '',
            imageUrls: _readReviewImageUrls(shopReview),
            exists: shopReviewDoc?.exists ?? false,
            metadata: <String, dynamic>{
              'orderId': orderId,
              'shopId': shopId,
              'shopOwnerId': shopOwnerId,
              'customerId': customerId,
              'shopNameSnapshot': shopName,
              'status': 'visible',
            },
          )
        : null;

    final driverId = _readOrderRiderId(data);
    _ReviewDraft? riderDraft;
    if (driverId.isNotEmpty) {
      final riderReviewId = '${orderId}_$driverId';
      final riderReviewDoc = await firestore
          .collection('rider_reviews')
          .doc(riderReviewId)
          .get();
      final riderReview = riderReviewDoc.data();
      final riderName = _roadmapReadFirstNonEmptyValue(data, const <String>[
            'riderName',
            'driverName',
            'deliveryProofCapturedByName',
          ]) ??
          L10n.rider;
      riderDraft = _ReviewDraft(
        id: riderReviewId,
        title: riderName,
        subtitle: L10n.reviewRider,
        imageUrl: null,
        rating: _readReviewRating(riderReview),
        comment: (riderReview?['comment'] as String?) ?? '',
        imageUrls: _readReviewImageUrls(riderReview),
        exists: riderReviewDoc.exists,
        metadata: <String, dynamic>{
          'orderId': orderId,
          'riderId': driverId,
          'customerId': customerId,
          'riderNameSnapshot': riderName,
          'status': 'visible',
        },
      );
    }

    if (!context.mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _OrderReviewSheet(
        firestore: firestore,
        productDrafts: productDrafts,
        shopDraft: shopDraft,
        riderDraft: riderDraft,
      ),
    );
  }
}

int _readReviewRating(Map<String, dynamic>? review) {
  final existing = (review?['rating'] as num?)?.round();
  if (existing != null && existing >= 1 && existing <= 5) {
    return existing;
  }
  return 5;
}

String _reviewCollectionForDraft(_ReviewDraft draft) {
  if (draft.metadata.containsKey('productId')) {
    return 'product_reviews';
  }
  if (draft.metadata.containsKey('riderId')) {
    return 'rider_reviews';
  }
  return 'shop_reviews';
}

List<String> _readReviewImageUrls(Map<String, dynamic>? review) {
  return ((review?['imageUrls'] as List?) ?? const <dynamic>[])
      .whereType<String>()
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
}

String _resolveReviewShopOwnerId(Map<String, dynamic> data, String shopId) {
  final shopOwnerId = (data['shopOwnerId'] as String?)?.trim();
  if (shopOwnerId != null && shopOwnerId.isNotEmpty) {
    return shopOwnerId;
  }
  return shopId;
}

String _readOrderRiderId(Map<String, dynamic> data) {
  final driverId = (data['driverId'] as String?)?.trim();
  if (driverId != null && driverId.isNotEmpty) {
    return driverId;
  }
  return (data['deliveryProofCapturedById'] as String?)?.trim() ?? '';
}

List<String> _readOrderProductIds(Map<String, dynamic> data) {
  final fromField = (data['productIds'] as List?) ?? const <dynamic>[];
  final productIds = fromField
      .map((value) => value?.toString().trim() ?? '')
      .where((value) => value.isNotEmpty)
      .toSet();
  if (productIds.isNotEmpty) {
    return productIds.toList(growable: false);
  }

  final rawProducts = data['products'];
  if (rawProducts is! List) {
    return const <String>[];
  }

  for (final rawProduct in rawProducts) {
    if (rawProduct is! Map) {
      continue;
    }
    final productMap = Map<String, dynamic>.from(rawProduct);
    final productId = _roadmapReadFirstNonEmptyValue(productMap, const <String>[
      'productId',
      'product_id',
      'id',
      'docId',
      'documentId',
    ]);
    if (productId != null) {
      productIds.add(productId);
    }
  }
  return productIds.toList(growable: false);
}

class _ReviewDraft {
  _ReviewDraft({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.rating,
    required this.comment,
    required this.imageUrls,
    required this.exists,
    required this.metadata,
    List<File>? pendingImages,
  }) : pendingImages = pendingImages ?? <File>[];

  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  int rating;
  String comment;
  List<String> imageUrls;
  List<File> pendingImages;
  bool exists;
  final Map<String, dynamic> metadata;

  int get totalImageCount => imageUrls.length + pendingImages.length;
}

class _OrderReviewSheet extends StatefulWidget {
  const _OrderReviewSheet({
    required this.firestore,
    required this.productDrafts,
    this.shopDraft,
    this.riderDraft,
  });

  final FirebaseFirestore firestore;
  final List<_ReviewDraft> productDrafts;
  final _ReviewDraft? shopDraft;
  final _ReviewDraft? riderDraft;

  @override
  State<_OrderReviewSheet> createState() => _OrderReviewSheetState();
}

class _OrderReviewSheetState extends State<_OrderReviewSheet> {
  bool _saving = false;

  Future<void> _saveReviewDraft(_ReviewDraft draft) async {
    final collection = _reviewCollectionForDraft(draft);
    final ref = widget.firestore.collection(collection).doc(draft.id);
    final comment = draft.comment.trim();
    final customerId = (draft.metadata['customerId'] ?? '').toString();

    var imageUrls = List<String>.from(draft.imageUrls);
    if (draft.pendingImages.isNotEmpty && customerId.isNotEmpty) {
      final remainingSlots =
          ReviewService.maxImagesPerReview - imageUrls.length;
      if (remainingSlots > 0) {
        final uploaded = await ReviewService.uploadReviewImages(
          customerId: customerId,
          reviewId: draft.id,
          files: draft.pendingImages
              .take(remainingSlots)
              .toList(growable: false),
        );
        imageUrls = <String>[
          ...imageUrls,
          ...uploaded,
        ].take(ReviewService.maxImagesPerReview).toList(growable: false);
      }
    }

    if (draft.exists) {
      await ref.set(<String, dynamic>{
        'rating': draft.rating,
        'comment': comment,
        'imageUrls': imageUrls,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    await ref.set(<String, dynamic>{
      ...draft.metadata,
      'rating': draft.rating,
      'comment': comment,
      'imageUrls': imageUrls,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _submit() async {
    final allDrafts = <_ReviewDraft>[
      ...widget.productDrafts,
      if (widget.shopDraft != null) widget.shopDraft!,
      if (widget.riderDraft != null) widget.riderDraft!,
    ];
    final draftsToSave = allDrafts.where((draft) => draft.rating > 0).toList();
    if (draftsToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.rateAtLeastOne)),
      );
      return;
    }

    setState(() => _saving = true);
    var savedCount = 0;
    String? firstError;
    try {
      for (final draft in draftsToSave) {
        try {
          await _saveReviewDraft(draft);
          savedCount += 1;
        } catch (error) {
          firstError ??= '$error';
        }
      }

      if (!mounted) {
        return;
      }

      if (savedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              firstError == null
                  ? L10n.reviewSaveFailed
                  : L10n.reviewSaveFailedWithError(firstError),
            ),
          ),
        );
        return;
      }

      Navigator.of(context).pop();
      final message = savedCount == draftsToSave.length
          ? L10n.reviewSaved
          : L10n.reviewSavedPartial(savedCount, draftsToSave.length);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.reviewSaveFailedWithError(error))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasShopOrProduct =
        widget.productDrafts.isNotEmpty || widget.shopDraft != null;
    final sheetTitle = hasShopOrProduct
        ? (widget.riderDraft != null
            ? L10n.reviewProductsShopRider
            : L10n.reviewProductsShop)
        : L10n.reviewRider;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                sheetTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                L10n.reviewMaxImagesHint(ReviewService.maxImagesPerReview),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
              ),
              const SizedBox(height: 14),
              for (final draft in widget.productDrafts) ...<Widget>[
                _ReviewDraftTile(
                  draft: draft,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.shopDraft != null) ...<Widget>[
                _ReviewDraftTile(
                  draft: widget.shopDraft!,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.riderDraft != null)
                _ReviewDraftTile(
                  draft: widget.riderDraft!,
                  onChanged: () => setState(() {}),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF57C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? L10n.savingReview : L10n.saveReview),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewDraftTile extends StatefulWidget {
  const _ReviewDraftTile({required this.draft, required this.onChanged});

  final _ReviewDraft draft;
  final VoidCallback onChanged;

  @override
  State<_ReviewDraftTile> createState() => _ReviewDraftTileState();
}

class _ReviewDraftTileState extends State<_ReviewDraftTile> {
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(text: widget.draft.comment);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _ReviewThumb(imageUrl: draft.imageUrl, title: draft.title),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      draft.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (draft.subtitle?.isNotEmpty == true)
                      Text(
                        draft.subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List<Widget>.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => draft.rating = value);
                  widget.onChanged();
                },
                icon: Icon(
                  value <= draft.rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: const Color(0xFFF59E0B),
                  size: 30,
                ),
              );
            }),
          ),
          TextField(
            controller: _commentController,
            maxLines: 2,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: L10n.commentOptional,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
            onChanged: (value) => draft.comment = value,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final url in draft.imageUrls)
                _ReviewImageChip(
                  imageUrl: url,
                  onRemove: () {
                    setState(() => draft.imageUrls.remove(url));
                    widget.onChanged();
                  },
                ),
              for (final file in draft.pendingImages)
                _ReviewImageChip(
                  localFile: file,
                  onRemove: () {
                    setState(() => draft.pendingImages.remove(file));
                    widget.onChanged();
                  },
                ),
              if (draft.totalImageCount < ReviewService.maxImagesPerReview)
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: Text(L10n.addPhoto),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickImages() async {
    final draft = widget.draft;
    final remaining = ReviewService.maxImagesPerReview - draft.totalImageCount;
    if (remaining <= 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.maxPhotosPerReview(ReviewService.maxImagesPerReview),
          ),
        ),
      );
      return;
    }

    final picked = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (picked.isEmpty || !mounted) {
      return;
    }

    setState(() {
      draft.pendingImages.addAll(
        picked
            .take(remaining)
            .map((file) => File(file.path))
            .where((file) => file.path.isNotEmpty),
      );
    });
    widget.onChanged();
  }
}

class _ReviewImageChip extends StatelessWidget {
  const _ReviewImageChip({
    this.imageUrl,
    this.localFile,
    required this.onRemove,
  });

  final String? imageUrl;
  final File? localFile;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 72,
            height: 72,
            child: localFile != null
                ? Image.file(localFile!, fit: BoxFit.cover)
                : CachedAppImage(imageUrl: imageUrl!, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Colors.black87,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewThumb extends StatelessWidget {
  const _ReviewThumb({required this.imageUrl, required this.title});

  final String? imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 52,
        height: 52,
        color: const Color(0xFFF3F4F6),
        child: url != null && url.isNotEmpty
            ? CachedAppImage(
                imageUrl: url,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                lightweight: true,
              )
            : Center(
                child: Text(
                  title.characters.take(1).toString(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
      ),
    );
  }
}

class _RiderContactState {
  const _RiderContactState({required this.profile, required this.phone});

  final UserProfile? profile;
  final String? phone;
}

class _TimelineStepTile extends StatelessWidget {
  const _TimelineStepTile({
    required this.label,
    required this.status,
    this.isLast = false,
    this.leadingIcon,
  });

  final String label;
  final bool status;
  final bool isLast;
  final IconData? leadingIcon;
  @override
  Widget build(BuildContext context) {
    final color = status ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(
              status ? Icons.check_circle : Icons.radio_button_unchecked,
              color: color,
              size: 20,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: color.withValues(alpha: 0.45),
              ),
          ],
        ),
        const SizedBox(width: 10),
        if (leadingIcon != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(leadingIcon, size: 18, color: color),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              style: TextStyle(
                color: status
                    ? const Color(0xFF111827)
                    : const Color(0xFF6B7280),
                fontWeight: status ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderRoadmapState {
  const _OrderRoadmapState({
    required this.riderSearchStarted,
    required this.riderMatched,
    required this.riderAccepted,
    required this.riderToShop,
    required this.shopPreparing,
    required this.riderScannedPickup,
    required this.delivering,
    required this.delivered,
  });

  final bool riderSearchStarted;
  final bool riderMatched;
  final bool riderAccepted;
  final bool riderToShop;
  final bool shopPreparing;
  final bool riderScannedPickup;
  final bool delivering;
  final bool delivered;
}

bool _orderCanRequestRefund(Map<String, dynamic> data) =>
    orderCanRequestRefund(data);

Future<Map<String, String>?> _showRefundAccountDialog(BuildContext context) =>
    showOrderRefundAccountDialog(context);

class _AwaitingShopDecisionBanner extends StatefulWidget {
  const _AwaitingShopDecisionBanner({
    required this.orderId,
    required this.data,
    required this.firestore,
    required this.orderActions,
  });

  final String orderId;
  final Map<String, dynamic> data;
  final FirebaseFirestore firestore;
  final CustomerOrderActionsService orderActions;

  @override
  State<_AwaitingShopDecisionBanner> createState() =>
      _AwaitingShopDecisionBannerState();
}

class _AwaitingShopDecisionBannerState
    extends State<_AwaitingShopDecisionBanner> {
  static const Duration _shopDecisionThreshold = Duration(minutes: 15);
  static const Duration _customerExtraWaitDuration = Duration(minutes: 15);

  Timer? _refreshTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  DateTime? _readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  String _readStatus() => (widget.data['status'] as String?)?.trim() ?? '';

  String _readShopDecisionStatus() =>
      (widget.data['shopDecisionStatus'] as String?)?.trim() ?? '';

  bool get _shopHasAccepted {
    final status = _readStatus();
    return widget.data['preparingStartTime'] != null ||
        status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';
  }

  bool get _shopRejected {
    final cancelReason = (widget.data['cancelReason'] as String?)?.trim() ?? '';
    return _readShopDecisionStatus() == 'rejected' ||
        widget.data['shopRejectedAt'] != null ||
        cancelReason == 'shop_rejected_waiting_customer_decision' ||
        cancelReason == 'shop_rejected_order';
  }

  bool get _isWaiting {
    final waitUntil = widget.data['customerShopWaitUntil'];
    if (waitUntil is Timestamp) {
      return waitUntil.toDate().isAfter(DateTime.now());
    }
    return false;
  }

  bool get _isStale {
    if (_isWaiting) {
      return true;
    }
    if (_shopHasAccepted) {
      return false;
    }
    if (_shopRejected) {
      return true;
    }

    final status = _readStatus();
    if (status != 'accepted') {
      return false;
    }

    final acceptedAt = _readTimestamp(widget.data['acceptedAt']);
    if (acceptedAt == null) {
      return false;
    }
    return DateTime.now().difference(acceptedAt) >= _shopDecisionThreshold;
  }

  Future<void> _wait15Min() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.orderActions.shopWait15Min(orderId: widget.orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.waitExtraMinutes(_customerExtraWaitDuration.inMinutes),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(L10n.saveWaitFailed(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelOrder() async {
    if (_busy) return;

    Map<String, String>? refundInfo;
    if (_orderCanRequestRefund(widget.data)) {
      refundInfo = await _showRefundAccountDialog(context);
      if (refundInfo == null || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      await widget.orderActions.shopCancel(
        orderId: widget.orderId,
        shopRejected: _shopRejected,
        refundInfo: refundInfo,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(L10n.orderCancelled)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(L10n.cancelOrderFailed(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canRequestRefund => _orderCanRequestRefund(widget.data);

  @override
  Widget build(BuildContext context) {
    if (!_isStale) return const SizedBox.shrink();

    final waiting = _isWaiting;
    final rejected = _shopRejected;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFF59E0B)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                color: Color(0xFFD97706),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  waiting
                      ? L10n.waitingShopExtra15
                      : rejected
                      ? L10n.shopRejectedOrder
                      : L10n.shopNotAcceptedAfterRider,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            waiting
                ? L10n.canCancelIfShopLate
                : (_canRequestRefund
                      ? L10n.canWaitOrCancelRefund
                      : L10n.canWaitOrCancel),
            style: const TextStyle(color: Color(0xFF78350F), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || waiting ? null : _wait15Min,
                  icon: const Icon(Icons.timer_outlined),
                  label: Text(waiting ? L10n.waiting : L10n.wait15More),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                  ),
                  onPressed: _busy ? null : _cancelOrder,
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(L10n.cancelOrder),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _readOrderShopId(Map<String, dynamic> data) {
  final direct = _roadmapReadFirstNonEmptyValue(data, _kOrderShopLookupFields);
  if (direct != null) {
    return direct;
  }

  final shopSnapshot = data['shopSnapshot'];
  if (shopSnapshot is Map) {
    final fromSnapshot = _roadmapReadFirstNonEmptyValue(
      Map<String, dynamic>.from(shopSnapshot),
      _kOrderShopLookupFields,
    );
    if (fromSnapshot != null) {
      return fromSnapshot;
    }
  }

  final rawProducts = data['products'];
  if (rawProducts is List) {
    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }

      final productMap = Map<String, dynamic>.from(rawProduct);
      final productShopId = _roadmapReadFirstNonEmptyValue(
        productMap,
        _kOrderShopLookupFields,
      );
      if (productShopId != null) {
        return productShopId;
      }
    }
  }

  return '';
}

String? _roadmapReadFirstNonEmptyValue(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _roadmapReadTrimmedString(
  dynamic first,
  dynamic second,
  dynamic third,
) {
  for (final value in <dynamic>[first, second, third]) {
    final trimmed = value?.toString().trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

