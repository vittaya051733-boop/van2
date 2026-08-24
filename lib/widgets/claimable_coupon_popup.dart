import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/promotion_models.dart';
import '../services/user_coupon_wallet_service.dart';

class ClaimableCouponPopupHost extends StatefulWidget {
  const ClaimableCouponPopupHost({
    super.key,
    required this.coupons,
    required this.claimedCouponIds,
    required this.sessionId,
    this.onClaimed,
  });

  final List<ClaimableCouponOffer> coupons;
  final Set<String> claimedCouponIds;
  final String sessionId;
  final VoidCallback? onClaimed;

  @override
  State<ClaimableCouponPopupHost> createState() =>
      _ClaimableCouponPopupHostState();
}

class _ClaimableCouponPopupHostState extends State<ClaimableCouponPopupHost> {
  bool _checkingDismissals = true;
  ClaimableCouponOffer? _visibleCoupon;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _resolveVisibleCoupon();
  }

  @override
  void didUpdateWidget(covariant ClaimableCouponPopupHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coupons != widget.coupons ||
        oldWidget.claimedCouponIds != widget.claimedCouponIds ||
        oldWidget.sessionId != widget.sessionId) {
      _resolveVisibleCoupon();
    }
  }

  Future<void> _resolveVisibleCoupon() async {
    final popupCoupons = widget.coupons
        .where(
          (coupon) =>
              coupon.showsPopup &&
              !widget.claimedCouponIds.contains(coupon.id),
        )
        .toList(growable: false);

    if (popupCoupons.isEmpty) {
      if (mounted) {
        setState(() {
          _visibleCoupon = null;
          _checkingDismissals = false;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    ClaimableCouponOffer? next;
    for (final coupon in popupCoupons) {
      final dismissed = prefs.getBool(_dismissKey(coupon.id)) ?? false;
      if (!dismissed) {
        next = coupon;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _visibleCoupon = next;
        _checkingDismissals = false;
      });
    }
  }

  String _dismissKey(String couponId) {
    return 'coupon_popup_dismissed_${couponId}_${widget.sessionId}';
  }

  Future<void> _dismiss() async {
    final coupon = _visibleCoupon;
    if (coupon == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissKey(coupon.id), true);
    if (mounted) {
      setState(() => _visibleCoupon = null);
    }
    await _resolveVisibleCoupon();
  }

  Future<void> _claim() async {
    final coupon = _visibleCoupon;
    if (coupon == null || _claiming) {
      return;
    }

    setState(() => _claiming = true);
    try {
      final result =
          await UserCouponWalletService.instance.claimCoupon(coupon.id);
      if (!mounted) {
        return;
      }
      final message = result.alreadyClaimed
          ? 'คุณรับคูปองนี้แล้ว — ดูได้ใน "คูปองของฉัน"'
          : 'เก็บคูปองใน "คูปองของฉัน" แล้ว';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
      widget.onClaimed?.call();
      setState(() => _visibleCoupon = null);
      await _resolveVisibleCoupon();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('รับคูปองไม่สำเร็จ: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _claiming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingDismissals || _visibleCoupon == null) {
      return const SizedBox.shrink();
    }

    final coupon = _visibleCoupon!;
    final imageOnlyPopup =
        coupon.transparentImage && coupon.imageUrl.isNotEmpty;

    if (imageOnlyPopup) {
      return Stack(
        children: <Widget>[
          ModalBarrier(
            color: Colors.black.withValues(alpha: 0.45),
            dismissible: false,
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  GestureDetector(
                    onTap: _claiming ? null : _claim,
                    child: Image.network(
                      coupon.imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _imageFallback(),
                    ),
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: IconButton(
                      onPressed: _dismiss,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  if (_claiming)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x44000000),
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: <Widget>[
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.45),
          dismissible: false,
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: <Widget>[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (coupon.imageUrl.isNotEmpty)
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            coupon.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imageFallback(),
                          ),
                        )
                      else
                        _imageFallback(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: Column(
                          children: <Widget>[
                            Text(
                              coupon.popupTitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              coupon.discountSummary,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(color: const Color(0xFFE55A00)),
                            ),
                            if (coupon.minSubtotal > 0) ...<Widget>[
                              const SizedBox(height: 6),
                              Text(
                                'ขั้นต่ำ ฿${coupon.minSubtotal.toStringAsFixed(0)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _claiming ? null : _claim,
                                child: _claiming
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(coupon.ctaText),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: _dismiss,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.45),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageFallback() {
    return Container(
      height: 160,
      width: double.infinity,
      color: const Color(0xFFFFF7ED),
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_offer_rounded,
        size: 56,
        color: Color(0xFFE55A00),
      ),
    );
  }
}
