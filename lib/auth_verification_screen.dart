import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'phone_login_helper.dart';
import 'utils/app_check_guard.dart';

enum VerificationChannel { phone, email }

enum VerificationPurpose { signIn, register, resetPassword }

class AuthVerificationScreen extends StatefulWidget {
  const AuthVerificationScreen({
    super.key,
    required this.channel,
    required this.identifier,
    required this.password,
    this.purpose = VerificationPurpose.signIn,
    this.autoStart = true,
    this.initialOtpSent = false,
    required this.firebaseEnabled,
  });

  final VerificationChannel channel;
  final String identifier;
  final String password;
  final VerificationPurpose purpose;
  final bool autoStart;
  final bool initialOtpSent;
  final bool firebaseEnabled;

  @override
  State<AuthVerificationScreen> createState() => _AuthVerificationScreenState();
}

class _AuthVerificationScreenState extends State<AuthVerificationScreen> {
  static const Map<String, String> _localizedDigits = <String, String>{
    '๐': '0',
    '๑': '1',
    '๒': '2',
    '๓': '3',
    '๔': '4',
    '๕': '5',
    '๖': '6',
    '๗': '7',
    '๘': '8',
    '๙': '9',
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  bool _isLoading = false;
  bool _isOtpSent = false;
  bool _isResetOtpVerified = false;
  String _verifiedResetOtp = '';
  Timer? _countdownTimer;
  int _countdownSeconds = 0;

  String get _email => widget.identifier.trim();
  String get _normalizedPhone =>
      PhoneLoginHelper.normalize(widget.identifier.trim());
  bool get _isPhoneFlow => widget.channel == VerificationChannel.phone;
  bool get _isRegisterFlow => widget.purpose == VerificationPurpose.register;
  bool get _isResetPasswordFlow =>
      widget.purpose == VerificationPurpose.resetPassword;

  @override
  void initState() {
    super.initState();
    _isOtpSent = widget.initialOtpSent;
    if (!_isPhoneFlow && _isOtpSent) {
      _startCountdown();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.autoStart) {
        return;
      }
      if (_isPhoneFlow) {
        _sendPhoneOtp();
      } else {
        _startEmailVerification();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  String _normalizeOtp(String input) {
    final buffer = StringBuffer();
    for (final rawChar in input.trim().split('')) {
      final mappedChar = _localizedDigits[rawChar] ?? rawChar;
      if (mappedChar.codeUnitAt(0) >= 48 && mappedChar.codeUnitAt(0) <= 57) {
        buffer.write(mappedChar);
      }
    }
    return buffer.toString();
  }

  void _syncNormalizedOtp(String otp) {
    if (_otpController.text == otp) {
      return;
    }
    _otpController.value = TextEditingValue(
      text: otp,
      selection: TextSelection.collapsed(offset: otp.length),
    );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdownSeconds = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _startEmailVerification() async {
    if (!widget.firebaseEnabled) {
      _showSnackBar(
        'Firebase ยังไม่พร้อมใช้งานบนแพลตฟอร์มนี้',
        backgroundColor: Colors.red,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AppCheckGuard.ensureAuthReady();
      final callable = _functions.httpsCallable('sendEmailOtp');
      await callable.call(<String, dynamic>{
        'email': _email,
        'password': widget.password,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _isOtpSent = true;
        _isResetOtpVerified = false;
        _verifiedResetOtp = '';
      });
      _startCountdown();
      _showSnackBar(
        'ส่ง OTP ไปที่ $_email แล้ว',
        backgroundColor: Colors.green,
      );
    } on FirebaseFunctionsException catch (error) {
      _showSnackBar(_mapEmailFunctionError(error), backgroundColor: Colors.red);
    } on MissingPluginException {
      _showSnackBar(
        'ต้องปิดแอปแล้วรันใหม่ 1 ครั้ง เพื่อโหลดระบบ Email OTP',
        backgroundColor: Colors.red,
      );
    } catch (error) {
      _showSnackBar(
        _mapUnexpectedFunctionError(
          error,
          fallback: 'ไม่สามารถส่ง OTP ทางอีเมลได้',
        ),
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkEmailVerified() async {
    if (!widget.firebaseEnabled) {
      return;
    }

    if (_isResetPasswordFlow && _isResetOtpVerified) {
      await _submitNewPassword();
      return;
    }

    final otp = _normalizeOtp(_otpController.text);
    _syncNormalizedOtp(otp);

    if (otp.length != 6) {
      _showSnackBar('กรุณากรอกรหัส OTP 6 หลัก', backgroundColor: Colors.red);
      return;
    }

    if (_isResetPasswordFlow && !_isResetOtpVerified) {
      await _verifyResetPasswordOtp(otp);
      return;
    }

    final targetPassword = widget.password;

    setState(() => _isLoading = true);
    try {
      await AppCheckGuard.ensureAuthReady();
      final verifyCallable = _functions.httpsCallable('verifyEmailOtp');
      final response = await verifyCallable.call(<String, dynamic>{
        'email': _email,
        'otp': otp,
        'password': targetPassword,
        'mode': _isRegisterFlow ? 'register' : 'sign_in',
      });

      final data = response.data;
      final responseMap = data is Map ? Map<Object?, Object?>.from(data) : null;
      final customToken = responseMap?['customToken'];

      if (_isRegisterFlow) {
        if (customToken is String && customToken.trim().isNotEmpty) {
          // Replace any stale anonymous session before switching to the new account.
          await FirebaseAuth.instance.signOut();
          await FirebaseAuth.instance.signInWithCustomToken(customToken);
        } else {
          await FirebaseAuth.instance.currentUser?.reload();
        }
      } else {
        if (customToken is String && customToken.trim().isNotEmpty) {
          await FirebaseAuth.instance.signInWithCustomToken(customToken);
        } else {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _email,
            password: targetPassword,
          );
        }
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (error) {
      _showSnackBar(_mapEmailFunctionError(error), backgroundColor: Colors.red);
    } on MissingPluginException {
      _showSnackBar(
        'ต้องปิดแอปแล้วรันใหม่ 1 ครั้ง เพื่อโหลดระบบ Email OTP',
        backgroundColor: Colors.red,
      );
    } catch (error) {
      _showSnackBar(
        _mapUnexpectedFunctionError(
          error,
          fallback: 'ตรวจสอบสถานะอีเมลไม่สำเร็จ',
        ),
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitNewPassword() async {
    final targetPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (targetPassword.length < 6) {
      _showSnackBar(
        'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร',
        backgroundColor: Colors.red,
      );
      return;
    }
    if (targetPassword != confirmPassword) {
      _showSnackBar(
        'รหัสผ่านใหม่และรหัสยืนยันไม่ตรงกัน',
        backgroundColor: Colors.red,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AppCheckGuard.ensureAuthReady();
      final verifyCallable = _functions.httpsCallable('verifyEmailOtp');
      final payload = <String, dynamic>{
        'email': _email,
        'password': targetPassword,
        'mode': 'reset_password',
      };
      if (_verifiedResetOtp.length == 6) {
        payload['otp'] = _verifiedResetOtp;
      }

      final response = await verifyCallable.call(payload);
      final data = response.data;
      final responseMap = data is Map ? Map<Object?, Object?>.from(data) : null;
      final customToken = responseMap?['customToken'];

      if (customToken is String && customToken.trim().isNotEmpty) {
        await FirebaseAuth.instance.signInWithCustomToken(customToken);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email,
          password: targetPassword,
        );
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'not-found' || error.code == 'deadline-exceeded') {
        setState(() {
          _isResetOtpVerified = false;
          _verifiedResetOtp = '';
        });
      }
      _showSnackBar(_mapEmailFunctionError(error), backgroundColor: Colors.red);
    } on MissingPluginException {
      _showSnackBar(
        'ต้องปิดแอปแล้วรันใหม่ 1 ครั้ง เพื่อโหลดระบบ Email OTP',
        backgroundColor: Colors.red,
      );
    } catch (error) {
      _showSnackBar(
        _mapUnexpectedFunctionError(
          error,
          fallback: 'ตั้งรหัสผ่านใหม่ไม่สำเร็จ',
        ),
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyResetPasswordOtp(String otp) async {
    setState(() => _isLoading = true);
    try {
      await AppCheckGuard.ensureAuthReady();
      final verifyCallable = _functions.httpsCallable('verifyEmailOtp');
      await verifyCallable.call(<String, dynamic>{
        'email': _email,
        'otp': otp,
        'mode': 'reset_password_check',
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _isResetOtpVerified = true;
        _verifiedResetOtp = otp;
      });
      _showSnackBar('OTP ถูกต้อง กรุณาตั้งรหัสผ่านใหม่', backgroundColor: Colors.green);
    } on FirebaseFunctionsException catch (error) {
      _showSnackBar(_mapEmailFunctionError(error), backgroundColor: Colors.red);
    } on MissingPluginException {
      _showSnackBar(
        'ต้องปิดแอปแล้วรันใหม่ 1 ครั้ง เพื่อโหลดระบบ Email OTP',
        backgroundColor: Colors.red,
      );
    } catch (error) {
      _showSnackBar(
        _mapUnexpectedFunctionError(
          error,
          fallback: 'ตรวจสอบ OTP ไม่สำเร็จ',
        ),
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _mapEmailFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'invalid-argument':
        return 'รูปแบบอีเมลหรือรหัส OTP ไม่ถูกต้อง';
      case 'resource-exhausted':
        return 'กรุณารอก่อนขอรหัสใหม่';
      case 'deadline-exceeded':
        return 'OTP หมดอายุแล้ว กรุณาขอรหัสใหม่';
      case 'permission-denied':
        return error.message ?? 'รหัส OTP ไม่ถูกต้อง';
      case 'not-found':
        return error.message ?? 'ไม่พบข้อมูลสำหรับอีเมลนี้';
      case 'failed-precondition':
        return error.message ??
            'ระบบ Email OTP ยังไม่ได้ตั้งค่า SMTP บนเซิร์ฟเวอร์';
      case 'unavailable':
      case 'internal':
        return error.message ??
            'ระบบ Email OTP ฝั่งเซิร์ฟเวอร์ยังไม่พร้อม กรุณาตรวจสอบการ deploy';
      default:
        return error.message ?? 'เกิดข้อผิดพลาดในการยืนยันอีเมล';
    }
  }

  String _mapUnexpectedFunctionError(Object error, {required String fallback}) {
    final message = error.toString();
    if (error is PlatformException ||
        message.contains('Unable to establish connection on channel') ||
        message.contains('CloudFunctionsHostApi.call')) {
      return 'ต้องปิดแอปแล้วเปิดใหม่ก่อนใช้งาน Email OTP';
    }
    if (message.contains('NOT_FOUND') ||
        message.contains('failed-precondition') ||
        message.contains('unavailable')) {
      return 'ระบบ Email OTP ยังไม่พร้อม กรุณาตรวจ SMTP secrets และ deploy Cloud Functions';
    }
    return '$fallback: $error';
  }

  Future<void> _sendPhoneOtp() async {
    if (!widget.firebaseEnabled) {
      _showSnackBar(
        'Firebase ยังไม่พร้อมใช้งานบนแพลตฟอร์มนี้',
        backgroundColor: Colors.red,
      );
      return;
    }

    if (!_normalizedPhone.startsWith('+')) {
      _showSnackBar(
        'รูปแบบเบอร์โทรไม่ถูกต้อง เช่น 0812345678 หรือ +66812345678',
        backgroundColor: Colors.red,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AppCheckGuard.ensureAuthReady();
      final callable = _functions.httpsCallable('sendMerchantPhoneOtp');
      await callable.call(<String, dynamic>{
        'phoneNumber': _normalizedPhone,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _isOtpSent = true;
      });
      _startCountdown();
      _showSnackBar(
        'ส่ง OTP SMS ไปที่ $_normalizedPhone แล้ว',
        backgroundColor: Colors.green,
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      _showSnackBar(_mapPhoneFunctionError(error), backgroundColor: Colors.red);
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      _showSnackBar(
        'ต้องปิดแอปแล้วรันใหม่ 1 ครั้ง เพื่อโหลดระบบ OTP',
        backgroundColor: Colors.red,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      _showSnackBar(
        'ไม่สามารถส่ง OTP ได้: $error',
        backgroundColor: Colors.red,
      );
    }
  }

  String _mapPhoneFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'invalid-argument':
        return error.message ?? 'รหัส OTP ไม่ถูกต้อง';
      case 'failed-precondition':
        return error.message ?? 'กรุณากดส่ง OTP ก่อนยืนยัน';
      case 'deadline-exceeded':
        return error.message ?? 'OTP หมดอายุ กรุณาขอรหัสใหม่';
      case 'resource-exhausted':
        return error.message ?? 'ขอ OTP บ่อยเกินไป กรุณารอแล้วลองใหม่';
      case 'unavailable':
        return error.message ??
            'ไม่สามารถส่ง SMS ได้ ตรวจ Firebase Billing (Blaze) และเปิด Phone sign-in';
      default:
        return error.message ?? 'ส่ง OTP ไม่สำเร็จ';
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final otp = _normalizeOtp(_otpController.text);
    _syncNormalizedOtp(otp);

    if (otp.length != 6) {
      _showSnackBar('กรุณากรอกรหัส OTP 6 หลัก', backgroundColor: Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AppCheckGuard.ensureAuthReady();
      final callable = _functions.httpsCallable('verifyMerchantPhoneOtp');
      final response = await callable.call(<String, dynamic>{
        'phoneNumber': _normalizedPhone,
        'otp': otp,
        'password': widget.password,
      });

      final data = response.data;
      final responseMap = data is Map ? Map<Object?, Object?>.from(data) : null;
      final customToken = responseMap?['customToken'];

      if (customToken is String && customToken.trim().isNotEmpty) {
        await FirebaseAuth.instance.signInWithCustomToken(customToken);
      } else {
        throw Exception('ไม่พบ custom token หลังยืนยัน OTP');
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      _showSnackBar(_mapPhoneFunctionError(error), backgroundColor: Colors.red);
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      _showSnackBar(
        error.message ?? 'ยืนยัน OTP ไม่สำเร็จ',
        backgroundColor: Colors.red,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      _showSnackBar(
        'ยืนยัน OTP ไม่สำเร็จ: $error',
        backgroundColor: Colors.red,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showResetPasswordFormOnly =
        _isResetPasswordFlow && _isResetOtpVerified;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7ED),
      appBar: AppBar(
        title: Text(
          _isPhoneFlow
              ? 'ยืนยันรหัส OTP'
              : _isRegisterFlow
              ? 'ยืนยันอีเมลเพื่อสมัครสมาชิก'
              : showResetPasswordFormOnly
              ? 'ตั้งรหัสผ่านใหม่'
              : _isResetPasswordFlow
              ? 'ตั้งรหัสผ่านใหม่'
              : 'ยืนยันอีเมล',
        ),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!showResetPasswordFormOnly) ...<Widget>[
                Text(
                  _isPhoneFlow
                      ? 'ยืนยันตัวตนด้วยเบอร์โทร'
                      : _isRegisterFlow
                      ? 'ยืนยันอีเมลเพื่อเปิดบัญชีใหม่'
                      : _isResetPasswordFlow
                      ? 'ยืนยัน OTP เพื่อตั้งรหัสผ่านใหม่'
                      : 'ยืนยันตัวตนด้วยอีเมล',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF9A3412),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isPhoneFlow
                      ? (_isRegisterFlow
                        ? 'กรอกรหัส 6 หลักที่ส่งไปที่ $_normalizedPhone เพื่อยืนยันเบอร์โทรของผู้ใช้ใหม่'
                        : 'กรอกรหัส 6 หลักที่ส่งไปที่ $_normalizedPhone ก่อนเข้าสู่ระบบ')
                      : _isResetPasswordFlow
                      ? 'กรอกรหัส 6 หลักที่ส่งไปที่ $_email แล้วตั้งรหัสผ่านใหม่ จากนั้นระบบจะพาเข้าหน้าแรกทันที'
                      : _isRegisterFlow
                      ? 'กรอกรหัส 6 หลักที่ส่งไปที่ $_email เพื่อยืนยันอีเมล จากนั้นระบบจะเปิดบัญชีใหม่และพาเข้าหน้าแรก'
                      : 'กรอกรหัส 6 หลักที่ส่งไปที่ $_email ก่อนเข้าสู่ระบบ',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF7C2D12),
                  ),
                ),
                const SizedBox(height: 28),
              ],
              if (_isPhoneFlow) ...<Widget>[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: (_) {
                    if (_isResetPasswordFlow && _isResetOtpVerified) {
                      setState(() => _isResetOtpVerified = false);
                    }
                  },
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    labelText: 'รหัส OTP 6 หลัก',
                    prefixIcon: const Icon(Icons.password_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (_isLoading || !_isOtpSent)
                        ? null
                        : _verifyPhoneOtp,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF57C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                          _isRegisterFlow ? 'ยืนยันเบอร์โทร' : 'ยืนยันและเข้าสู่ระบบ',
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: (_isLoading || _countdownSeconds > 0)
                      ? null
                      : _sendPhoneOtp,
                  child: Text(
                    _countdownSeconds > 0
                        ? 'ส่งรหัสอีกครั้งใน $_countdownSeconds วินาที'
                        : 'ส่งรหัส OTP อีกครั้ง',
                  ),
                ),
              ] else ...<Widget>[
                if (!showResetPasswordFormOnly) ...<Widget>[
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: 'รหัส OTP 6 หลักจากอีเมล',
                      prefixIcon: const Icon(Icons.mark_email_read_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ถ้ายังไม่เจออีเมล ให้ตรวจสอบโฟลเดอร์ Spam หรือ Promotions ด้วย',
                    style: TextStyle(color: Color(0xFF7C2D12)),
                  ),
                ],
                if (showResetPasswordFormOnly) ...<Widget>[
                  Text(
                    'ตั้งรหัสผ่านใหม่สำหรับ $_email',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF9A3412),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_isResetPasswordFlow && _isResetOtpVerified) ...<Widget>[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่านใหม่',
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'ยืนยันรหัสผ่านใหม่',
                      prefixIcon: const Icon(Icons.verified_user_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (_isLoading || !_isOtpSent)
                        ? null
                        : _checkEmailVerified,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF57C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                          _isResetPasswordFlow
                            ? (_isResetOtpVerified
                              ? 'ตั้งรหัสผ่านใหม่'
                              : 'ตรวจสอบ OTP')
                            : _isRegisterFlow
                            ? 'ยืนยันอีเมลและเปิดบัญชี'
                            : 'ยืนยันและเข้าสู่ระบบ',
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!showResetPasswordFormOnly)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: (_isLoading || _countdownSeconds > 0)
                          ? null
                          : _startEmailVerification,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7C2D12),
                        side: const BorderSide(color: Color(0xFFF57C00)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      child: Text(
                        _countdownSeconds > 0
                            ? 'ส่งรหัสอีกครั้งใน $_countdownSeconds วินาที'
                            : 'ส่งรหัส OTP อีกครั้ง',
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
