import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'call_screen.dart';
import 'chat_room_screen.dart';
import 'models/user_profile.dart';
import 'services/notification_service.dart';
import 'services/review_service.dart';
import 'widgets/cached_app_image.dart';

const double _kRoadmapProductCarouselHeight = 128;

const Set<String> _kArchivedRoadmapOrderStatuses = <String>{
  'cancelled',
  'canceled',
  'refund',
  'refunded',
};

bool _isArchivedRoadmapOrder(Map<String, dynamic> data) {
  final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
  return _kArchivedRoadmapOrderStatuses.contains(status);
}

bool _isActiveRoadmapOrder(Map<String, dynamic> data) {
  return !_isArchivedRoadmapOrder(data);
}

String _readOrderStatusLabel(Map<String, dynamic> data) {
  final label = (data['statusLabel'] as String?)?.trim();
  if (label != null && label.isNotEmpty) {
    return label;
  }
  final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
  switch (status) {
    case 'cancelled':
    case 'canceled':
      return 'ยกเลิกออเดอร์';
    case 'refund':
    case 'refunded':
      return 'ขอคืนเงิน';
    case 'delivered':
      return 'ส่งสำเร็จ';
    default:
      return status.isEmpty ? 'ออเดอร์' : status;
  }
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
    FirebaseFirestore? firestore,
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  final List<String> orderIds;
  final FirebaseFirestore firestore;

  @override
  Widget build(BuildContext context) {
    final uniqueOrderIds = orderIds.toSet().toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Roadmap การจัดส่ง'),
        actions: [
          TextButton.icon(
            onPressed: () => _showOrderProductHistorySheet(
              context: context,
              firestore: firestore,
            ),
            icon: const Icon(Icons.history, size: 20),
            label: const Text('ประวัติ'),
          ),
        ],
      ),
      body: _CustomerActiveRoadmapList(
        preferredOrderIds: uniqueOrderIds,
        uid: FirebaseAuth.instance.currentUser?.uid,
        firestore: firestore,
        onOpenHistory: () => _showOrderProductHistorySheet(
          context: context,
          firestore: firestore,
        ),
      ),
    );
  }
}

class _RoadmapList extends StatelessWidget {
  const _RoadmapList({required this.orderIds, required this.firestore});

  final List<String> orderIds;
  final FirebaseFirestore firestore;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orderIds.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final orderId = orderIds[index];
        return _OrderRoadmapCard(orderId: orderId, firestore: firestore);
      },
    );
  }
}

class _CustomerActiveRoadmapList extends StatelessWidget {
  const _CustomerActiveRoadmapList({
    required this.preferredOrderIds,
    required this.uid,
    required this.firestore,
    required this.onOpenHistory,
  });

  final List<String> preferredOrderIds;
  final String? uid;
  final FirebaseFirestore firestore;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    if (uid == null || uid!.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('กรุณาเข้าสู่ระบบเพื่อดูโรดแมปออเดอร์'),
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
              child: Text('โหลดโรดแมปไม่สำเร็จ: ${snapshot.error}'),
            ),
          );
        }

        final docs =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .toList(growable: false);
        final dataById = <String, Map<String, dynamic>>{
          for (final doc in docs) doc.id: doc.data(),
        };

        final activeDocs = docs
            .where((doc) => _isActiveRoadmapOrder(doc.data()))
            .toList(growable: false);

        activeDocs.sort((a, b) {
          final aTs = a.data()['createdAt'];
          final bTs = b.data()['createdAt'];
          final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
          final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
          return bMs.compareTo(aMs);
        });

        final List<String> orderIds;
        if (preferredOrderIds.isNotEmpty) {
          orderIds = preferredOrderIds
              .where((id) {
                final data = dataById[id];
                return data == null || _isActiveRoadmapOrder(data);
              })
              .toList(growable: false);
        } else {
          orderIds = activeDocs.map((doc) => doc.id).toList(growable: false);
        }

        if (orderIds.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ไม่มีออเดอร์ที่กำลังดำเนินการ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ออเดอร์ที่ยกเลิกหรือขอคืนเงินแล้วจะอยู่ในปุ่มประวัติ',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onOpenHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('ดูประวัติออเดอร์'),
                  ),
                ],
              ),
            ),
          );
        }

        return _RoadmapList(orderIds: orderIds, firestore: firestore);
      },
    );
  }
}

class _OrderRoadmapCard extends StatelessWidget {
  const _OrderRoadmapCard({required this.orderId, required this.firestore});

  final String orderId;
  final FirebaseFirestore firestore;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('orders').doc(orderId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('โหลดออเดอร์ $orderId ไม่สำเร็จ: ${snapshot.error}'),
            ),
          );
        }

        final data = snapshot.data?.data();
        if (data == null) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('ไม่พบข้อมูลออเดอร์ $orderId'),
            ),
          );
        }

        final roadmap = _buildRoadmapState(data);
        final isTravelOrder = _isTravelPassengerOrder(data);
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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String?>(
                  future: shopImageUrl != null
                      ? Future<String?>.value(shopImageUrl)
                      : _loadShopImageUrl(data),
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
                      ? 'จุดรับ: ${pickupLabel?.isNotEmpty == true ? pickupLabel : '-'}'
                      : 'ร้าน: ${shopName?.isNotEmpty == true ? shopName : '-'}',
                ),
                if (isTravelOrder)
                  Text(
                    'จุดส่ง: ${destinationLabel?.isNotEmpty == true ? destinationLabel : '-'}',
                  ),
                Text('ยอดชำระ: THB ${total.toStringAsFixed(1)}'),
                if (isTravelOrder && travelVehicleLabel != null)
                  Text('ประเภทรถ: $travelVehicleLabel'),
                if (isTravelOrder && travelScheduleLabel != null)
                  Text('เวลาเดินทาง: $travelScheduleLabel'),
                if (productEntries.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    isTravelOrder ? 'รายละเอียดการเดินทาง' : 'สินค้าในออเดอร์',
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
                  const Text(
                    'รูปยืนยันจากไรเดอร์',
                    style: TextStyle(fontWeight: FontWeight.w700),
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
                        child: const Text('โหลดรูปยืนยันไม่สำเร็จ'),
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
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ChatRoomScreen(
                                          friendProfile: contact!.profile!,
                                          orderId: orderId,
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('แชทไรเดอร์'),
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
                              canCall ? 'โทรไรเดอร์' : 'โทรไรเดอร์ไม่ได้',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                _AwaitingRiderBanner(
                  orderId: orderId,
                  data: data,
                  firestore: firestore,
                ),
                if (!isTravelOrder)
                  _AwaitingShopDecisionBanner(
                    orderId: orderId,
                    data: data,
                    firestore: firestore,
                  ),
                _TimelineStepTile(
                  label: 'ไรเดอร์รับออเดอร์',
                  status: roadmap.riderAccepted,
                  leadingIcon: Icons.assignment_turned_in_outlined,
                ),
                _TimelineStepTile(
                  label: isTravelOrder
                      ? 'กำลังรอผู้โดยสารขึ้นรถ'
                      : 'ร้านค้ารับออเดอร์',
                  status: roadmap.shopPreparing,
                  leadingIcon: isTravelOrder
                      ? Icons.airline_seat_recline_normal_outlined
                      : Icons.storefront_outlined,
                ),
                _TimelineStepTile(
                  label: isTravelOrder
                      ? 'ไรเดอร์ถึงจุดรับแล้ว'
                      : 'ไรเดอร์สแกนรับสินค้า',
                  status: roadmap.riderScannedPickup,
                  leadingIcon: isTravelOrder
                      ? Icons.location_on_outlined
                      : Icons.qr_code_scanner_outlined,
                ),
                _TimelineStepTile(
                  label: isTravelOrder
                      ? 'กำลังเดินทางไปจุดส่ง'
                      : 'ไรเดอร์กำลังไปส่ง',
                  status: roadmap.delivering,
                  leadingIcon: isTravelOrder
                      ? Icons.directions_car_outlined
                      : Icons.delivery_dining_outlined,
                ),
                _TimelineStepTile(
                  label: isTravelOrder ? 'ถึงจุดหมายแล้ว' : 'ส่งถึงลูกค้าแล้ว',
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
      return 'ยืนยันโดย $capturedByName เมื่อ $capturedAt';
    }
    if (capturedByName != null) {
      return 'ยืนยันโดย $capturedByName';
    }
    if (capturedAt != null) {
      return 'ถ่ายเมื่อ $capturedAt';
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
      );
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
          name: name ?? 'สินค้า',
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

  Future<_RiderContactState> _loadRiderContactState(
    Map<String, dynamic> data,
  ) async {
    final driverId = (data['driverId'] as String?)?.trim();
    final fallbackName =
        ((data['driverName'] as String?)?.trim().isNotEmpty ?? false)
        ? (data['driverName'] as String).trim()
        : 'ไรเดอร์';
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
        const SnackBar(content: Text('ไม่สามารถโทรออกได้')),
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
          throw Exception('ไม่สามารถโทรหาบัญชีตัวเองได้');
        }

        final callee =
            riderProfile ??
            UserProfile(
              uid: riderUid,
              displayName: 'ไรเดอร์',
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
          SnackBar(content: Text('เริ่มการโทรไม่สำเร็จ: $error')),
        );
      }
    }

    final phone = contact?.phone?.trim();
    if (phone != null && phone.isNotEmpty) {
      await _callPhone(phone, messenger);
      return;
    }

    messenger?.showSnackBar(
      const SnackBar(content: Text('ไม่พบข้อมูลไรเดอร์สำหรับโทรออก')),
    );
  }

  Future<UserProfile> _buildCurrentUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception('กรุณาเข้าสู่ระบบก่อนโทรหาไรเดอร์');
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
                : 'ลูกค้า'),
      phoneNumber: user.phoneNumber,
      photoUrl: user.photoURL,
    );
  }

  _OrderRoadmapState _buildRoadmapState(Map<String, dynamic> data) {
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
}

bool _isTravelPassengerOrder(Map<String, dynamic> data) {
  final orderType = (data['orderType'] as String?)?.trim();
  final serviceType = (data['serviceType'] as String?)?.trim();
  return orderType == 'travel_passenger' || serviceType == 'travel_passenger';
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
                  quantity > 0 ? '$quantity ชิ้น' : '-',
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
    final customerId = FirebaseAuth.instance.currentUser?.uid;
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
        ? (hasRiderReview ? 'รีวิวสินค้า ร้านค้า และไรเดอร์' : 'รีวิวสินค้าและร้านค้า')
        : 'รีวิวไรเดอร์';

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
              'รีวิวจากออเดอร์ที่ส่งสำเร็จ ช่วยให้ลูกค้าคนอื่นตัดสินใจง่ายขึ้น',
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
              label: const Text('รีวิว / แก้ไขรีวิว'),
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
    final shopName = (data['shopName'] as String?)?.trim() ?? 'ร้านค้า';
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
          subtitle: product.quantity > 0 ? 'จำนวน ${product.quantity}' : null,
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
            subtitle: 'รีวิวร้านค้า',
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
          'ไรเดอร์';
      riderDraft = _ReviewDraft(
        id: riderReviewId,
        title: riderName,
        subtitle: 'รีวิวไรเดอร์',
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
        const SnackBar(content: Text('กรุณาให้คะแนนอย่างน้อย 1 รายการ')),
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
                  ? 'บันทึกรีวิวไม่สำเร็จ'
                  : 'บันทึกรีวิวไม่สำเร็จ: $firstError',
            ),
          ),
        );
        return;
      }

      Navigator.of(context).pop();
      final message = savedCount == draftsToSave.length
          ? 'บันทึกรีวิวเรียบร้อยแล้ว'
          : 'บันทึกรีวิวได้ $savedCount/${draftsToSave.length} รายการ';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกรีวิวไม่สำเร็จ: $error')));
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
            ? 'รีวิวสินค้า ร้านค้า และไรเดอร์'
            : 'รีวิวสินค้าและร้านค้า')
        : 'รีวิวไรเดอร์';
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
                'ให้คะแนนและแนบรูปได้สูงสุด ${ReviewService.maxImagesPerReview} รูปต่อรายการ ค่าเริ่มต้นคือ 5 ดาว',
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
                label: Text(_saving ? 'กำลังบันทึก...' : 'บันทึกรีวิว'),
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
            decoration: const InputDecoration(
              labelText: 'ความคิดเห็น (ไม่บังคับ)',
              border: OutlineInputBorder(),
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
                  label: const Text('เพิ่มรูป'),
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
            'อัปโหลดได้สูงสุด ${ReviewService.maxImagesPerReview} รูปต่อรีวิว',
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

bool _orderIsCashOnDelivery(Map<String, dynamic> data) {
  final paymentMethod =
      (data['paymentMethod'] as String?)?.trim().toLowerCase() ?? '';
  final paymentStatus =
      (data['paymentStatus'] as String?)?.trim().toLowerCase() ?? '';
  return paymentMethod == 'cash_on_delivery' ||
      paymentStatus == 'cash_on_delivery';
}

bool _orderCanRequestRefund(Map<String, dynamic> data) {
  if (_orderIsCashOnDelivery(data)) {
    return false;
  }

  final paymentStatus =
      (data['paymentStatus'] as String?)?.trim().toLowerCase() ?? '';
  return paymentStatus == 'verified';
}

Future<Map<String, String>?> _showRefundAccountDialog(BuildContext context) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => const _RefundAccountDialog(),
  );
}

class _RefundAccountDialog extends StatefulWidget {
  const _RefundAccountDialog();

  @override
  State<_RefundAccountDialog> createState() => _RefundAccountDialogState();
}

class _RefundAccountDialogState extends State<_RefundAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _bankNameController = TextEditingController();

  @override
  void dispose() {
    _accountNumberController.dispose();
    _accountNameController.dispose();
    _bankNameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, {
      'refundBankAccountNumber': _accountNumberController.text.trim(),
      'refundAccountName': _accountNameController.text.trim(),
      'refundBankName': _bankNameController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ขอคืนเงิน'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'กรุณาใส่หมายเลขบัญชี ชื่อ และธนาคารให้ถูกต้อง และต้องเป็นบัญชีที่โอนมาซื้อเท่านั้น หากเป็นบัญชีอื่นจะไม่สามารถโอนคืนได้ เนื่องจากเกี่ยวข้องกับข้อกฎหมาย ระบบสรุปยอดเวลา 18:00 น. ของทุกวัน และเงินจะเข้าบัญชีช่วง 18:00-20:00 น.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'หมายเลขบัญชี',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'กรุณาใส่หมายเลขบัญชี';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _accountNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'ชื่อเจ้าของบัญชี',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'กรุณาใส่ชื่อเจ้าของบัญชี';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _bankNameController,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'ชื่อธนาคาร',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'กรุณาใส่ชื่อธนาคาร';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _submit, child: const Text('ยืนยันคืนเงิน')),
      ],
    );
  }
}

class _AwaitingRiderBanner extends StatefulWidget {
  const _AwaitingRiderBanner({
    required this.orderId,
    required this.data,
    required this.firestore,
  });

  final String orderId;
  final Map<String, dynamic> data;
  final FirebaseFirestore firestore;

  @override
  State<_AwaitingRiderBanner> createState() => _AwaitingRiderBannerState();
}

class _AwaitingRiderBannerState extends State<_AwaitingRiderBanner> {
  static const Duration _noAcceptedRiderThreshold = Duration(minutes: 15);
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

  DateTime? _riderWaitStartedAt() {
    return _readTimestamp(widget.data['customerWaitRequestedAt']) ??
        _readTimestamp(widget.data['reassignedAt']) ??
        _readTimestamp(widget.data['assignedRiderAt']) ??
        _readTimestamp(widget.data['customerConfirmedAt']) ??
        _readTimestamp(widget.data['createdAt']);
  }

  bool get _isStale {
    final status = (widget.data['status'] as String?)?.trim() ?? '';
    final driverId = (widget.data['driverId'] as String?)?.trim() ?? '';
    final reassignFailed = (widget.data['reassignFailureReason'] as String?)
        ?.trim();
    final acceptedAt = _readTimestamp(widget.data['acceptedAt']);

    if (_isWaiting) {
      return true;
    }

    // Show when reassignment explicitly failed.
    if (reassignFailed != null && reassignFailed.isNotEmpty) {
      return true;
    }

    if (acceptedAt != null) {
      return false;
    }

    final waitStartedAt = _riderWaitStartedAt();
    if (waitStartedAt == null) {
      return false;
    }

    final age = DateTime.now().difference(waitStartedAt);
    if (age < _noAcceptedRiderThreshold) {
      return false;
    }

    // No rider matched at all, or a rider was assigned but has not accepted yet.
    if (status == 'awaiting_rider' && driverId.isEmpty) {
      return true;
    }
    if (status == 'pending' && driverId.isNotEmpty) {
      return true;
    }
    return false;
  }

  bool get _isWaiting {
    final waitUntil = widget.data['customerWaitUntil'];
    if (waitUntil is Timestamp) {
      return waitUntil.toDate().isAfter(DateTime.now());
    }
    return false;
  }

  Future<void> _wait15Min() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final until = DateTime.now().add(_customerExtraWaitDuration);
      await widget.firestore.collection('orders').doc(widget.orderId).set({
        'customerWaitUntil': Timestamp.fromDate(until),
        'customerWaitRequestedAt': FieldValue.serverTimestamp(),
        'customerNoRiderChoice': 'wait_15_min',
        'reassignFailureReason': FieldValue.delete(),
        'needsReassign': true,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('รอเพิ่ม 15 นาที ระบบจะหาไรเดอร์ให้ใหม่'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกการรอไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelWithoutRefund({
    required String cancelReason,
    required String customerChoiceField,
    required String customerChoiceValue,
    required String successMessage,
  }) async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await widget.firestore.collection('orders').doc(widget.orderId).set({
        'status': 'cancelled',
        'statusLabel': 'ยกเลิกออเดอร์',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': uid,
        'cancelReason': cancelReason,
        customerChoiceField: customerChoiceValue,
        'needsReassign': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ยกเลิกออเดอร์ไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestRefund() async {
    if (_busy) return;

    final refundInfo = await _showRefundAccountDialog(context);
    if (refundInfo == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await widget.firestore.collection('orders').doc(widget.orderId).set({
        'status': 'refund',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': 'no_rider_available_refund_requested',
        'refundRequested': true,
        'refundRequestedAt': FieldValue.serverTimestamp(),
        'refundRequestedBy': uid,
        'refundStatus': 'requested',
        ...refundInfo,
        'customerNoRiderChoice': 'refund',
        'needsReassign': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ส่งคำขอคืนเงินแล้ว ทีมงานจะดำเนินการให้'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ส่งคำขอคืนเงินไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleNoRiderSecondaryAction() async {
    if (_orderCanRequestRefund(widget.data)) {
      await _requestRefund();
      return;
    }

    await _cancelWithoutRefund(
      cancelReason: 'no_rider_available_customer_cancelled',
      customerChoiceField: 'customerNoRiderChoice',
      customerChoiceValue: 'cancel',
      successMessage: 'ยกเลิกออเดอร์แล้ว',
    );
  }

  bool get _canRequestRefund => _orderCanRequestRefund(widget.data);

  @override
  Widget build(BuildContext context) {
    if (!_isStale) return const SizedBox.shrink();

    final waiting = _isWaiting;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFB923C)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: Color(0xFFEA580C),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  waiting
                      ? 'กำลังรอไรเดอร์ใหม่ ระบบจะลองหาให้ภายใน 15 นาที'
                      : 'ยังไม่มีไรเดอร์รับงานภายใน 15 นาที',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9A3412),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            waiting
                ? (_canRequestRefund
                      ? 'หากยังไม่ได้ไรเดอร์ภายในเวลาที่กำหนด คุณสามารถขอคืนเงินได้'
                      : 'หากยังไม่ได้ไรเดอร์ภายในเวลาที่กำหนด คุณสามารถยกเลิกออเดอร์ได้')
                : (_canRequestRefund
                      ? 'คุณสามารถเลือกรอเพิ่มอีก 15 นาที หรือขอคืนเงินได้'
                      : 'คุณสามารถเลือกรอเพิ่มอีก 15 นาที หรือยกเลิกออเดอร์ได้'),
            style: const TextStyle(color: Color(0xFF7C2D12), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || waiting ? null : _wait15Min,
                  icon: const Icon(Icons.timer_outlined),
                  label: Text(waiting ? 'รออยู่...' : 'รออีก 15 นาที'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                  ),
                  onPressed: _busy ? null : _handleNoRiderSecondaryAction,
                  icon: Icon(
                    _canRequestRefund
                        ? Icons.payments_outlined
                        : Icons.cancel_outlined,
                  ),
                  label: Text(
                    _canRequestRefund ? 'ขอคืนเงิน' : 'ยกเลิกออเดอร์',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AwaitingShopDecisionBanner extends StatefulWidget {
  const _AwaitingShopDecisionBanner({
    required this.orderId,
    required this.data,
    required this.firestore,
  });

  final String orderId;
  final Map<String, dynamic> data;
  final FirebaseFirestore firestore;

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

  String? _currentUserUidOrNull() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _wait15Min() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final until = DateTime.now().add(_customerExtraWaitDuration);
      await widget.firestore.collection('orders').doc(widget.orderId).set({
        'status': 'accepted',
        'customerShopWaitUntil': Timestamp.fromDate(until),
        'customerShopWaitRequestedAt': FieldValue.serverTimestamp(),
        'customerShopChoice': 'wait_15_min',
        'shopDecisionStatus': FieldValue.delete(),
        'shopRejectedAt': FieldValue.delete(),
        'shopRejectedBy': FieldValue.delete(),
        'cancelReason': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('รอเพิ่ม 15 นาที ร้านค้าจะเห็นออเดอร์นี้อีกครั้ง'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกการรอไม่สำเร็จ: $e')));
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
      final currentUid = _currentUserUidOrNull();
      final cancelReason = _shopRejected
          ? 'customer_cancelled_after_shop_rejected'
          : 'customer_cancelled_after_shop_no_response';
      final update = <String, dynamic>{
        'status': 'cancelled',
        'statusLabel': 'ยกเลิกออเดอร์',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': currentUid,
        'cancelReason': cancelReason,
        'customerShopChoice': 'cancel',
        'customerCancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (refundInfo != null) {
        update.addAll({
          'refundRequested': true,
          'refundRequestedAt': FieldValue.serverTimestamp(),
          'refundRequestedBy': currentUid,
          'refundStatus': 'requested',
          ...refundInfo,
        });
      }

      await widget.firestore
          .collection('orders')
          .doc(widget.orderId)
          .set(update, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ยกเลิกออเดอร์แล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ยกเลิกออเดอร์ไม่สำเร็จ: $e')));
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
                      ? 'กำลังรอร้านค้าอีก 15 นาที'
                      : rejected
                      ? 'ร้านค้าปฏิเสธออเดอร์นี้'
                      : 'ร้านค้ายังไม่รับออเดอร์หลังไรเดอร์รับงานแล้ว',
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
                ? 'หากร้านค้ายังไม่รับงานภายในเวลาที่กำหนด คุณสามารถยกเลิกออเดอร์ได้'
                : (_canRequestRefund
                      ? 'คุณสามารถเลือกรออีก 15 นาที หรือยกเลิกออเดอร์และขอคืนเงินได้'
                      : 'คุณสามารถเลือกรออีก 15 นาที หรือยกเลิกออเดอร์นี้ได้'),
            style: const TextStyle(color: Color(0xFF78350F), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || waiting ? null : _wait15Min,
                  icon: const Icon(Icons.timer_outlined),
                  label: Text(waiting ? 'รออยู่...' : 'รออีก 15 นาที'),
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
                  label: const Text('ยกเลิกออเดอร์'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductHistoryLine {
  const _ProductHistoryLine({
    required this.name,
    required this.quantity,
    this.unitPrice,
    this.lineTotal,
    this.imageUrl,
    this.toppingsLabel,
  });

  final String name;
  final int quantity;
  final num? unitPrice;
  final num? lineTotal;
  final String? imageUrl;
  final String? toppingsLabel;
}

class _ProductHistoryOrderGroup {
  const _ProductHistoryOrderGroup({
    required this.orderId,
    required this.orderCode,
    required this.shopName,
    required this.orderedAt,
    required this.products,
    required this.statusLabel,
    required this.isArchived,
  });

  final String orderId;
  final String? orderCode;
  final String shopName;
  final DateTime? orderedAt;
  final List<_ProductHistoryLine> products;
  final String statusLabel;
  final bool isArchived;
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

int _roadmapReadQuantity(dynamic value) {
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

String? _roadmapReadToppingsLabel(dynamic rawToppings) {
  if (rawToppings is! List) {
    return null;
  }

  final labels = rawToppings
      .map((item) {
        if (item is Map) {
          return _roadmapReadTrimmedString(
            item['name'],
            item['label'],
            item['title'],
          );
        }
        return item?.toString().trim();
      })
      .whereType<String>()
      .where((label) => label.isNotEmpty)
      .toList(growable: false);

  if (labels.isEmpty) {
    return null;
  }
  return labels.join(', ');
}

List<_ProductHistoryLine> _readProductHistoryLines(Map<String, dynamic> data) {
  final rawProducts = data['products'];
  if (rawProducts is! List) {
    return const <_ProductHistoryLine>[];
  }

  final results = <_ProductHistoryLine>[];
  for (final rawProduct in rawProducts) {
    if (rawProduct is! Map) {
      continue;
    }

    final productMap = Map<String, dynamic>.from(rawProduct);
    final name = _roadmapReadTrimmedString(
      productMap['name'],
      productMap['productName'],
      productMap['title'],
    );
    if (name == null) {
      continue;
    }

    results.add(
      _ProductHistoryLine(
        name: name,
        quantity: _roadmapReadQuantity(productMap['quantity']),
        unitPrice: productMap['unitPrice'] as num?,
        lineTotal: productMap['lineTotal'] as num?,
        imageUrl: _roadmapReadTrimmedString(
          productMap['imageUrl'],
          productMap['productImage'],
          productMap['photoUrl'],
        ),
        toppingsLabel: _roadmapReadToppingsLabel(
          productMap['selectedToppings'],
        ),
      ),
    );
  }

  return results;
}

DateTime? _readOrderCreatedAt(Map<String, dynamic> data) {
  final createdAt = data['createdAt'];
  if (createdAt is Timestamp) {
    return createdAt.toDate();
  }
  if (createdAt is DateTime) {
    return createdAt;
  }
  return null;
}

Future<List<_ProductHistoryOrderGroup>> _loadCustomerProductHistory({
  required FirebaseFirestore firestore,
  required String customerId,
}) async {
  final snapshot = await firestore
      .collection('orders')
      .where('customerId', isEqualTo: customerId)
      .get();

  final groups = <_ProductHistoryOrderGroup>[];
  for (final doc in snapshot.docs) {
    final data = doc.data();
    if (_isTravelPassengerOrder(data)) {
      continue;
    }

    final products = _readProductHistoryLines(data);
    if (products.isEmpty) {
      continue;
    }

    final shopName = (data['shopName'] as String?)?.trim();
    groups.add(
      _ProductHistoryOrderGroup(
        orderId: doc.id,
        orderCode: (data['orderCode'] as String?)?.trim(),
        shopName: shopName?.isNotEmpty == true ? shopName! : 'ร้านค้า',
        orderedAt: _readOrderCreatedAt(data),
        products: products,
        statusLabel: _readOrderStatusLabel(data),
        isArchived: _isArchivedRoadmapOrder(data),
      ),
    );
  }

  groups.sort((a, b) {
    final aMs = a.orderedAt?.millisecondsSinceEpoch ?? 0;
    final bMs = b.orderedAt?.millisecondsSinceEpoch ?? 0;
    return bMs.compareTo(aMs);
  });

  return groups;
}

void _showOrderProductHistorySheet({
  required BuildContext context,
  required FirebaseFirestore firestore,
}) {
  final customerId = FirebaseAuth.instance.currentUser?.uid;
  if (customerId == null || customerId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('กรุณาเข้าสู่ระบบเพื่อดูประวัติสินค้า')),
    );
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return _OrderProductHistorySheet(
            firestore: firestore,
            customerId: customerId,
            scrollController: scrollController,
          );
        },
      );
    },
  );
}

class _OrderProductHistorySheet extends StatefulWidget {
  const _OrderProductHistorySheet({
    required this.firestore,
    required this.customerId,
    required this.scrollController,
  });

  final FirebaseFirestore firestore;
  final String customerId;
  final ScrollController scrollController;

  @override
  State<_OrderProductHistorySheet> createState() =>
      _OrderProductHistorySheetState();
}

class _OrderProductHistorySheetState extends State<_OrderProductHistorySheet> {
  late final Future<List<_ProductHistoryOrderGroup>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadCustomerProductHistory(
      firestore: widget.firestore,
      customerId: widget.customerId,
    );
  }

  String _formatOrderedAt(DateTime? value) {
    if (value == null) {
      return '-';
    }
    return DateFormat('d MMM y, HH:mm').format(value);
  }

  String _formatPrice(num? value) {
    if (value == null) {
      return '-';
    }
    return 'THB ${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ประวัติออเดอร์',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'รวมออเดอร์ที่ยกเลิกและสินค้าที่เคยสั่ง',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<_ProductHistoryOrderGroup>>(
              future: _historyFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'โหลดประวัติสินค้าไม่สำเร็จ: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final groups =
                    snapshot.data ?? const <_ProductHistoryOrderGroup>[];
                if (groups.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('ยังไม่มีประวัติสินค้า'),
                    ),
                  );
                }

                return ListView.separated(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final orderLabel = group.orderCode?.isNotEmpty == true
                        ? group.orderCode!
                        : group.orderId;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Order $orderLabel',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: group.isArchived
                                      ? const Color(0xFFFEE2E2)
                                      : const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  group.statusLabel,
                                  style: TextStyle(
                                    color: group.isArchived
                                        ? const Color(0xFFB91C1C)
                                        : const Color(0xFF166534),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            group.shopName,
                            style: const TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatOrderedAt(group.orderedAt),
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (
                            var productIndex = 0;
                            productIndex < group.products.length;
                            productIndex++
                          ) ...[
                            if (productIndex > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(height: 1),
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ProductHistoryThumb(
                                  imageUrl:
                                      group.products[productIndex].imageUrl,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group.products[productIndex].name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        group.products[productIndex].quantity >
                                                0
                                            ? '${group.products[productIndex].quantity} ชิ้น'
                                            : '-',
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (group
                                              .products[productIndex]
                                              .toppingsLabel !=
                                          null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          group
                                              .products[productIndex]
                                              .toppingsLabel!,
                                          style: const TextStyle(
                                            color: Color(0xFF9CA3AF),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Text(
                                  _formatPrice(
                                    group.products[productIndex].lineTotal ??
                                        group.products[productIndex].unitPrice,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductHistoryThumb extends StatelessWidget {
  const _ProductHistoryThumb({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedAppImage(
        imageUrl: imageUrl,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        lightweight: true,
        borderRadius: BorderRadius.circular(10),
        errorWidget: Container(
          width: 44,
          height: 44,
          color: const Color(0xFFF3F4F6),
          child: const Icon(
            Icons.fastfood_outlined,
            size: 20,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }
}
