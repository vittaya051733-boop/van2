import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_verification_screen.dart';
import 'category_catalog_screen.dart';
import 'phone_login_helper.dart';
import 'services/notification_service.dart';
import 'services/privacy_consent_service.dart';
import 'l10n/l10n.dart';
import 'utils/app_check_guard.dart';
import 'web_google_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.categoryLabel,
    this.serviceType,
    required this.firebaseEnabled,
    this.onLoggedIn,
  });

  final String categoryLabel;
  final String? serviceType;
  final bool firebaseEnabled;
  final void Function(BuildContext context)? onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  bool _isSigningIn = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(_handleWebGoogleRedirectResult());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        _completeLogin();
      }
    });
  }

  Future<void> _restoreAnonymousBrowsingSession() => restoreAnonymousBrowsingSession();

  Future<void> _handleWebGoogleRedirectResult() async {
    try {
      final result = await handleWebGoogleRedirectResult();
      final user = result?.user;
      if (user == null || !mounted) {
        return;
      }

      _showSnackBar(
        user.displayName?.trim().isNotEmpty == true
            ? L10n.signInSuccessWithName(user.displayName!)
            : L10n.signInSuccessGoogle,
      );
      _completeLogin();
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        L10n.googleSignInFailed(error.message ?? error.code),
      );
      await _restoreAnonymousBrowsingSession();
    } catch (_) {
      await _restoreAnonymousBrowsingSession();
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isEmailIdentifier(String value) {
    return value.contains('@');
  }

  Future<_LoginIdentifierStatus?> _lookupIdentifierStatus({
    String? email,
    String? phoneNumber,
  }) async {
    try {
      await AppCheckGuard.ensureAuthReady();
      final callable = _functions.httpsCallable('lookupLoginIdentifier');
      final response = await callable.call(<String, dynamic>{
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
          'phoneNumber': phoneNumber.trim(),
      });
      final data = response.data;
      if (data is! Map) {
        return null;
      }
      return _LoginIdentifierStatus.fromMap(Map<Object?, Object?>.from(data));
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return null;
      }
      _showSnackBar(error.message ?? L10n.lookupIdentifierFailed);
      return null;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      _showSnackBar(L10n.lookupIdentifierFailedWithError(error));
      return null;
    }
  }

  Future<String?> _askForResetEmail() async {
    final emailController = TextEditingController(
      text: _isEmailIdentifier(_identifierController.text.trim())
          ? _identifierController.text.trim()
          : '',
    );

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(L10n.forgotPassword),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: InputDecoration(
              labelText: L10n.email,
              hintText: 'name@example.com',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(L10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final value = emailController.text.trim();
                if (!_isEmailIdentifier(value)) {
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: Text(L10n.sendOtp),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startForgotPasswordFlow() async {
    if (!widget.firebaseEnabled) {
      _showSnackBar(L10n.firebaseNotReady);
      return;
    }

    final email = await _askForResetEmail();

    if (!mounted || email == null || email.isEmpty) {
      return;
    }

    if (!_isEmailIdentifier(email)) {
      _showSnackBar(L10n.pleaseEnterValidEmail);
      return;
    }

    _identifierController.text = email;

    setState(() => _isSigningIn = true);
    try {
      await AppCheckGuard.ensureAuthReady();
      final callable = _functions.httpsCallable('sendEmailOtp');
      await callable.call(<String, dynamic>{'email': email});
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(_mapEmailFunctionError(error));
      return;
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      _showSnackBar(L10n.emailOtpRestartApp);
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(L10n.cannotSendEmailOtp(error));
      return;
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }

    if (!mounted) {
      return;
    }

    _showSnackBar(L10n.otpSentToEmail(email));

    await Future<void>.delayed(Duration.zero);

    if (!mounted) {
      return;
    }

    await _openOtpVerification(
      identifier: email,
      password: '',
      channel: VerificationChannel.email,
      purpose: VerificationPurpose.resetPassword,
      autoStart: false,
      initialOtpSent: true,
    );
  }

  Future<void> _handleLogin() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();
    final isEmail = _isEmailIdentifier(identifier);
    final normalizedPhone = isEmail ? '' : PhoneLoginHelper.normalize(identifier);

    if (identifier.isEmpty || password.isEmpty) {
      _showSnackBar(L10n.pleaseEnterEmailOrPhoneAndPassword);
      return;
    }

    if (!widget.firebaseEnabled) {
      _showSnackBar(L10n.firebaseNotReady);
      return;
    }

    if (!isEmail && !normalizedPhone.startsWith('+')) {
      _showSnackBar(L10n.pleaseEnterValidPhone);
      return;
    }

    if (isEmail) {
      final emailStatus = await _lookupIdentifierStatus(email: identifier);
      if (emailStatus == null || !mounted) {
        return;
      }

      if (!emailStatus.emailExists) {
        final verified = await _openOtpVerification(
          identifier: identifier,
          password: password,
          channel: VerificationChannel.email,
          purpose: VerificationPurpose.register,
        );
        if (verified == true && mounted) {
          _completeLogin();
        }
        return;
      }

      final directEmailSignIn = await _trySignInEmailWithoutOtp(
        identifier,
        password,
      );
      if (directEmailSignIn != false) {
        return;
      }

      final verified = await _openOtpVerification(
        identifier: identifier,
        password: password,
        channel: VerificationChannel.email,
      );
      if (verified == true && mounted) {
        _completeLogin();
      }
      return;
    }

    final phoneStatus = await _lookupIdentifierStatus(phoneNumber: normalizedPhone);
    if (phoneStatus == null || !mounted) {
      return;
    }

    if (!phoneStatus.phoneExists) {
      final verified = await _openOtpVerification(
        identifier: normalizedPhone,
        password: password,
        channel: VerificationChannel.phone,
        purpose: VerificationPurpose.register,
      );
      if (verified == true && mounted) {
        _completeLogin();
      }
      return;
    }

    if (phoneStatus.phoneExists) {
      final fastSignIn = await _trySignInPhoneWithoutOtp(normalizedPhone, password);
      if (fastSignIn != false) {
        return;
      }

      final verified = await _openOtpVerification(
        identifier: normalizedPhone,
        password: password,
        channel: VerificationChannel.phone,
      );
      if (verified == true && mounted) {
        _completeLogin();
      }
      return;
    }
  }

  Future<bool?> _trySignInEmailWithoutOtp(
    String email,
    String password,
  ) async {
    setState(() => _isSigningIn = true);
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final signedInUser = userCredential.user;
      if (signedInUser == null) {
        throw Exception(L10n.userNotFoundAfterSignIn);
      }

      await signedInUser.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser?.emailVerified == true) {
        if (!mounted) {
          return true;
        }

        _completeLogin();
        return true;
      }

      await FirebaseAuth.instance.signOut();
      if (mounted) {
        _showSnackBar(L10n.pleaseVerifyOtpFirst);
      }
      return false;
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return null;
      }

      _showSnackBar(_mapEmailPasswordSignInError(error));
      return null;
    } catch (error) {
      if (!mounted) {
        return null;
      }

      _showSnackBar(L10n.emailSignInFailedWithError(error));
      return null;
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<bool?> _trySignInPhoneWithoutOtp(
    String identifier,
    String password,
  ) async {
    final normalizedPhone = PhoneLoginHelper.normalize(identifier);
    if (!normalizedPhone.startsWith('+')) {
      return false;
    }

    setState(() => _isSigningIn = true);
    try {
      final callable = _functions.httpsCallable('signInWithPhonePassword');
      final response = await callable.call(<String, dynamic>{
        'phoneNumber': normalizedPhone,
        'password': password,
      });

      final data = response.data;
      if (data is! Map) {
        return false;
      }

      final token = data['customToken'];
      if (token is! String || token.trim().isEmpty) {
        return false;
      }

      await FirebaseAuth.instance.signInWithCustomToken(token);
      if (!mounted) {
        return true;
      }

      _showSnackBar(L10n.signInSuccessNoOtp);
      _completeLogin();
      return true;
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return null;
      }

      final message = error.message ?? '';
      if (
        error.code == 'permission-denied' &&
        message.contains('ต้องยืนยัน OTP ครั้งแรกก่อน')
      ) {
        _showSnackBar(L10n.pleaseVerifyOtpFirst);
        return false;
      }

      if (
        error.code == 'permission-denied' ||
        error.code == 'invalid-argument'
      ) {
        _showSnackBar(message.isNotEmpty ? message : L10n.phoneOrPasswordIncorrect);
        return null;
      }

      _showSnackBar(message.isNotEmpty ? message : L10n.phoneSignInFailed);
      return null;
    } catch (error) {
      if (!mounted) {
        return null;
      }

      _showSnackBar(L10n.phoneSignInFailedWithError(error));
      return null;
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<bool> _openOtpVerification({
    required String identifier,
    required String password,
    required VerificationChannel channel,
    VerificationPurpose purpose = VerificationPurpose.signIn,
    bool autoStart = true,
    bool initialOtpSent = false,
  }) async {

    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => AuthVerificationScreen(
          channel: channel,
          identifier: identifier,
          password: password,
          purpose: purpose,
          autoStart: autoStart,
          initialOtpSent: initialOtpSent,
          firebaseEnabled: widget.firebaseEnabled,
        ),
      ),
    );

    return verified == true;
  }

  Future<void> _completeLogin() async {
    if (!mounted) {
      return;
    }

    final consentOk = await PrivacyConsentService.instance.ensureConsent(
      context,
      app: PrivacyAppKey.van2Customer,
      source: 'login_gate',
    );
    if (!mounted || !consentOk) {
      return;
    }

    final local = await PrivacyConsentService.instance.loadLocalSnapshot();
    if (!kIsWeb && local?.pushOptIn == true) {
      await NotificationService().enablePushNotifications();
    }

    if (!mounted) {
      return;
    }

    if (widget.onLoggedIn != null) {
      widget.onLoggedIn!(context);
      return;
    }

    if (widget.serviceType != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => CategoryCatalogScreen(
            title: widget.categoryLabel,
            serviceType: widget.serviceType!,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _signInWithGoogle() async {
    if (!widget.firebaseEnabled) {
      _showSnackBar(L10n.firebaseNotReady);
      return;
    }

    setState(() => _isSigningIn = true);

    try {
      final UserCredential credential;
      if (kIsWeb) {
        credential = await signInWithGoogleForWeb();
      } else {
        final googleUser = await GoogleSignIn(
          scopes: <String>['email'],
        ).signIn();
        if (googleUser == null) {
          return;
        }

        final googleAuth = await googleUser.authentication;
        final authCredential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        credential = await FirebaseAuth.instance.signInWithCredential(
          authCredential,
        );
      }

      if (!mounted) {
        return;
      }

      final user = credential.user;
      _showSnackBar(
        user?.displayName?.trim().isNotEmpty == true
            ? L10n.signInSuccessWithName(user!.displayName!)
            : L10n.signInSuccessGoogle,
      );

      _completeLogin();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'auth/popup-closed-by-user' ||
          error.code == 'auth/redirect-initiated') {
        if (error.code == 'auth/popup-closed-by-user') {
          await _restoreAnonymousBrowsingSession();
        }
        return;
      }
      _showSnackBar(
        L10n.googleSignInFailed(error.message ?? error.code),
      );
      await _restoreAnonymousBrowsingSession();
    } catch (error) {
      _showSnackBar(L10n.googleSignInFailed('$error'));
      await _restoreAnonymousBrowsingSession();
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _mapEmailFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'invalid-argument':
        return L10n.invalidEmailFormat;
      case 'resource-exhausted':
        return L10n.waitBeforeNewCode;
      case 'failed-precondition':
        return L10n.emailOtpSmtpNotConfigured;
      case 'unavailable':
      case 'internal':
        return error.message ?? L10n.emailOtpServerNotReady;
      default:
        return error.message ?? L10n.sendEmailOtpFailed;
    }
  }

  String _mapEmailPasswordSignInError(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
        return L10n.emailAccountNotFound;
      case 'wrong-password':
      case 'invalid-credential':
        return L10n.emailOrPasswordIncorrect;
      case 'invalid-email':
        return L10n.invalidEmailFormat;
      case 'user-disabled':
        return L10n.accountDisabled;
      default:
        return error.message ?? L10n.emailSignInFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7ED),
      appBar: AppBar(
        title: Text(L10n.signIn),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                L10n.signInToUseCategory(widget.categoryLabel),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF9A3412),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.serviceType == null
                    ? L10n.signInHintNoServiceType
                    : L10n.signInHintWithServiceType(widget.serviceType!),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF7C2D12),
                ),
              ),
              const SizedBox(height: 28),
              _LoginTextField(
                label: L10n.emailOrPhone,
                icon: Icons.person_outline,
                controller: _identifierController,
              ),
              const SizedBox(height: 16),
              _LoginTextField(
                label: L10n.password,
                icon: Icons.lock_outline,
                obscureText: true,
                controller: _passwordController,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isSigningIn ? null : _startForgotPasswordFlow,
                  child: Text(L10n.forgotPasswordQuestion),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSigningIn ? null : _handleLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(L10n.signIn),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSigningIn ? null : _signInWithGoogle,
                  icon: _isSigningIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Image.asset(
                          'assets/google_logo.png',
                          width: 20,
                          height: 20,
                          fit: BoxFit.contain,
                        ),
                  label: Text(
                    _isSigningIn
                        ? L10n.signingIn
                        : L10n.signInWithGoogle,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C2D12),
                    side: const BorderSide(color: Color(0xFFF57C00)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginIdentifierStatus {
  const _LoginIdentifierStatus({
    required this.emailExists,
    required this.phoneExists,
  });

  factory _LoginIdentifierStatus.fromMap(Map<Object?, Object?> map) {
    return _LoginIdentifierStatus(
      emailExists: map['emailExists'] == true,
      phoneExists: map['phoneExists'] == true,
    );
  }

  final bool emailExists;
  final bool phoneExists;
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.label,
    required this.icon,
    required this.controller,
    this.obscureText = false,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
