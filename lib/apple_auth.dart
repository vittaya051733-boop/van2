import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'ios_apple_auth.dart';
import 'web_apple_auth.dart';

/// Web (OAuth) + iOS (native) — same Firebase `apple.com` provider as vantalad web.
bool get isAppleSignInSupported =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.iOS;

Future<UserCredential> signInWithApple() async {
  if (kIsWeb) {
    return signInWithAppleForWeb();
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return signInWithAppleForIos();
  }
  throw FirebaseAuthException(
    code: 'operation-not-supported-in-this-environment',
    message: 'Sign in with Apple is only supported on web and iOS.',
  );
}
