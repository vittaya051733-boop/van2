import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'models/omise_payment_channel.dart';
import 'widgets/payment_brand_strip.dart';
import 'widgets/payment_checkout_sheet.dart';

typedef TravelConfirmCashOnDelivery = Future<List<String>> Function();
typedef TravelSubmitOmisePayment = Future<List<String>> Function(
  OmisePaymentChannel channel,
);
typedef TravelOrderCompleted = Future<void> Function(List<String> orderIds);

Future<void> showTravelPaymentFlow({
  required BuildContext context,
  required double grandTotal,
  required String pickupLabel,
  required String destinationLabel,
  required double distanceKm,
  String? vehicleTypeLabel,
  String? scheduleLabel,
  required TravelConfirmCashOnDelivery? onConfirmCashOnDelivery,
  required TravelSubmitOmisePayment? onSubmitOmisePayment,
  required TravelOrderCompleted onOrderCompleted,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _TravelPaymentSheet(
        grandTotal: grandTotal,
        pickupLabel: pickupLabel,
        destinationLabel: destinationLabel,
        distanceKm: distanceKm,
        vehicleTypeLabel: vehicleTypeLabel,
        scheduleLabel: scheduleLabel,
        onConfirmCashOnDelivery: onConfirmCashOnDelivery,
        onSubmitOmisePayment: onSubmitOmisePayment,
        onOrderCompleted: onOrderCompleted,
      );
    },
  );
}

class _TravelPaymentSheet extends StatefulWidget {
  const _TravelPaymentSheet({
    required this.grandTotal,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.distanceKm,
    required this.vehicleTypeLabel,
    required this.scheduleLabel,
    required this.onConfirmCashOnDelivery,
    required this.onSubmitOmisePayment,
    required this.onOrderCompleted,
  });

  final double grandTotal;
  final String pickupLabel;
  final String destinationLabel;
  final double distanceKm;
  final String? vehicleTypeLabel;
  final String? scheduleLabel;
  final TravelConfirmCashOnDelivery? onConfirmCashOnDelivery;
  final TravelSubmitOmisePayment? onSubmitOmisePayment;
  final TravelOrderCompleted onOrderCompleted;

  @override
  State<_TravelPaymentSheet> createState() => _TravelPaymentSheetState();
}

class _TravelPaymentSheetState extends State<_TravelPaymentSheet> {
  bool _isProcessing = false;

  String _formatDistanceKm(double value) {
    return L10n.distanceKmOrMeters(value);
  }

  Future<void> _openPaymentOptions() async {
    if (_isProcessing) {
      return;
    }
    setState(() => _isProcessing = true);

    var checkoutStarted = false;
    try {
      await showPaymentCheckoutSheet(
        context: context,
        grandTotal: widget.grandTotal,
        subtitle: L10n.travelRouteSubtitle(
          widget.pickupLabel,
          widget.destinationLabel,
        ),
        onCashOnDelivery: widget.onConfirmCashOnDelivery == null
            ? null
            : () async {
                checkoutStarted = true;
                try {
                  final orderIds = await widget.onConfirmCashOnDelivery!.call();
                  if (orderIds.isEmpty) {
                    throw Exception(L10n.createTravelOrderFailed);
                  }
                  await widget.onOrderCompleted(orderIds);
                } finally {
                  if (mounted) {
                    setState(() => _isProcessing = false);
                  }
                }
              },
        onOmisePayment: (channel) async {
          checkoutStarted = true;
          try {
            final callback = widget.onSubmitOmisePayment;
            if (callback == null) {
              throw Exception(L10n.omisePaymentNotReady);
            }
            final orderIds = await callback(channel);
            if (orderIds.isEmpty) {
              throw Exception(L10n.createTravelOrderFailed);
            }
            await widget.onOrderCompleted(orderIds);
          } finally {
            if (mounted) {
              setState(() => _isProcessing = false);
            }
          }
        },
      );
    } finally {
      if (mounted && !checkoutStarted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBF6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D3D1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              L10n.travelPaymentTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.travelPaymentSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              L10n.amountDueBaht(widget.grandTotal),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFFE55A00),
              ),
            ),
            const SizedBox(height: 16),
            _TravelOrderSummaryCard(
              pickupLabel: widget.pickupLabel,
              destinationLabel: widget.destinationLabel,
              distanceLabel: _formatDistanceKm(widget.distanceKm),
              totalLabel: '฿${widget.grandTotal.toStringAsFixed(2)}',
              vehicleTypeLabel: widget.vehicleTypeLabel,
              scheduleLabel: widget.scheduleLabel,
            ),
            const SizedBox(height: 16),
            const PaymentBrandStrip(compact: true),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isProcessing ? null : _openPaymentOptions,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFFE55A00),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        L10n.pay,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelOrderSummaryCard extends StatelessWidget {
  const _TravelOrderSummaryCard({
    required this.pickupLabel,
    required this.destinationLabel,
    required this.distanceLabel,
    required this.totalLabel,
    required this.vehicleTypeLabel,
    required this.scheduleLabel,
  });

  final String pickupLabel;
  final String destinationLabel;
  final String distanceLabel;
  final String totalLabel;
  final String? vehicleTypeLabel;
  final String? scheduleLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SummaryRow(label: L10n.pickupPoint, value: pickupLabel),
          const SizedBox(height: 8),
          _SummaryRow(label: L10n.destination, value: destinationLabel),
          const SizedBox(height: 8),
          _SummaryRow(label: L10n.distance, value: distanceLabel),
          if (vehicleTypeLabel != null && vehicleTypeLabel!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _SummaryRow(label: L10n.vehicleType, value: vehicleTypeLabel!),
          ],
          if (scheduleLabel != null && scheduleLabel!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _SummaryRow(label: L10n.scheduleTime, value: scheduleLabel!),
          ],
          const SizedBox(height: 8),
          _SummaryRow(
            label: L10n.total,
            value: totalLabel,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: emphasized
                ? Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFE55A00),
                  )
                : Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ),
      ],
    );
  }
}
