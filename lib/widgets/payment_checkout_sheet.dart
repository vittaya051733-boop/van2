import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/payment_gateway_config.dart';
import '../l10n/l10n.dart';
import '../models/omise_payment_channel.dart';
import '../services/locale_service.dart';
import '../services/omise_payment_service.dart';
import 'payment_brand_strip.dart';

typedef PaymentCashOnDeliveryHandler = Future<void> Function();
typedef PaymentOmiseHandler = Future<void> Function(OmisePaymentChannel channel);
typedef PaymentEmbeddedPromptPayHandler = Future<void> Function();

Future<void> showPaymentCheckoutSheet({
  required BuildContext context,
  required double grandTotal,
  required PaymentCashOnDeliveryHandler? onCashOnDelivery,
  PaymentOmiseHandler? onOmisePayment,
  PaymentEmbeddedPromptPayHandler? onEmbeddedPromptPayScan,
  String? subtitle,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _PaymentCheckoutSheet(
        grandTotal: grandTotal,
        subtitle: subtitle,
        onCashOnDelivery: onCashOnDelivery,
        onOmisePayment: onOmisePayment,
        onEmbeddedPromptPayScan: onEmbeddedPromptPayScan,
      );
    },
  );
}

class _PaymentCheckoutSheet extends StatefulWidget {
  const _PaymentCheckoutSheet({
    required this.grandTotal,
    required this.subtitle,
    required this.onCashOnDelivery,
    required this.onOmisePayment,
    required this.onEmbeddedPromptPayScan,
  });

  final double grandTotal;
  final String? subtitle;
  final PaymentCashOnDeliveryHandler? onCashOnDelivery;
  final PaymentOmiseHandler? onOmisePayment;
  final PaymentEmbeddedPromptPayHandler? onEmbeddedPromptPayScan;

  @override
  State<_PaymentCheckoutSheet> createState() => _PaymentCheckoutSheetState();
}

class _PaymentCheckoutSheetState extends State<_PaymentCheckoutSheet> {
  bool _isProcessing = false;
  bool _runLock = false;

  Future<void> _run(
    Future<void> Function() action, {
    bool closeBeforeAction = true,
  }) async {
    if (_runLock || _isProcessing) {
      return;
    }
    _runLock = true;
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      if (closeBeforeAction) {
        navigator.pop();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      await action();
      if (!closeBeforeAction && mounted) {
        navigator.pop();
      }
    } on PaymentCheckoutCancelled {
      debugPrint('[payment] checkout cancelled by user');
    } catch (error, stackTrace) {
      debugPrint('[payment] checkout failed: $error\n$stackTrace');
      messenger.showSnackBar(
        SnackBar(content: Text(L10n.paymentFailed(error))),
      );
    } finally {
      _runLock = false;
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                L10n.paymentTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                L10n.paymentTotalBaht(widget.grandTotal.toStringAsFixed(2)),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFE55A00),
                ),
              ),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  widget.subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF374151),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              PaymentBrandStrip(
                showBanner: true,
                promptPayOnly: !PaymentGatewayConfig.omiseGatewayEnabled,
              ),
              const SizedBox(height: 16),
              if (widget.onCashOnDelivery != null)
                _PaymentOptionTile(
                  title: L10n.codTitle,
                  subtitle: L10n.codSubtitle,
                  icon: Icons.local_shipping_outlined,
                  enabled: !_isProcessing,
                  onTap: () => _run(
                    widget.onCashOnDelivery!,
                    closeBeforeAction: false,
                  ),
                ),
              if (PaymentGatewayConfig.embeddedPromptPayScanEnabled &&
                  widget.onEmbeddedPromptPayScan != null)
                _PaymentOptionTile(
                  title: L10n.scanPromptPay,
                  subtitle: L10n.scanPromptPayHint,
                  logoAssets: const <String>[
                    'assets/payment_logos/promptpay.png',
                  ],
                  enabled: !_isProcessing,
                  onTap: () => _run(
                    widget.onEmbeddedPromptPayScan!,
                    closeBeforeAction: false,
                  ),
                ),
              if (PaymentGatewayConfig.omiseGatewayEnabled &&
                  widget.onOmisePayment != null)
                for (final channel in OmisePaymentChannel.values)
                  _PaymentOptionTile(
                    title: channel.label,
                    subtitle: _channelSubtitle(channel),
                    logoAssets: channel.tileLogoAssets,
                    enabled: !_isProcessing,
                    onTap: () => _run(
                      () => widget.onOmisePayment!(channel),
                      closeBeforeAction: false,
                    ),
                  ),
              if (_isProcessing) ...<Widget>[
                const SizedBox(height: 12),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  String _channelSubtitle(OmisePaymentChannel channel) {
    switch (channel) {
      case OmisePaymentChannel.promptPay:
        return L10n.omiseScanPromptPayQr;
      case OmisePaymentChannel.card:
        return 'Visa, Mastercard, JCB';
      case OmisePaymentChannel.mobileBanking:
        return L10n.omiseMobileBankTransfer;
      case OmisePaymentChannel.trueMoney:
        return L10n.omiseTrueMoneyOtpConfirm;
    }
  }

}

class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.icon,
    this.logoAssets,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final IconData? icon;
  final List<String>? logoAssets;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                if (logoAssets != null && logoAssets!.isNotEmpty)
                  _PaymentOptionLogoGroup(assets: logoAssets!)
                else
                  Icon(icon ?? Icons.payment, color: const Color(0xFF374151)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentOptionLogoGroup extends StatelessWidget {
  const _PaymentOptionLogoGroup({required this.assets});

  final List<String> assets;

  @override
  Widget build(BuildContext context) {
    if (assets.length == 1) {
      return PaymentBrandLogo(
        asset: assets.first,
        height: 30,
        showBorder: false,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < assets.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(width: 4),
          PaymentBrandLogo(asset: assets[index], height: 18),
        ],
      ],
    );
  }
}
