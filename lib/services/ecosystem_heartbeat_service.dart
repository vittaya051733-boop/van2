import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Writes live health heartbeats for van4 ecosystem dashboard.
class EcosystemHeartbeatService {
  EcosystemHeartbeatService._();

  static final EcosystemHeartbeatService instance =
      EcosystemHeartbeatService._();

  static const String appId = 'van2';
  static const Duration interval = Duration(seconds: 45);
  static const Duration probeTimeout = Duration(seconds: 8);

  Timer? _timer;
  bool _pulsing = false;

  void start() {
    _timer?.cancel();
    unawaited(pulse());
    _timer = Timer.periodic(interval, (_) => unawaited(pulse()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  DocumentReference<Map<String, dynamic>> _sessionRef(String uid) {
    return FirebaseFirestore.instance
        .collection('ecosystem_heartbeats')
        .doc(appId)
        .collection('sessions')
        .doc(uid);
  }

  Future<void> _writeSession({
    required String uid,
    required bool firestoreOk,
    required Map<String, bool> points,
    String? lastError,
    String? errorCode,
  }) {
    return _sessionRef(uid).set(<String, dynamic>{
      'appId': appId,
      'uid': uid,
      'firestoreOk': firestoreOk,
      'updatedAt': FieldValue.serverTimestamp(),
      'platform': defaultTargetPlatform.name,
      'points': points,
      'lastError': lastError,
      'errorCode': errorCode,
    }, SetOptions(merge: true));
  }

  Future<void> pulse() async {
    if (_pulsing) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    _pulsing = true;
    final uid = user.uid;
    try {
      // Alive ping first — do not clear `points` (merge would wipe prior map).
      await _sessionRef(uid).set(<String, dynamic>{
        'appId': appId,
        'uid': uid,
        'firestoreOk': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      }, SetOptions(merge: true));

      final points = <String, bool>{};
      String? lastError;
      String? errorCode;
      var firestoreOk = true;

      Future<void> check(String pointId, Future<void> Function() action) async {
        try {
          await action().timeout(probeTimeout);
          points[pointId] = true;
        } catch (error) {
          points[pointId] = false;
          firestoreOk = false;
          lastError ??= error.toString();
          if (error is FirebaseException) {
            errorCode ??= error.code;
          }
          debugPrint('van2 heartbeat $pointId failed: $error');
        }
      }

      final db = FirebaseFirestore.instance;
      const server = GetOptions(source: Source.server);

      await check('V2-CATALOG', () async {
        await db.collection('products').limit(1).get(server);
      });
      await check('V2-COUPONS', () async {
        await db.collection('coupons').limit(1).get(server);
      });
      await check('V2-PRICING', () async {
        await db.collection('pricing_config').limit(1).get(server);
      });
      await check('V2-ORDERS', () async {
        await db
            .collection('orders')
            .where('customerId', isEqualTo: uid)
            .limit(1)
            .get(server);
      });
      await check('V2-NOTIF', () async {
        await db
            .collection('app_notifications')
            .where('recipientUid', isEqualTo: uid)
            .limit(1)
            .get(server);
      });

      await _writeSession(
        uid: uid,
        firestoreOk: firestoreOk,
        points: points,
        lastError: lastError,
        errorCode: errorCode,
      );
    } catch (error) {
      debugPrint('van2 heartbeat write failed: $error');
    } finally {
      _pulsing = false;
    }
  }
}
