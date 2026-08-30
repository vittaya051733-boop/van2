import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/promotion_models.dart';
import '../services/locale_service.dart';
import '../services/user_coupon_wallet_service.dart';

class ClaimableCouponStrip extends StatelessWidget {
  const ClaimableCouponStrip({
    super.key,
    required this.coupons,
    required this.claimedCouponIds,
    this.onClaimed,
  });

  final List<ClaimableCouponOffer> coupons;
  final Set<String> claimedCouponIds;
  final VoidCallback? onClaimed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    final inlineCoupons = coupons
        .where((coupon) => coupon.showsInline)
        .toList(growable: false);
    if (inlineCoupons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            L10n.specialCoupons,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: inlineCoupons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final coupon = inlineCoupons[index];
              final claimed = claimedCouponIds.contains(coupon.id);
              return _ClaimableCouponCard(
                coupon: coupon,
                claimed: claimed,
                onClaimed: onClaimed,
              );
            },
          ),
        ),
      ],
    );
      },
    );
  }
}

class _ClaimableCouponCard extends StatefulWidget {
  const _ClaimableCouponCard({
    required this.coupon,
    required this.claimed,
    this.onClaimed,
  });

  final ClaimableCouponOffer coupon;
  final bool claimed;
  final VoidCallback? onClaimed;

  @override
  State<_ClaimableCouponCard> createState() => _ClaimableCouponCardState();
}

class _ClaimableCouponCardState extends State<_ClaimableCouponCard> {
  bool _claiming = false;

  Future<void> _claim() async {
    if (widget.claimed || _claiming) {
      return;
    }
    setState(() => _claiming = true);
    try {
      final result = await UserCouponWalletService.instance
          .claimCoupon(widget.coupon.id);
      if (!mounted) {
        return;
      }
      final message = result.alreadyClaimed
          ? L10n.couponAlreadyClaimedShort
          : L10n.couponSavedToMyCoupons;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
      widget.onClaimed?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.claimCouponFailed(error)),
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
    final coupon = widget.coupon;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFE0B2)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 72,
            child: coupon.imageUrl.isNotEmpty
                ? Image.network(
                    coupon.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imageFallback(),
                  )
                : _imageFallback(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    coupon.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    coupon.discountSummary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFE55A00),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: widget.claimed
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              L10n.claimedBadge,
                              style: const TextStyle(
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : TextButton(
                            onPressed: _claiming ? null : _claim,
                            child: _claiming
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(coupon.ctaText),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageFallback() {
    return Container(
      color: const Color(0xFFFFF7ED),
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_offer_rounded,
        color: Color(0xFFE55A00),
      ),
    );
  }
}
