import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../privacy_onboarding_screen.dart';

/// Keep in sync across van1, van2, van3.
const String kPrivacyPolicyVersion = '2026-06-01';

abstract final class PrivacyAppKey {
  static const String van2Customer = 'van2_customer';
  static const String van1Merchant = 'van1_merchant';
  static const String van3Rider = 'van3_rider';
}

class PrivacyConsentSnapshot {
  const PrivacyConsentSnapshot({
    required this.policyVersion,
    required this.pushOptIn,
    required this.marketingOptIn,
    required this.termsAcceptedAt,
  });

  final String policyVersion;
  final bool pushOptIn;
  final bool marketingOptIn;
  final DateTime? termsAcceptedAt;

  bool get isCurrentPolicy =>
      policyVersion.trim() == kPrivacyPolicyVersion;
}

class PrivacyConsentService {
  PrivacyConsentService._();

  static final PrivacyConsentService instance = PrivacyConsentService._();

  static const String _localVersionKey = 'privacy_policy_version';
  static const String _localPushKey = 'privacy_push_opt_in';
  static const String _localMarketingKey = 'privacy_marketing_opt_in';

  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  Future<bool> hasLocalConsentForCurrentPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localVersionKey) == kPrivacyPolicyVersion;
  }

  Future<PrivacyConsentSnapshot?> loadLocalSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString(_localVersionKey)?.trim();
    if (version == null || version.isEmpty) {
      return null;
    }
    return PrivacyConsentSnapshot(
      policyVersion: version,
      pushOptIn: prefs.getBool(_localPushKey) ?? false,
      marketingOptIn: prefs.getBool(_localMarketingKey) ?? false,
      termsAcceptedAt: null,
    );
  }

  Future<void> saveLocalConsent({
    required bool pushOptIn,
    required bool marketingOptIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localVersionKey, kPrivacyPolicyVersion);
    await prefs.setBool(_localPushKey, pushOptIn);
    await prefs.setBool(_localMarketingKey, marketingOptIn);
  }

  Future<PrivacyConsentSnapshot?> loadRemoteSnapshot({
    required String uid,
    required String app,
  }) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      return null;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('privacy_consents')
          .doc(trimmedUid)
          .get();
      final data = doc.data();
      if (data == null) {
        return null;
      }

      final apps = data['apps'];
      if (apps is! Map) {
        return null;
      }

      final appData = apps[app];
      if (appData is! Map) {
        return null;
      }

      final version = appData['policyVersion']?.toString().trim() ?? '';
      if (version.isEmpty) {
        return null;
      }

      DateTime? acceptedAt;
      final rawAcceptedAt = appData['termsAcceptedAt'];
      if (rawAcceptedAt is Timestamp) {
        acceptedAt = rawAcceptedAt.toDate();
      }

      return PrivacyConsentSnapshot(
        policyVersion: version,
        pushOptIn: appData['pushOptIn'] == true,
        marketingOptIn: appData['marketingOptIn'] == true,
        termsAcceptedAt: acceptedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> needsConsentFlow({
    required String app,
    User? user,
  }) async {
    // Show the full-screen gate only until the user accepts the current
    // policy locally. Preferences remain editable in Settings afterwards.
    return !(await hasLocalConsentForCurrentPolicy());
  }

  Future<void> recordRemoteConsent({
    required String app,
    required bool pushOptIn,
    required bool marketingOptIn,
    String source = 'app',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return;
    }

    final callable = _functions.httpsCallable('recordPrivacyConsent');
    await callable.call(<String, dynamic>{
      'app': app,
      'policyVersion': kPrivacyPolicyVersion,
      'pushOptIn': pushOptIn,
      'marketingOptIn': marketingOptIn,
      'locale': _currentLocaleCode(),
      'platform': _currentPlatformLabel(),
      'source': source,
    });
  }

  Future<void> persistConsent({
    required String app,
    required bool pushOptIn,
    required bool marketingOptIn,
    String source = 'app',
  }) async {
    await saveLocalConsent(
      pushOptIn: pushOptIn,
      marketingOptIn: marketingOptIn,
    );
    try {
      await recordRemoteConsent(
        app: app,
        pushOptIn: pushOptIn,
        marketingOptIn: marketingOptIn,
        source: source,
      );
    } catch (error) {
      debugPrint('Remote privacy consent sync failed: $error');
    }
  }

  Future<bool> ensureConsent(
    BuildContext context, {
    required String app,
    String source = 'onboarding_gate',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final needs = await needsConsentFlow(app: app, user: user);
    if (!needs) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    final result = await Navigator.of(context).push<PrivacyOnboardingResult>(
      MaterialPageRoute<PrivacyOnboardingResult>(
        fullscreenDialog: true,
        builder: (_) => PrivacyOnboardingScreen(app: app),
      ),
    );

    if (!context.mounted || result == null || !result.acceptedTerms) {
      return false;
    }

    await persistConsent(
      app: app,
      pushOptIn: result.pushOptIn,
      marketingOptIn: result.marketingOptIn,
      source: source,
    );
    return true;
  }

  Future<void> updatePreference({
    required String app,
    bool? pushOptIn,
    bool? marketingOptIn,
    String source = 'privacy_settings',
  }) async {
    final local = await loadLocalSnapshot();
    final nextPush = pushOptIn ?? local?.pushOptIn ?? false;
    final nextMarketing = marketingOptIn ?? local?.marketingOptIn ?? false;
    await persistConsent(
      app: app,
      pushOptIn: nextPush,
      marketingOptIn: nextMarketing,
      source: source,
    );
  }

  Future<({String requestId, String ticketId})> createPrivacyRequest({
    required String app,
    required String type,
    String? note,
  }) async {
    final callable = _functions.httpsCallable('createPrivacyRequest');
    final response = await callable.call(<String, dynamic>{
      'app': app,
      'type': type,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    final data = response.data;
    if (data is! Map) {
      throw StateError('คำขอ PDPA ไม่สำเร็จ');
    }
    final requestId = data['requestId']?.toString().trim() ?? '';
    final ticketId = data['ticketId']?.toString().trim() ?? '';
    if (requestId.isEmpty) {
      throw StateError('คำขอ PDPA ไม่สำเร็จ');
    }
    return (requestId: requestId, ticketId: ticketId);
  }

  String _currentLocaleCode() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    } catch (_) {
      return 'th';
    }
  }

  String _currentPlatformLabel() {
    if (kIsWeb) {
      return 'web';
    }
    return Platform.operatingSystem;
  }
}
