import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/omise_payment_channel.dart';
import '../widgets/omise_authorize_payment_dialog.dart';
import '../widgets/omise_card_checkout_screen.dart';
import '../widgets/omise_mobile_bank_sheet.dart';
import '../widgets/omise_offline_payment_dialog.dart';
import '../widgets/omise_qr_display.dart';
import '../widgets/omise_truemoney_phone_dialog.dart';

/// User dismissed the payment UI before completing checkout.
class PaymentCheckoutCancelled implements Exception {
  const PaymentCheckoutCancelled([this.message = 'ยกเลิกการชำระเงิน']);

  final String message;

  @override
  String toString() => message;
}

class OmisePaymentSession {
  const OmisePaymentSession({
    required this.sessionId,
    required this.status,
    required this.amount,
    required this.channel,
    this.qrImageUrl,
    this.qrImageDataUrl,
    this.authorizeUri,
    this.publicKey,
    this.needsCardToken = false,
    this.omiseChargeId,
    this.checkoutQuoteId,
    this.orderReference,
  });

  final String sessionId;
  final String status;
  final double amount;
  final String channel;
  final String? qrImageUrl;
  final String? qrImageDataUrl;
  final String? authorizeUri;
  final String? publicKey;
  final bool needsCardToken;
  final String? omiseChargeId;
  final String? checkoutQuoteId;
  final String? orderReference;

  factory OmisePaymentSession.fromMap(Map<String, dynamic> map) {
    return OmisePaymentSession(
      sessionId: map['sessionId']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      channel: map['channel']?.toString() ?? '',
      qrImageUrl: map['qrImageUrl']?.toString(),
      qrImageDataUrl: map['qrImageDataUrl']?.toString(),
      authorizeUri: map['authorizeUri']?.toString(),
      publicKey: map['publicKey']?.toString(),
      needsCardToken: map['needsCardToken'] == true,
      omiseChargeId: map['omiseChargeId']?.toString(),
      checkoutQuoteId: map['checkoutQuoteId']?.toString(),
      orderReference: map['orderReference']?.toString(),
    );
  }
}

class OmisePaymentService {
  OmisePaymentService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
        _firestore = firestore ?? FirebaseFirestore.instance;

  static const String defaultReturnUri = 'https://vantalad.web.app/payment/return';

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  String get _platformType {
    if (kIsWeb) {
      return 'ANDROID';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'IOS';
      default:
        return 'ANDROID';
    }
  }

  Never _throwCallableError(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        throw Exception(message);
      }
    }
    throw error is Exception ? error : Exception(error.toString());
  }

  Future<OmisePaymentSession> createSession({
    required OmisePaymentChannel channel,
    required double amount,
    required String checkoutQuoteId,
    String purpose = 'cart',
    String? cardToken,
    String? mobileBankCode,
    String? phoneNumber,
    String? returnUri,
    String? platformType,
  }) async {
    final callable = _functions.httpsCallable('createOmisePaymentSession');
    try {
      final response = await callable.call(<String, dynamic>{
        'channel': channel.methodId,
        'amount': amount,
        if (checkoutQuoteId.isNotEmpty) 'checkoutQuoteId': checkoutQuoteId,
        'purpose': purpose,
        if (cardToken != null && cardToken.isNotEmpty) 'cardToken': cardToken,
        if (mobileBankCode != null && mobileBankCode.isNotEmpty)
          'mobileBankCode': mobileBankCode,
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phoneNumber': phoneNumber,
        'returnUri': returnUri ?? defaultReturnUri,
        'platformType': platformType ?? _platformType,
      });

      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      return OmisePaymentSession.fromMap(payload);
    } catch (error) {
      _throwCallableError(error);
    }
  }

  Future<OmisePaymentSession> getSession(String sessionId) async {
    final callable = _functions.httpsCallable('getOmisePaymentSession');
    final response = await callable.call(<String, dynamic>{
      'sessionId': sessionId,
    });
    final payload = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};
    return OmisePaymentSession.fromMap(payload);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSession(String sessionId) {
    return _firestore.collection('payment_sessions').doc(sessionId).snapshots();
  }

  Future<OmisePaymentSession> waitUntilPaid({
    required String sessionId,
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final completer = Completer<OmisePaymentSession>();
    late StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub;
    Timer? timer;
    Timer? pollTimer;

    void finishPaid(Map<String, dynamic> data) {
      if (!completer.isCompleted) {
        completer.complete(OmisePaymentSession.fromMap(<String, dynamic>{
          'sessionId': sessionId,
          ...data,
        }));
      }
    }

    void finishError(String message) {
      if (!completer.isCompleted) {
        completer.completeError(Exception(message));
      }
    }

    sub = watchSession(sessionId).listen((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return;
      }
      final status = data['status']?.toString() ?? '';
      if (status == 'paid') {
        finishPaid(data);
      } else if (status == 'failed' || status == 'expired') {
        finishError(
          data['failureMessage']?.toString() ?? 'การชำระเงินไม่สำเร็จ',
        );
      }
    });

    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (completer.isCompleted) {
        return;
      }
      try {
        final session = await getSession(sessionId);
        if (session.status == 'paid') {
          finishPaid(<String, dynamic>{
            'status': session.status,
            'amount': session.amount,
            'channel': session.channel,
            'omiseChargeId': session.omiseChargeId,
          });
        } else if (session.status == 'failed' || session.status == 'expired') {
          finishError('การชำระเงินไม่สำเร็จ');
        }
      } catch (_) {
        // Ignore transient poll errors.
      }
    });

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('หมดเวลารอการชำระเงิน'),
        );
      }
    });

    try {
      return await completer.future;
    } finally {
      await sub.cancel();
      pollTimer.cancel();
      timer.cancel();
    }
  }

  Future<OmisePaymentSession> startCheckout({
    required BuildContext context,
    required OmisePaymentChannel channel,
    required double amount,
    required String checkoutQuoteId,
    String purpose = 'cart',
  }) async {
    String? phoneNumber;
    String? mobileBankCode;

    if (channel == OmisePaymentChannel.trueMoney) {
      if (!context.mounted) {
        throw Exception('ไม่สามารถแสดงฟอร์ม TrueMoney ได้');
      }
      phoneNumber = await showOmiseTrueMoneyPhoneDialog(context: context);
      if (phoneNumber == null || phoneNumber.isEmpty) {
        throw const PaymentCheckoutCancelled('ยกเลิกการชำระ TrueMoney');
      }
    }

    if (channel == OmisePaymentChannel.mobileBanking) {
      if (!context.mounted) {
        throw Exception('ไม่สามารถเลือกธนาคารได้');
      }
      mobileBankCode = await showOmiseMobileBankSheet(context);
      if (mobileBankCode == null || mobileBankCode.isEmpty) {
        throw const PaymentCheckoutCancelled('ยกเลิกการชำระ Mobile Banking');
      }
    }

    var session = await createSession(
      channel: channel,
      amount: amount,
      checkoutQuoteId: checkoutQuoteId,
      purpose: purpose,
      phoneNumber: phoneNumber,
      mobileBankCode: mobileBankCode,
    );

    if (session.hasDisplayableQr &&
        (session.qrImageDataUrl == null ||
            session.qrImageDataUrl!.trim().isEmpty)) {
      debugPrint(
        '[omise] QR data URL missing after create — refetching session ${session.sessionId}',
      );
      session = await getSession(session.sessionId);
    }

    debugPrint(
      '[omise] session ${session.sessionId} channel=${session.channel} '
      'status=${session.status} hasQr=${session.hasDisplayableQr} '
      'authorize=${session.authorizeUri != null && session.authorizeUri!.isNotEmpty}',
    );

    if (session.status == 'paid') {
      return session;
    }

    if (session.hasDisplayableQr) {
      if (!context.mounted) {
        throw Exception('ไม่สามารถแสดง QR ชำระเงินได้');
      }
      return showOmiseOfflinePaymentDialog(
        context: context,
        session: session,
        channel: channel,
        service: this,
      );
    }

    if (session.authorizeUri != null && session.authorizeUri!.isNotEmpty) {
      final uri = Uri.tryParse(session.authorizeUri!);
      if (uri != null) {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) {
          throw Exception('ไม่สามารถเปิดหน้าชำระเงินได้ กรุณาลองอีกครั้ง');
        }
      }
      if (!context.mounted) {
        throw Exception('ไม่สามารถแสดงหน้ารอชำระเงินได้');
      }
      return showOmiseAuthorizePaymentDialog(
        context: context,
        session: session,
        service: this,
        title: channel == OmisePaymentChannel.mobileBanking
            ? 'โอนผ่านแอปธนาคาร'
            : channel == OmisePaymentChannel.trueMoney
                ? 'ยืนยัน TrueMoney'
                : 'รอการชำระเงิน',
        message: channel == OmisePaymentChannel.mobileBanking
            ? 'กรุณาชำระเงินในแอปธนาคารที่เปิดขึ้น แล้วกลับมารอสักครู่'
            : channel == OmisePaymentChannel.trueMoney
                ? 'กรุณายืนยัน OTP ใน TrueMoney Wallet แล้วกลับมารอสักครู่'
                : 'กรุณาชำระเงินในแอป/เบราว์เซอร์ที่เปิดขึ้น แล้วรอสักครู่',
      );
    }

    if (session.needsCardToken) {
      if (!context.mounted) {
        throw Exception('ไม่สามารถแสดงฟอร์มบัตรได้');
      }
      final completedPayload = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute<Map<String, dynamic>>(
          fullscreenDialog: true,
          builder: (context) => OmiseCardCheckoutScreen(
            sessionId: session.sessionId,
            amount: amount,
            publicKey: session.publicKey,
          ),
        ),
      );
      if (completedPayload == null) {
        throw const PaymentCheckoutCancelled('ยกเลิกการชำระด้วยบัตร');
      }
      final completed = OmisePaymentSession.fromMap(completedPayload);
      if (completed.status == 'paid') {
        return completed;
      }
      if (completed.authorizeUri != null &&
          completed.authorizeUri!.isNotEmpty) {
        final uri = Uri.tryParse(completed.authorizeUri!);
        if (uri != null) {
          final launched =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!launched) {
            throw Exception('ไม่สามารถเปิดหน้ายืนยัน 3D Secure ได้');
          }
        }
        if (context.mounted) {
          return showOmiseAuthorizePaymentDialog(
            context: context,
            session: completed,
            service: this,
            title: 'ยืนยันการชำระเงิน',
            message: 'กรุณายืนยันในแอปธนาคาร/3D Secure แล้วรอสักครู่',
          );
        }
      }
      return waitUntilPaid(sessionId: completed.sessionId);
    }

    throw Exception(
      'ไม่สามารถเริ่มช่องทาง ${channel.label} ได้ กรุณาเลือกช่องทางอื่น',
    );
  }

  Widget buildQrImage(OmisePaymentSession session) {
    return OmiseQrDisplay(session: session);
  }
}

extension OmisePaymentSessionQr on OmisePaymentSession {
  bool get hasDisplayableQr {
    final dataUrl = qrImageDataUrl?.trim();
    if (dataUrl != null && dataUrl.isNotEmpty) {
      return true;
    }
    final url = qrImageUrl?.trim();
    return url != null && url.isNotEmpty;
  }
}
