import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/promotion_models.dart';

class UserCouponWalletService {
  UserCouponWalletService._();

  static final UserCouponWalletService instance = UserCouponWalletService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Stream<List<ClaimedCoupon>> watchActiveWallet(String? userId) {
    if (userId == null || userId.isEmpty) {
      return Stream<List<ClaimedCoupon>>.value(const <ClaimedCoupon>[]);
    }

    return _firestore
        .collection('customer_users')
        .doc(userId)
        .collection('claimed_coupons')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final coupons = snapshot.docs
          .map((doc) => ClaimedCoupon.fromFirestore(doc.id, doc.data()))
          .where((coupon) => coupon.isActive)
          .toList(growable: false);
      coupons.sort((a, b) {
        final aTime = a.claimedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.claimedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return coupons;
    });
  }

  Stream<Set<String>> watchClaimedCouponIds(String? userId) {
    if (userId == null || userId.isEmpty) {
      return Stream<Set<String>>.value(<String>{});
    }

    return _firestore
        .collection('customer_users')
        .doc(userId)
        .collection('claimed_coupons')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) => doc.id).toSet(),
        );
  }

  Future<ClaimCouponResult> claimCoupon(String couponId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('กรุณาเข้าสู่ระบบก่อนรับคูปอง');
    }

    final callable = _functions.httpsCallable('claimCoupon');
    final response = await callable.call(<String, dynamic>{
      'couponId': couponId,
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    return ClaimCouponResult.fromPayload(data);
  }
}

class ClaimCouponResult {
  const ClaimCouponResult({
    required this.alreadyClaimed,
    required this.couponId,
    required this.code,
    required this.name,
    required this.shortLabel,
    required this.discountSummary,
    required this.imageUrl,
  });

  final bool alreadyClaimed;
  final String couponId;
  final String code;
  final String name;
  final String shortLabel;
  final String discountSummary;
  final String imageUrl;

  factory ClaimCouponResult.fromPayload(Map<String, dynamic> data) {
    return ClaimCouponResult(
      alreadyClaimed: data['alreadyClaimed'] == true,
      couponId: (data['couponId'] ?? '').toString(),
      code: (data['code'] ?? '').toString(),
      name: (data['name'] ?? 'คูปอง').toString(),
      shortLabel: (data['shortLabel'] ?? data['name'] ?? 'คูปอง').toString(),
      discountSummary: (data['discountSummary'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
    );
  }
}
