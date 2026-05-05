import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'call_screen.dart';
import 'chat_room_screen.dart';
import 'models/user_profile.dart';
import 'services/notification_service.dart';
import 'widgets/cached_app_image.dart';

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
      appBar: AppBar(
        title: const Text('Roadmap การจัดส่ง'),
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
  const _RecentCustomerRoadmapList({required this.uid, required this.firestore});

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
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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

        final docs = (snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
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
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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
        final total = (data['grandTotal'] as num?) ?? (data['totalPrice'] as num?) ?? 0;
        final driverId = (data['driverId'] as String?)?.trim();
        final shopImageUrl = _readShopImageUrl(data);
        final productEntries = _readProductEntries(data);
        final deliveryProofImageUrl = (data['deliveryProofImageUrl'] as String?)?.trim();
        final deliveryProofMeta = _buildDeliveryProofMeta(data);
        final pickupLabel = isTravelOrder ? _readTravelPickupLabel(data) : null;
        final destinationLabel = isTravelOrder ? _readTravelDestinationLabel(data) : null;
        final travelVehicleLabel = isTravelOrder ? _readTravelVehicleLabel(data) : null;
        final travelScheduleLabel = isTravelOrder ? _readTravelScheduleLabel(data) : null;

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
                    final resolvedShopImageUrl = shopImageSnapshot.data ?? shopImageUrl;

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
                                orderCode?.isNotEmpty == true ? 'Order $orderCode' : 'Order $orderId',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
                  Text('จุดส่ง: ${destinationLabel?.isNotEmpty == true ? destinationLabel : '-'}'),
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
                    height: 126,
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
                if (deliveryProofImageUrl != null && deliveryProofImageUrl.isNotEmpty) ...[
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
                    final canCall = hasRider || (contact?.phone?.isNotEmpty ?? false);

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
                            label: Text(canCall ? 'โทรไรเดอร์' : 'โทรไรเดอร์ไม่ได้'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                _TimelineStepTile(
                  label: 'ระบบค้นหาไรเดอร์ใกล้สุด',
                  status: roadmap.riderSearchStarted,
                ),
                _TimelineStepTile(
                  label: 'แมตช์ไรเดอร์สำเร็จ',
                  status: roadmap.riderMatched,
                ),
                _TimelineStepTile(
                  label: 'ไรเดอร์รับออเดอร์',
                  status: roadmap.riderAccepted,
                ),
                _TimelineStepTile(
                  label: isTravelOrder
                      ? 'ไรเดอร์กำลังไปจุดรับผู้โดยสาร'
                      : 'ไรเดอร์กำลังไปรับสินค้าที่ร้าน',
                  status: roadmap.riderToShop,
                ),
                _TimelineStepTile(
                  label: isTravelOrder ? 'กำลังรอผู้โดยสารขึ้นรถ' : 'ร้านกำลังทำสินค้า',
                  status: roadmap.shopPreparing,
                ),
                _TimelineStepTile(
                  label: isTravelOrder ? 'ไรเดอร์ถึงจุดรับแล้ว' : 'ไรเดอร์สแกนรับสินค้า',
                  status: roadmap.riderScannedPickup,
                ),
                _TimelineStepTile(
                  label: isTravelOrder ? 'กำลังเดินทางไปจุดส่ง' : 'ไรเดอร์กำลังไปส่ง',
                  status: roadmap.delivering,
                ),
                _TimelineStepTile(
                  label: isTravelOrder ? 'ถึงจุดหมายแล้ว' : 'ส่งถึงลูกค้าแล้ว',
                  status: roadmap.delivered,
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
        final query = await productCollection.where(field, isEqualTo: shopId).limit(1).get();
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
        final productShopId = _readFirstNonEmptyValue(productMap, _shopLookupFields);
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

  String? _readFirstNonEmptyValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static const List<String> _shopLookupFields = <String>[
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

  Future<_RiderContactState> _loadRiderContactState(Map<String, dynamic> data) async {
    final driverId = (data['driverId'] as String?)?.trim();
    final fallbackName = ((data['driverName'] as String?)?.trim().isNotEmpty ?? false)
        ? (data['driverName'] as String).trim()
        : 'ไรเดอร์';
    final fallbackPhone = (data['driverPhone'] as String?)?.trim();

    if (driverId == null || driverId.isEmpty) {
      return _RiderContactState(
        profile: null,
        phone: fallbackPhone,
      );
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

    return _RiderContactState(
      profile: profile,
      phone: phone,
    );
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

  Future<void> _callPhone(String phone, ScaffoldMessengerState? messenger) async {
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

        final callee = riderProfile ?? UserProfile(
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
              channelName: (callData['channelId'] as String?) ?? 'call_${caller.uid}_$riderUid',
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
          : (user.email?.trim().isNotEmpty == true ? user.email!.trim() : 'ลูกค้า'),
      phoneNumber: user.phoneNumber,
      photoUrl: user.photoURL,
    );
  }

  _OrderRoadmapState _buildRoadmapState(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim() ?? '';
    final hasDriver = ((data['driverId'] as String?)?.trim().isNotEmpty ?? false);
    final riderSearch = data['riderSearch'];
    final matchedBySearch = riderSearch is Map<String, dynamic>
      ? (riderSearch['matched'] == true)
      : false;
    final hasAcceptedAt = data['acceptedAt'] != null;
    final hasScanned = ((data['scannedByDriverId'] as String?)?.trim().isNotEmpty ?? false) ||
        data['scannedAt'] != null;

    final riderSearchStarted = riderSearch is Map<String, dynamic> ||
      status == 'awaiting_rider' ||
      status == 'pending' ||
      status == 'accepted' ||
      status == 'preparing' ||
      status == 'ready' ||
      status == 'delivering' ||
      status == 'delivered';

    final riderMatched = hasDriver ||
      matchedBySearch ||
      status == 'pending' ||
      status == 'accepted' ||
      status == 'preparing' ||
      status == 'ready' ||
      status == 'delivering' ||
      status == 'delivered';

    final riderAccepted = hasAcceptedAt ||
        status == 'accepted' ||
        status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final riderToShop = status == 'accepted' ||
        status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final shopPreparing = status == 'preparing' ||
        status == 'ready' ||
        status == 'delivering' ||
        status == 'delivered';

    final riderScannedPickup = hasScanned ||
        status == 'delivering' ||
        status == 'delivered';

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
        errorWidget: const Icon(Icons.storefront_outlined, color: Color(0xFF9CA3AF)),
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
              child: const Icon(Icons.image_not_supported_outlined, color: Color(0xFF9CA3AF)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quantity > 0 ? '$quantity ชิ้น' : '-',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
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
  const _RiderContactState({
    required this.profile,
    required this.phone,
  });

  final UserProfile? profile;
  final String? phone;
}

class _TimelineStepTile extends StatelessWidget {
  const _TimelineStepTile({
    required this.label,
    required this.status,
    this.isLast = false,
  });

  final String label;
  final bool status;
  final bool isLast;

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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              style: TextStyle(
                color: status ? const Color(0xFF111827) : const Color(0xFF6B7280),
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
