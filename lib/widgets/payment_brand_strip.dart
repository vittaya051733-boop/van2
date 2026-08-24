import 'package:flutter/material.dart';

class PaymentBrandStrip extends StatelessWidget {
  const PaymentBrandStrip({
    super.key,
    this.compact = false,
    this.showBanner = false,
    this.promptPayOnly = false,
  });

  final bool compact;
  final bool showBanner;
  final bool promptPayOnly;

  static const List<String> cardLogoAssets = <String>[
    'assets/payment_logos/visa.png',
    'assets/payment_logos/mastercard.png',
    'assets/payment_logos/jcb.png',
  ];

  static const List<String> _logoAssets = <String>[
    ...cardLogoAssets,
    'assets/payment_logos/promptpay.png',
    'assets/payment_logos/truemoney.png',
    'assets/payment_logos/mobile_banking.png',
  ];

  static const String bannerAsset =
      'assets/payment_logos/payment_methods_banner.png';

  @override
  Widget build(BuildContext context) {
    if (showBanner && !promptPayOnly) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/payment_logos/payment_methods_banner.png',
          fit: BoxFit.cover,
          width: double.infinity,
          height: compact ? 56 : 72,
          errorBuilder: (context, error, stackTrace) {
            return _LogoRow(compact: compact, promptPayOnly: promptPayOnly);
          },
        ),
      );
    }

    return _LogoRow(compact: compact, promptPayOnly: promptPayOnly);
  }
}

class _LogoRow extends StatelessWidget {
  const _LogoRow({
    required this.compact,
    this.promptPayOnly = false,
  });

  final bool compact;
  final bool promptPayOnly;

  List<String> get _logoAssets {
    if (promptPayOnly) {
      return const <String>['assets/payment_logos/promptpay.png'];
    }
    return PaymentBrandStrip._logoAssets;
  }

  String get _caption {
    if (promptPayOnly) {
      return 'สแกนจ่ายผ่าน PromptPay';
    }
    return 'รองรับ PromptPay, บัตร, Mobile Banking, TrueMoney';
  }

  @override
  Widget build(BuildContext context) {
    final logoHeight = compact ? 22.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!compact)
          Text(
            _caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
            ),
          ),
        if (!compact) const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final asset in _logoAssets) ...<Widget>[
                PaymentBrandLogo(asset: asset, height: logoHeight),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Single payment brand logo — same styling as the banner strip.
class PaymentBrandLogo extends StatelessWidget {
  const PaymentBrandLogo({
    super.key,
    required this.asset,
    required this.height,
    this.showBorder = true,
    this.backgroundColor = Colors.white,
  });

  final String asset;
  final double height;
  final bool showBorder;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          height: height,
          child: const Icon(Icons.payment, size: 18, color: Color(0xFF9CA3AF)),
        );
      },
    );

    if (!showBorder) {
      return SizedBox(height: height, child: image);
    }

    return Container(
      height: height + 8,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: image,
    );
  }
}
