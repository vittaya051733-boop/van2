import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/promotion_models.dart';
import '../services/user_coupon_wallet_service.dart';

typedef CouponWalletApplyCallback = void Function(String couponCode);

Future<void> showMyCouponsSheet(
  BuildContext context, {
  CouponWalletApplyCallback? onApplyToCart,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => MyCouponsScreen(onApplyToCart: onApplyToCart),
    ),
  );
}

class MyCouponsScreen extends StatelessWidget {
  const MyCouponsScreen({super.key, this.onApplyToCart});

  final CouponWalletApplyCallback? onApplyToCart;

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('คูปองของฉัน'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: StreamBuilder<List<ClaimedCoupon>>(
        stream: UserCouponWalletService.instance.watchActiveWallet(userId),
        builder: (context, snapshot) {
          final coupons = snapshot.data ?? const <ClaimedCoupon>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              coupons.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (coupons.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ยังไม่มีคูปอง — กดรับจากหน้าแรกได้เลย',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: coupons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final coupon = coupons[index];
              return _WalletCouponTile(
                coupon: coupon,
                onApplyToCart: onApplyToCart,
              );
            },
          );
        },
      ),
    );
  }
}

class _WalletCouponTile extends StatelessWidget {
  const _WalletCouponTile({
    required this.coupon,
    this.onApplyToCart,
  });

  final ClaimedCoupon coupon;
  final CouponWalletApplyCallback? onApplyToCart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0B2)),
        color: const Color(0xFFFFF7ED),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: coupon.imageUrl.isNotEmpty
                  ? Image.network(
                      coupon.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconFallback(),
                    )
                  : _iconFallback(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  coupon.shortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  coupon.discountSummary.isNotEmpty
                      ? coupon.discountSummary
                      : coupon.name,
                  style: const TextStyle(
                    color: Color(0xFFE55A00),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (coupon.code.isNotEmpty)
                  Text(
                    'โค้ด: ${coupon.code}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (onApplyToCart != null && coupon.code.isNotEmpty)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onApplyToCart!(coupon.code);
              },
              child: const Text('ใช้ในตะกร้า'),
            ),
        ],
      ),
    );
  }

  Widget _iconFallback() {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: const Icon(Icons.local_offer_rounded, color: Color(0xFFE55A00)),
    );
  }
}
