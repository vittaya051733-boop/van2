import 'package:flutter/material.dart';

import '../models/promotion_models.dart';

class PromotionCartPanel extends StatelessWidget {
  const PromotionCartPanel({
    super.key,
    required this.config,
    required this.discounts,
    required this.couponController,
    required this.appliedCouponCode,
    required this.isApplyingCoupon,
    required this.onApplyCoupon,
    required this.onClearCoupon,
  });

  final PromotionDisplayConfig config;
  final CartDiscountSnapshot discounts;
  final TextEditingController couponController;
  final String? appliedCouponCode;
  final bool isApplyingCoupon;
  final VoidCallback onApplyCoupon;
  final VoidCallback onClearCoupon;

  static const Color _accent = Color(0xFFE55A00);
  static const Color _surface = Color(0xFFFFF7ED);
  static const Color _border = Color(0xFFFFE0B2);

  @override
  Widget build(BuildContext context) {
    if (config.isBannerOnlyCart) {
      return _buildCouponOnly(context);
    }

    if (config.isCompactCart) {
      return _buildCompact(context);
    }

    return _buildExpanded(context);
  }

  Widget _buildExpanded(BuildContext context) {
    final promoLines = discounts.discountLines
        .where((line) => line.kind == 'promotion')
        .toList(growable: false);
    final couponLines = discounts.discountLines
        .where((line) => line.kind == 'coupon')
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (config.showAutoPromotionsInCart) ...<Widget>[
          _sectionTitle(context, 'โปรที่ใช้ได้'),
          const SizedBox(height: 8),
          if (promoLines.isNotEmpty)
            for (final line in promoLines)
              _appliedPromoTile(context, line)
          else if (discounts.nearMissPromotions.isNotEmpty)
            for (final near in discounts.nearMissPromotions)
              _nearMissTile(context, near)
          else
            _infoTile(context, 'ยังไม่มีโปรที่ใช้ได้ในตะกร้านี้'),
          const SizedBox(height: 12),
        ],
        if (config.showCouponField) ...<Widget>[
          _sectionTitle(context, 'คูปอง'),
          const SizedBox(height: 8),
          _couponField(context),
          if (couponLines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _appliedCouponTile(context, couponLines.first),
            ),
          if (discounts.couponError != null &&
              discounts.couponError!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                discounts.couponError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFDC2626),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (discounts.stackNote != null &&
              discounts.stackNote!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                discounts.stackNote!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB45309),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (config.showCouponField) ...<Widget>[
          _couponField(context),
          if (appliedCouponCode != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'ใช้คูปอง $appliedCouponCode แล้ว',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF15803D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (discounts.couponError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                discounts.couponError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFDC2626),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (discounts.discountTotal > 0)
          Row(
            children: <Widget>[
              Text(
                'ส่วนลดรวม',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '-฿${discounts.discountTotal.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _accent,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCouponOnly(BuildContext context) {
    if (!config.showCouponField) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _couponField(context),
        if (discounts.couponError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              discounts.couponError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFDC2626),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: const Color(0xFF111827),
      ),
    );
  }

  Widget _couponField(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: couponController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'กรอกรหัสคูปอง',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (appliedCouponCode != null)
            IconButton(
              onPressed: isApplyingCoupon ? null : onClearCoupon,
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'ลบคูปอง',
            ),
          FilledButton(
            onPressed: isApplyingCoupon ? null : onApplyCoupon,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              minimumSize: const Size(64, 40),
            ),
            child: isApplyingCoupon
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('ใช้'),
          ),
        ],
      ),
    );
  }

  Widget _appliedPromoTile(BuildContext context, CartDiscountLine line) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded, color: Color(0xFF15803D), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '-฿${line.amount.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _appliedCouponTile(BuildContext context, CartDiscountLine line) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.confirmation_number_rounded,
              color: Color(0xFF15803D), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ใช้ ${line.code ?? line.label} แล้ว',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '-฿${line.amount.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nearMissTile(BuildContext context, NearMissPromotion near) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.local_offer_outlined, color: _accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${near.label} — ขาดอีก ฿${near.shortfall.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class PromotionDiscountBreakdown extends StatelessWidget {
  const PromotionDiscountBreakdown({
    super.key,
    required this.discounts,
  });

  final CartDiscountSnapshot discounts;

  @override
  Widget build(BuildContext context) {
    if (discounts.promotionDiscount <= 0 && discounts.couponDiscount <= 0) {
      return const SizedBox.shrink();
    }

    return Column(
      children: <Widget>[
        if (discounts.promotionDiscount > 0) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Text(
                'ส่วนลดโปร',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              const Spacer(),
              Text(
                '-฿${discounts.promotionDiscount.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFE55A00),
                ),
              ),
            ],
          ),
        ],
        if (discounts.couponDiscount > 0) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Text(
                'ส่วนลดคูปอง',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              const Spacer(),
              Text(
                '-฿${discounts.couponDiscount.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFE55A00),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
