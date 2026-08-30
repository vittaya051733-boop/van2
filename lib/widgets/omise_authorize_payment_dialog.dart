import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/locale_service.dart';
import '../services/omise_payment_service.dart';

/// Waits for redirect-based Omise payments (Mobile Banking, 3DS).
Future<OmisePaymentSession> showOmiseAuthorizePaymentDialog({
  required BuildContext context,
  required OmisePaymentSession session,
  required OmisePaymentService service,
  required String title,
  required String message,
}) {
  return showDialog<OmisePaymentSession>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _OmiseAuthorizePaymentDialog(
        session: session,
        service: service,
        title: title,
        message: message,
      );
    },
  ).then((value) {
    if (value == null) {
      throw PaymentCheckoutCancelled(L10n.paymentCancelledMessage);
    }
    return value;
  });
}

class _OmiseAuthorizePaymentDialog extends StatefulWidget {
  const _OmiseAuthorizePaymentDialog({
    required this.session,
    required this.service,
    required this.title,
    required this.message,
  });

  final OmisePaymentSession session;
  final OmisePaymentService service;
  final String title;
  final String message;

  @override
  State<_OmiseAuthorizePaymentDialog> createState() =>
      _OmiseAuthorizePaymentDialogState();
}

class _OmiseAuthorizePaymentDialogState
    extends State<_OmiseAuthorizePaymentDialog> {
  Timer? _pollTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  String _status = 'pending';
  bool _isPolling = false;
  bool _completed = false;

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
    _handleStatusUpdate(status);
  }

  Future<void> _pollSession() async {
    if (!mounted || _completed || _isPolling) {
      return;
    }
    setState(() => _isPolling = true);
    try {
      final latest = await widget.service.getSession(widget.session.sessionId);
      if (!mounted || _completed) {
        return;
      }
      _handleStatusUpdate(latest.status);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[omise] authorize poll failed: $error');
      }
    } finally {
      if (mounted && !_completed) {
        setState(() => _isPolling = false);
      }
    }
  }

  void _handleStatusUpdate(String status) {
    if (_completed) {
      return;
    }
    if (status == 'paid') {
      _completePaid();
      return;
    }
    if (status == 'failed' || status == 'expired') {
      if (_status == status) {
        return;
      }
      setState(() => _status = status);
    }
  }

  void _completePaid() {
    if (_completed) {
      return;
    }
    _completed = true;
    _pollTimer?.cancel();
    setState(() => _status = 'paid');
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

  String? get _referenceLabel {
    final orderReference = widget.session.orderReference?.trim();
    if (orderReference != null && orderReference.isNotEmpty) {
      return orderReference;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    final referenceLabel = _referenceLabel;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.message),
          if (referenceLabel != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              L10n.referenceCode(referenceLabel),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              if (_status != 'paid')
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_status != 'paid') const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _status == 'paid'
                      ? L10n.paymentSuccess
                      : L10n.waitingForPayment,
                ),
              ),
            ],
          ),
        ],
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
}
