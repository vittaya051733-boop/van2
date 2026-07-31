import 'package:flutter/material.dart';

import 'payment_brand_strip.dart';

/// Supported card networks for Omise checkout (Visa, Mastercard, JCB).
class CardBrandStrip extends StatelessWidget {
  const CardBrandStrip({super.key});

  static const List<String> logoAssets = PaymentBrandStrip.cardLogoAssets;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (final asset in logoAssets) ...<Widget>[
          PaymentBrandLogo(asset: asset, height: 28, showBorder: false),
          if (asset != logoAssets.last) const SizedBox(width: 16),
        ],
      ],
    );
  }
}
