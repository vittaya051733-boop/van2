import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

const String kAppCheckRecaptchaSiteKey = String.fromEnvironment(
  'APP_CHECK_RECAPTCHA_SITE_KEY',
);

/// Ensures App Check token is available before payment / checkout callables.
class AppCheckGuard {
  const AppCheckGuard._();

  static Future<void> ensureCheckoutReady() async {
    await _ensureToken(
      releaseMessage:
          'ไม่สามารถยืนยันความปลอดภัยของอุปกรณ์ได้ กรุณาอัปเดตแอปจาก Play Store หรือลองใหม่',
    );
  }

  static Future<void> ensureAuthReady() async {
    await _ensureToken(
      releaseMessage:
          'ไม่สามารถยืนยันความปลอดภัยของอุปกรณ์ได้ กรุณาอัปเดตแอปจาก Play Store แล้วลองเข้าสู่ระบบใหม่',
      webMessage:
          'เวอร์ชันเว็บยังไม่พร้อมเข้าสู่ระบบ กรุณาใช้แอปมือถือหรือติดต่อผู้ดูแลระบบ',
    );
  }

  static Future<void> _ensureToken({
    required String releaseMessage,
    String? webMessage,
  }) async {
    if (kIsWeb) {
      if (kReleaseMode && kAppCheckRecaptchaSiteKey.isEmpty) {
        throw Exception(
          webMessage ??
              'เวอร์ชันเว็บยังไม่พร้อมชำระเงิน กรุณาใช้แอปมือถือหรือติดต่อผู้ดูแลระบบ',
        );
      }
      return;
    }

    Object? lastError;
    for (final forceRefresh in [false, true]) {
      try {
        await FirebaseAppCheck.instance
            .getToken(forceRefresh)
            .timeout(const Duration(seconds: 8));
        return;
      } catch (error) {
        lastError = error;
      }
    }

    if (kReleaseMode) {
      throw Exception(releaseMessage);
    }
    if (kDebugMode && lastError != null) {
      debugPrint('App Check token unavailable (debug): $lastError');
    }
  }
}
