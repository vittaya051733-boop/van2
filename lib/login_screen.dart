import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_verification_screen.dart';
import 'category_catalog_screen.dart';
import 'phone_login_helper.dart';

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
      _showSnackBar(error.message ?? 'ตรวจสอบข้อมูลเข้าสู่ระบบไม่สำเร็จ');
      return null;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      _showSnackBar('ตรวจสอบข้อมูลเข้าสู่ระบบไม่สำเร็จ: $error');
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
          title: const Text('ลืมรหัสผ่าน'),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'อีเมล',
              hintText: 'name@example.com',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                final value = emailController.text.trim();
                if (!_isEmailIdentifier(value)) {
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('ส่ง OTP'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startForgotPasswordFlow() async {
    if (!widget.firebaseEnabled) {
      _showSnackBar('Firebase ยังไม่พร้อมใช้งานบนแพลตฟอร์มนี้');
      return;
    }

    final email = await _askForResetEmail();

    if (!mounted || email == null || email.isEmpty) {
      return;
    }

    if (!_isEmailIdentifier(email)) {
      _showSnackBar('กรุณากรอกอีเมลที่ถูกต้อง');
      return;
    }

    _identifierController.text = email;

    setState(() => _isSigningIn = true);
    try {
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
      _showSnackBar('ต้องปิดแอปแล้วรันใหม่ 1 ครั้ง เพื่อโหลดระบบ Email OTP');
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('ไม่สามารถส่ง OTP ทางอีเมลได้: $error');
      return;
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }

    if (!mounted) {
      return;
    }

    _showSnackBar('ส่ง OTP ไปที่ $email แล้ว');

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
      _showSnackBar('กรุณากรอกอีเมลหรือเบอร์โทร และรหัสผ่านให้ครบ');
      return;
    }

    if (!widget.firebaseEnabled) {
      _showSnackBar('Firebase ยังไม่พร้อมใช้งานบนแพลตฟอร์มนี้');
      return;
    }

    if (!isEmail && !normalizedPhone.startsWith('+')) {
      _showSnackBar('กรุณากรอกเบอร์โทรให้ถูกต้อง');
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
        throw Exception('ไม่พบข้อมูลผู้ใช้หลังเข้าสู่ระบบ');
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
        _showSnackBar('กรุณายืนยัน OTP ก่อนเข้าสู่ระบบครั้งแรก');
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

      _showSnackBar('เข้าสู่ระบบด้วยอีเมลไม่สำเร็จ: $error');
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

      _showSnackBar('เข้าสู่ระบบสำเร็จ (ไม่ต้องยืนยัน OTP)');
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
        _showSnackBar('กรุณายืนยัน OTP ก่อนเข้าสู่ระบบครั้งแรก');
        return false;
      }

      if (
        error.code == 'permission-denied' ||
        error.code == 'invalid-argument'
      ) {
        _showSnackBar(message.isNotEmpty ? message : 'เบอร์โทรหรือรหัสผ่านไม่ถูกต้อง');
        return null;
      }

      _showSnackBar(message.isNotEmpty ? message : 'เข้าสู่ระบบด้วยเบอร์มือถือไม่สำเร็จ');
      return null;
    } catch (error) {
      if (!mounted) {
        return null;
      }

      _showSnackBar('เข้าสู่ระบบด้วยเบอร์มือถือไม่สำเร็จ: $error');
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

  void _completeLogin() {
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
      _showSnackBar('Firebase ยังไม่พร้อมใช้งานบนแพลตฟอร์มนี้');
      return;
    }

    setState(() => _isSigningIn = true);

    try {
      UserCredential credential;
      if (kIsWeb) {
        credential = await FirebaseAuth.instance.signInWithPopup(
          GoogleAuthProvider(),
        );
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
            ? 'เข้าสู่ระบบสำเร็จ: ${user!.displayName}'
            : 'เข้าสู่ระบบด้วย Google สำเร็จ',
      );

      _completeLogin();
    } on FirebaseAuthException catch (error) {
      _showSnackBar(
        'เข้าสู่ระบบด้วย Google ไม่สำเร็จ: ${error.message ?? error.code}',
      );
    } catch (error) {
      _showSnackBar('เข้าสู่ระบบด้วย Google ไม่สำเร็จ: $error');
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
        return 'รูปแบบอีเมลไม่ถูกต้อง';
      case 'resource-exhausted':
        return 'กรุณารอก่อนขอรหัสใหม่';
      case 'failed-precondition':
        return 'ระบบ Email OTP ยังไม่ได้ตั้งค่า SMTP บนเซิร์ฟเวอร์';
      case 'unavailable':
      case 'internal':
        return error.message ?? 'ระบบ Email OTP ฝั่งเซิร์ฟเวอร์ยังไม่พร้อม';
      default:
        return error.message ?? 'ส่ง OTP ทางอีเมลไม่สำเร็จ';
    }
  }

  String _mapEmailPasswordSignInError(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
        return 'ไม่พบบัญชีอีเมลนี้ในระบบ';
      case 'wrong-password':
      case 'invalid-credential':
        return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
      case 'invalid-email':
        return 'รูปแบบอีเมลไม่ถูกต้อง';
      case 'user-disabled':
        return 'บัญชีนี้ถูกปิดการใช้งาน';
      default:
        return error.message ?? 'เข้าสู่ระบบด้วยอีเมลไม่สำเร็จ';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7ED),
      appBar: AppBar(
        title: const Text('เข้าสู่ระบบ'),
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
                'เข้าสู่ระบบเพื่อใช้งาน ${widget.categoryLabel}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF9A3412),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.serviceType == null
                    ? 'กรอกอีเมลหรือเบอร์โทรอย่างใดอย่างหนึ่งเพื่อเข้าสู่ระบบหรือสมัครครั้งแรก'
                    : 'หมวดที่เลือก: ${widget.serviceType} • กรอกอีเมลหรือเบอร์โทรอย่างใดอย่างหนึ่งได้',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF7C2D12),
                ),
              ),
              const SizedBox(height: 28),
              _LoginTextField(
                label: 'อีเมล หรือ เบอร์โทรศัพท์',
                icon: Icons.person_outline,
                controller: _identifierController,
              ),
              const SizedBox(height: 16),
              _LoginTextField(
                label: 'รหัสผ่าน',
                icon: Icons.lock_outline,
                obscureText: true,
                controller: _passwordController,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isSigningIn ? null : _startForgotPasswordFlow,
                  child: const Text('ลืมรหัสผ่าน?'),
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
                  child: const Text('เข้าสู่ระบบ'),
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
                        ? 'กำลังเข้าสู่ระบบ...'
                        : 'เข้าสู่ระบบด้วย Google',
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
    this.keyboardType,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
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
