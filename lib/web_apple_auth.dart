import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Starts Sign in with Apple through Firebase Auth on web.
Future<UserCredential> signInWithAppleForWeb() async {
  final provider = OAuthProvider('apple.com')
    ..addScope('email')
    ..addScope('name');

  try {
    return await FirebaseAuth.instance.signInWithPopup(provider);
  } on FirebaseAuthException catch (error) {
    final useRedirect =
        error.code == 'popup-blocked' ||
        error.code == 'auth/popup-blocked' ||
        error.code == 'operation-not-supported-in-this-environment' ||
        error.code == 'auth/operation-not-supported-in-this-environment';
    if (!useRedirect) {
      rethrow;
    }

    await FirebaseAuth.instance.signInWithRedirect(provider);
    throw FirebaseAuthException(
      code: 'redirect-initiated',
      message: 'กำลังเปิดหน้าเข้าสู่ระบบ Apple...',
    );
  }
}

/// Reads the result of either Google or Apple OAuth redirect exactly once.
Future<UserCredential?> handleWebOAuthRedirectResult() async {
  if (!kIsWeb) {
    return null;
  }

  final result = await FirebaseAuth.instance.getRedirectResult();
  final user = result.user;
  if (user == null || user.isAnonymous) {
    return null;
  }
  return result;
}

bool isAppleCredential(UserCredential credential) {
  return credential.credential?.providerId == 'apple.com' ||
      credential.additionalUserInfo?.providerId == 'apple.com' ||
      credential.user?.providerData.any(
            (provider) => provider.providerId == 'apple.com',
          ) ==
          true;
}
