import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'call_screen.dart';
import 'chat_room_screen.dart';
import 'models/user_profile.dart';
import 'services/notification_service.dart';
import 'widgets/cached_app_image.dart';

const double _kRoadmapProductCarouselHeight = 128;

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
      body: uniqueOrderIds.isNotEmpty
          ? _RoadmapList(orderIds: uniqueOrderIds, firestore: firestore)
          : _RecentCustomerRoadmapList(
              uid: FirebaseAuth.instance.currentUser?.uid,
              firestore: firestore,
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

class _RecentCustomerRoadmapList extends StatelessWidget {
  const _RecentCustomerRoadmapList({
    required this.uid,
    required this.firestore,
  });

  final String? uid;
  final FirebaseFirestore firestore;

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

        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('ยังไม่มีออเดอร์สำหรับแสดงโรดแมป'),
            ),
          );
        }

        docs.sort((a, b) {
          final aTs = a.data()['createdAt'];
          final bTs = b.data()['createdAt'];
          final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
          final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
          return bMs.compareTo(aMs);
        });

        final orderIds = docs.map((doc) => doc.id).toList(growable: false);
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
                    child: Image.network(
                      deliveryProofImageUrl,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 120,
                          color: const Color(0xFFF3F4F6),
                          alignment: Alignment.center,
                          child: const Text('โหลดรูปยืนยันไม่สำเร็จ'),
                        );
                      },
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
    required this.name,
    required this.imageUrl,
    required this.quantity,
  });

  final String name;
  final String? imageUrl;
  final int quantity;
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
        FilledButton(
          onPressed: _submit,
          child: const Text('ยืนยันคืนเงิน'),
        ),
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
                  label: Text(_canRequestRefund ? 'ขอคืนเงิน' : 'ยกเลิกออเดอร์'),
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
  });

  final String orderId;
  final String? orderCode;
  final String shopName;
  final DateTime? orderedAt;
  final List<_ProductHistoryLine> products;
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

String? _roadmapReadTrimmedString(dynamic first, dynamic second, dynamic third) {
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
        toppingsLabel: _roadmapReadToppingsLabel(productMap['selectedToppings']),
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
                        'ประวัติสินค้า',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'สินค้าที่เคยสั่งทั้งหมด',
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
                          Text(
                            'Order $orderLabel',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
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
                          for (var productIndex = 0;
                              productIndex < group.products.length;
                              productIndex++) ...[
                            if (productIndex > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(height: 1),
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ProductHistoryThumb(
                                  imageUrl: group.products[productIndex].imageUrl,
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
                                        group.products[productIndex].quantity > 0
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
