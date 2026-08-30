import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/omise_payment_channel.dart';
import '../services/locale_service.dart';
import '../services/omise_payment_service.dart';
import 'omise_qr_display.dart';

/// QR / offline Omise payment (PromptPay, TrueMoney) with live status updates.
Future<OmisePaymentSession> showOmiseOfflinePaymentDialog({
  required BuildContext context,
  required OmisePaymentSession session,
  required OmisePaymentChannel channel,
  required OmisePaymentService service,
}) {
  return showDialog<OmisePaymentSession>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _OmiseOfflinePaymentDialog(
        session: session,
        channel: channel,
        service: service,
      );
    },
  ).then((value) {
    if (value == null) {
      throw PaymentCheckoutCancelled(L10n.paymentCancelledMessage);
    }
    return value;
  });
}

class _OmiseOfflinePaymentDialog extends StatefulWidget {
  const _OmiseOfflinePaymentDialog({
    required this.session,
    required this.channel,
    required this.service,
  });

  final OmisePaymentSession session;
  final OmisePaymentChannel channel;
  final OmisePaymentService service;

  @override
  State<_OmiseOfflinePaymentDialog> createState() =>
      _OmiseOfflinePaymentDialogState();
}

class _OmiseOfflinePaymentDialogState extends State<_OmiseOfflinePaymentDialog> {
  Timer? _pollTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  String _status = 'pending';
  String? _failureMessage;
  bool _isPolling = false;
  bool _completed = false;
  String? _pollError;

  @override
  void initState() {
    super.initState();
    _sessionSub = widget.service
        .watchSession(widget.session.sessionId)
        .listen(_onSessionSnapshot);
    _pollSession();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollSession();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _sessionSub?.cancel();
    super.dispose();
  }

  void _onSessionSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null || !mounted || _completed) {
      return;
    }
    final status = data['status']?.toString() ?? '';
    if (status.isEmpty) {
      return;
    }
    _handleStatusUpdate(
      status,
      data['failureMessage']?.toString(),
    );
  }

  Future<void> _pollSession() async {
    if (!mounted || _completed || _isPolling) {
      return;
    }
    setState(() {
      _isPolling = true;
      _pollError = null;
    });
    try {
      final latest = await widget.service.getSession(widget.session.sessionId);
      if (!mounted || _completed) {
        return;
      }
      _handleStatusUpdate(latest.status, null);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[omise] poll failed: $error');
      }
      if (mounted && !_completed) {
        setState(() {
          _pollError = L10n.pollStatusRetrying;
        });
      }
    } finally {
      if (mounted && !_completed) {
        setState(() => _isPolling = false);
      }
    }
  }

  void _handleStatusUpdate(String status, String? failureMessage) {
    if (_completed) {
      return;
    }
    if (status == 'paid') {
      _completePaid();
      return;
    }
    if (status == 'failed' || status == 'expired') {
      if (_status == status && _failureMessage == failureMessage) {
        return;
      }
      setState(() {
        _status = status;
        _failureMessage = failureMessage;
        _pollError = null;
      });
    }
  }

  void _completePaid() {
    if (_completed) {
      return;
    }
    _completed = true;
    _pollTimer?.cancel();
    setState(() {
      _status = 'paid';
      _pollError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        OmisePaymentSession.fromMap(<String, dynamic>{
          'sessionId': widget.session.sessionId,
          'status': 'paid',
          'amount': widget.session.amount,
          'channel': widget.session.channel,
          'omiseChargeId': widget.session.omiseChargeId,
          'orderReference': widget.session.orderReference,
        }),
      );
    });
  }

  String get _title {
    switch (widget.channel) {
      case OmisePaymentChannel.promptPay:
        return L10n.scanPromptPay;
      case OmisePaymentChannel.trueMoney:
        return L10n.scanTrueMoney;
      default:
        return L10n.paymentTitle;
    }
  }

  String get _instruction {
    switch (widget.channel) {
      case OmisePaymentChannel.promptPay:
        return L10n.scanQrBankHint;
      case OmisePaymentChannel.trueMoney:
        return L10n.scanQrTrueMoneyHint;
      default:
        return L10n.payThenWaitConfirm;
    }
  }

  String? get _referenceLabel {
    final orderReference = widget.session.orderReference?.trim();
    if (orderReference != null && orderReference.isNotEmpty) {
      return orderReference;
    }
    final quoteId = widget.session.checkoutQuoteId?.trim();
    if (quoteId != null && quoteId.isNotEmpty && quoteId.length >= 6) {
      return 'QTE-${quoteId.substring(quoteId.length - 8).toUpperCase()}';
    }
    return null;
  }

  String? get _chargeTail {
    final chargeId = widget.session.omiseChargeId?.trim();
    if (chargeId == null || chargeId.length < 8) {
      return null;
    }
    return chargeId.substring(chargeId.length - 8);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    final referenceLabel = _referenceLabel;
    final chargeTail = _chargeTail;

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Text(_title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              L10n.amountBaht(widget.session.amount.toStringAsFixed(2)),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFFE55A00),
              ),
            ),
            if (referenceLabel != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                L10n.referenceCode(referenceLabel),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              if (chargeTail != null)
                Text(
                  'Omise charge: ...$chargeTail',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
            ],
            const SizedBox(height: 12),
            OmiseQrDisplay(session: widget.session),
            const SizedBox(height: 12),
            Text(_instruction),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                if (_status != 'paid' &&
                    _status != 'failed' &&
                    _status != 'expired')
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_status != 'paid') const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _statusLabel(_status),
                    style: TextStyle(
                      color: _status == 'failed'
                          ? Colors.red.shade700
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
              ],
            ),
            if (_pollError != null && _pollError!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _pollError!,
                style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
              ),
            ],
            if (_failureMessage != null && _failureMessage!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _failureMessage!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        if (!_completed)
          TextButton(
            onPressed: _isPolling ? null : _pollSession,
            child: Text(L10n.checkAgain),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.cancel),
        ),
      ],
    );
      },
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'paid':
        return L10n.paymentSuccess;
      case 'failed':
        return L10n.paymentFailedShort;
      case 'expired':
        return L10n.paymentTimedOut;
      default:
        return L10n.waitingForPayment;
    }
  }
}
