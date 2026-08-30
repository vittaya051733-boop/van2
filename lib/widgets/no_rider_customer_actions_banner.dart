import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/customer_order_actions_service.dart';
import '../services/locale_service.dart';
import '../utils/order_no_rider_policy.dart';
import 'order_refund_dialog.dart';

/// Wait / refund actions when no rider accepts (immediate or scheduled travel).
class NoRiderCustomerActionsBanner extends StatefulWidget {
  NoRiderCustomerActionsBanner({
    super.key,
    required this.orderId,
    required this.data,
    required this.firestore,
    CustomerOrderActionsService? orderActions,
  }) : orderActions = orderActions ?? CustomerOrderActionsService.production();

  final String orderId;
  final Map<String, dynamic> data;
  final FirebaseFirestore firestore;
  final CustomerOrderActionsService orderActions;

  @override
  State<NoRiderCustomerActionsBanner> createState() =>
      _NoRiderCustomerActionsBannerState();
}

class _NoRiderCustomerActionsBannerState
    extends State<NoRiderCustomerActionsBanner> {
  Timer? _refreshTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool get _isVisible => OrderNoRiderPolicy.shouldShowNoRiderActions(widget.data);

  bool get _isWaiting => OrderNoRiderPolicy.isCustomerWaiting(widget.data);

  bool get _canRequestRefund => orderCanRequestRefund(widget.data);

  bool get _allowExtraWait => OrderNoRiderPolicy.allowExtraWait(widget.data);

  bool get _isScheduledTravel =>
      OrderNoRiderPolicy.isScheduledTravelOrder(widget.data);

  String get _title {
    if (_isWaiting) {
      return _allowExtraWait
          ? L10n.waitingNewRider15
          : L10n.findingRiderBeforeSchedule;
    }
    if (_isScheduledTravel) {
      return L10n.scheduleTimeNoRider;
    }
    return L10n.noRiderWithin15;
  }

  String get _subtitle {
    final scheduleLabel = OrderNoRiderPolicy.readScheduleLabel(widget.data);
    if (_isWaiting) {
      return _canRequestRefund
          ? L10n.refundIfNoRiderByDeadline
          : L10n.cancelIfNoRiderByDeadline;
    }
    if (_isScheduledTravel) {
      final scheduleHint = scheduleLabel == null
          ? L10n.scheduleApproaching
          : L10n.scheduleApproachingAt(scheduleLabel);
      return _canRequestRefund
          ? (L10n.en
              ? '$scheduleHint but no rider matched yet — you can request a refund'
              : '$scheduleHint แต่ยังจับคู่ไรเดอร์ไม่ได้ — คุณสามารถขอคืนเงินได้')
          : (L10n.en
              ? '$scheduleHint but no rider matched yet — you can cancel the order'
              : '$scheduleHint แต่ยังจับคู่ไรเดอร์ไม่ได้ — คุณสามารถยกเลิกออเดอร์ได้');
    }
    return _canRequestRefund ? L10n.wait15OrRefund : L10n.wait15OrCancel;
  }

  Future<void> _wait15Min() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.orderActions.noRiderWait15Min(orderId: widget.orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.wait15RiderRetrySnack)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.saveWaitFailed(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancelWithoutRefund({
    required String successMessage,
  }) async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.orderActions.noRiderCancel(
        orderId: widget.orderId,
        scheduledTravel: _isScheduledTravel,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.cancelOrderFailed(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _requestRefund() async {
    if (_busy) {
      return;
    }

    final refundInfo = await showOrderRefundAccountDialog(context);
    if (refundInfo == null || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.orderActions.noRiderRefund(
        orderId: widget.orderId,
        scheduledTravel: _isScheduledTravel,
        refundInfo: refundInfo,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.refundRequestSubmitted)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.refundRequestFailed(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _handleSecondaryAction() async {
    if (_canRequestRefund) {
      await _requestRefund();
      return;
    }

    await _cancelWithoutRefund(
      successMessage: L10n.orderCancelled,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
        final waiting = _isWaiting;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            border: Border.all(color: const Color(0xFFFB923C)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    color: Color(0xFFEA580C),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF9A3412),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _subtitle,
                style: const TextStyle(color: Color(0xFF7C2D12), fontSize: 13),
              ),
              const SizedBox(height: 10),
              if (_allowExtraWait)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy || waiting ? null : _wait15Min,
                        icon: const Icon(Icons.timer_outlined),
                        label: Text(
                          waiting ? L10n.waiting : L10n.wait15More,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                        ),
                        onPressed: _busy ? null : _handleSecondaryAction,
                        icon: Icon(
                          _canRequestRefund
                              ? Icons.payments_outlined
                              : Icons.cancel_outlined,
                        ),
                        label: Text(
                          _canRequestRefund
                              ? L10n.requestRefund
                              : L10n.cancelOrder,
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                    onPressed: _busy ? null : _handleSecondaryAction,
                    icon: Icon(
                      _canRequestRefund
                          ? Icons.payments_outlined
                          : Icons.cancel_outlined,
                    ),
                    label: Text(
                      _canRequestRefund
                          ? L10n.requestRefund
                          : L10n.cancelOrder,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
