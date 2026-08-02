import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/promotion_models.dart';

class ClaimableCouponService {
  ClaimableCouponService._();

  static final ClaimableCouponService instance = ClaimableCouponService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<ClaimableCouponOffer>> watchActiveClaimableCoupons() {
    return _firestore
        .collection('coupons')
        .where('active', isEqualTo: true)
        .limit(40)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final offers = <ClaimableCouponOffer>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final distribution = (data['distribution'] ?? 'manual_code').toString();
        if (distribution != 'self_claim') {
          continue;
        }
        final offer = ClaimableCouponOffer.fromFirestore(doc.id, data);
        if (!offer.active ||
            !offer.isWithinSchedule(now) ||
            offer.isClaimQuotaFull) {
          continue;
        }
        offers.add(offer);
      }
      offers.sort((a, b) => b.priority.compareTo(a.priority));
      return offers;
    });
  }
}
