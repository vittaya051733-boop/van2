import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Centralized Thai/English strings for van2 customer app.
class L10n {
  L10n._();

  static bool get en => LocaleService.instance.isEnglish;

  // ---------------------------------------------------------------------------
  // Locale / common
  // ---------------------------------------------------------------------------

  static String localeLabel(Locale value) =>
      value.languageCode == 'en' ? languageEnglish : languageThai;

  static String get languageEnglish => 'English';
  static String get languageThai => 'ไทย';

  static String get cancel => en ? 'Cancel' : 'ยกเลิก';
  static String get submit => en ? 'Submit' : 'ส่ง';
  static String get continueAction => en ? 'Continue' : 'ดำเนินการต่อ';
  static String get optional => en ? 'Optional' : 'ไม่บังคับ';
  static String get defaultUser => en ? 'User' : 'ผู้ใช้';
  static String get userFallback => defaultUser;
  static String get productFallback => en ? 'Product' : 'สินค้า';
  static String get shopFallback => en ? 'Shop' : 'ร้านค้า';
  static String get thaiLabel => languageThai;
  static String get englishLabel => languageEnglish;
  static String get close => en ? 'Close' : 'ปิด';
  static String get confirm => en ? 'Confirm' : 'ยืนยัน';
  static String get pay => en ? 'Pay' : 'ชำระ';
  static String get shareAction => en ? 'Share' : 'แชร์';
  static String get all => en ? 'All' : 'ทั้งหมด';
  static String get history => en ? 'History' : 'ประวัติ';
  static String get mapLabel => en ? 'Map' : 'แผนที่';
  static String get save => en ? 'Save' : 'บันทึก';
  static String get edit => en ? 'Edit' : 'แก้ไข';
  static String get signInRequired => en ? 'Please sign in' : 'กรุณาเข้าสู่ระบบ';
  static String get signInRequiredFirst =>
      en ? 'Please sign in first' : 'กรุณาเข้าสู่ระบบก่อน';
  static String get loading => en ? 'Loading...' : 'กำลังโหลด...';
  static String get calculating => en ? 'Calculating...' : 'กำลังคำนวณ...';
  static String get tryAgain => en ? 'Try again' : 'ลองใหม่';
  static String get acknowledge => en ? 'Got it' : 'รับทราบ';
  static String get rider => en ? 'Rider' : 'ไรเดอร์';
  static String get customer => en ? 'Customer' : 'ลูกค้า';
  static String get now => en ? 'Now' : 'ตอนนี้';
  static String get total => en ? 'Total' : 'ยอดรวม';
  static String get nationwideShipping =>
      en ? 'Nationwide shipping' : 'สินค้าส่งทั่วประเทศ';

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  static String get settingsTitle => en ? 'Settings' : 'ตั้งค่า';
  static String get helpSection => en ? 'Help' : 'ช่วยเหลือ';
  static String get helpCenter => en ? 'Help center' : 'ศูนย์ช่วยเหลือ';
  static String get contactAdmin => en ? 'Contact admin' : 'ติดต่อแอดมิน';
  static String get adminMessages => en ? 'Messages to admin' : 'ข้อความถึงแอดมิน';
  static String get adminMessagesSubtitle => en
      ? 'View admin replies and respond'
      : 'ดูคำตอบจากแอดมินและตอบกลับ';
  static String get securitySection => en ? 'Security' : 'ความปลอดภัย';
  static String get privacySecurity =>
      en ? 'Privacy & security' : 'ความเป็นส่วนตัวและความปลอดภัย';
  static String get languageSection => en ? 'Language' : 'ตั้งค่าภาษา';
  static String get language => en ? 'Language' : 'ภาษา';
  static String get accountSection => en ? 'Account' : 'บัญชี';
  static String get logout => en ? 'Sign out' : 'ออกจากระบบ';
  static String get loggingOut => en ? 'Signing out...' : 'กำลังออกจากระบบ...';
  static String get logoutTitle => en ? 'Sign out' : 'ออกจากระบบ';
  static String get logoutConfirm =>
      en ? 'Do you want to sign out?' : 'คุณต้องการออกจากระบบใช่หรือไม่';
  static String get chooseLanguage => en ? 'Choose language' : 'เลือกภาษา';

  // ---------------------------------------------------------------------------
  // Login / auth
  // ---------------------------------------------------------------------------

  static String get signIn => en ? 'Sign in' : 'เข้าสู่ระบบ';
  static String get email => en ? 'Email' : 'อีเมล';
  static String get emailOrPhone =>
      en ? 'Email or phone' : 'อีเมล หรือ เบอร์โทรศัพท์';
  static String get password => en ? 'Password' : 'รหัสผ่าน';
  static String get forgotPassword => en ? 'Forgot password' : 'ลืมรหัสผ่าน';
  static String get forgotPasswordQuestion =>
      en ? 'Forgot password?' : 'ลืมรหัสผ่าน?';
  static String get sendOtp => en ? 'Send OTP' : 'ส่ง OTP';
  static String get signInWithGoogle =>
      en ? 'Sign in with Google' : 'เข้าสู่ระบบด้วย Google';
  static String get signingIn => en ? 'Signing in...' : 'กำลังเข้าสู่ระบบ...';

  static String signInToUseCategory(String categoryLabel) => en
      ? 'Sign in to use $categoryLabel'
      : 'เข้าสู่ระบบเพื่อใช้งาน $categoryLabel';

  static String get signInHintNoServiceType => en
      ? 'Enter email or phone to sign in or register for the first time'
      : 'กรอกอีเมลหรือเบอร์โทรอย่างใดอย่างหนึ่งเพื่อเข้าสู่ระบบหรือสมัครครั้งแรก';

  static String signInHintWithServiceType(String serviceType) => en
      ? 'Selected category: $serviceType • Enter email or phone'
      : 'หมวดที่เลือก: $serviceType • กรอกอีเมลหรือเบอร์โทรอย่างใดอย่างหนึ่งได้';

  static String signInSuccessWithName(String name) =>
      en ? 'Signed in: $name' : 'เข้าสู่ระบบสำเร็จ: $name';

  static String get signInSuccessGoogle =>
      en ? 'Signed in with Google' : 'เข้าสู่ระบบด้วย Google สำเร็จ';

  static String googleSignInFailed(String message) => en
      ? 'Google sign-in failed: $message'
      : 'เข้าสู่ระบบด้วย Google ไม่สำเร็จ: $message';

  static String get lookupIdentifierFailed =>
      en ? 'Unable to verify sign-in details' : 'ตรวจสอบข้อมูลเข้าสู่ระบบไม่สำเร็จ';

  static String lookupIdentifierFailedWithError(Object error) => en
      ? 'Unable to verify sign-in details: $error'
      : 'ตรวจสอบข้อมูลเข้าสู่ระบบไม่สำเร็จ: $error';

  static String get firebaseNotReady => en
      ? 'Firebase is not ready on this platform'
      : 'Firebase ยังไม่พร้อมใช้งานบนแพลตฟอร์มนี้';

  static String get pleaseEnterValidEmail =>
      en ? 'Please enter a valid email' : 'กรุณากรอกอีเมลที่ถูกต้อง';

  static String get emailOtpRestartApp => en
      ? 'Close and reopen the app once to load Email OTP'
      : 'ต้องปิดแอปแล้วรันใหม่ 1 ครั้ง เพื่อโหลดระบบ Email OTP';

  static String cannotSendEmailOtp(Object error) => en
      ? 'Unable to send email OTP: $error'
      : 'ไม่สามารถส่ง OTP ทางอีเมลได้: $error';

  static String otpSentToEmail(String email) =>
      en ? 'OTP sent to $email' : 'ส่ง OTP ไปที่ $email แล้ว';

  static String get pleaseEnterEmailOrPhoneAndPassword => en
      ? 'Please enter email or phone and password'
      : 'กรุณากรอกอีเมลหรือเบอร์โทร และรหัสผ่านให้ครบ';

  static String get pleaseEnterValidPhone =>
      en ? 'Please enter a valid phone number' : 'กรุณากรอกเบอร์โทรให้ถูกต้อง';

  static String get userNotFoundAfterSignIn => en
      ? 'User not found after sign-in'
      : 'ไม่พบข้อมูลผู้ใช้หลังเข้าสู่ระบบ';

  static String get pleaseVerifyOtpFirst => en
      ? 'Please verify OTP before your first sign-in'
      : 'กรุณายืนยัน OTP ก่อนเข้าสู่ระบบครั้งแรก';

  static String emailSignInFailedWithError(Object error) => en
      ? 'Email sign-in failed: $error'
      : 'เข้าสู่ระบบด้วยอีเมลไม่สำเร็จ: $error';

  static String get signInSuccessNoOtp => en
      ? 'Signed in (OTP not required)'
      : 'เข้าสู่ระบบสำเร็จ (ไม่ต้องยืนยัน OTP)';

  static String get phoneOrPasswordIncorrect =>
      en ? 'Incorrect phone or password' : 'เบอร์โทรหรือรหัสผ่านไม่ถูกต้อง';

  static String get phoneSignInFailed =>
      en ? 'Phone sign-in failed' : 'เข้าสู่ระบบด้วยเบอร์มือถือไม่สำเร็จ';

  static String phoneSignInFailedWithError(Object error) => en
      ? 'Phone sign-in failed: $error'
      : 'เข้าสู่ระบบด้วยเบอร์มือถือไม่สำเร็จ: $error';

  static String get invalidEmailFormat =>
      en ? 'Invalid email format' : 'รูปแบบอีเมลไม่ถูกต้อง';

  static String get waitBeforeNewCode =>
      en ? 'Please wait before requesting a new code' : 'กรุณารอก่อนขอรหัสใหม่';

  static String get emailOtpSmtpNotConfigured => en
      ? 'Email OTP SMTP is not configured on the server'
      : 'ระบบ Email OTP ยังไม่ได้ตั้งค่า SMTP บนเซิร์ฟเวอร์';

  static String get emailOtpServerNotReady => en
      ? 'Email OTP server is not ready'
      : 'ระบบ Email OTP ฝั่งเซิร์ฟเวอร์ยังไม่พร้อม';

  static String get sendEmailOtpFailed =>
      en ? 'Failed to send email OTP' : 'ส่ง OTP ทางอีเมลไม่สำเร็จ';

  static String get emailAccountNotFound =>
      en ? 'Email account not found' : 'ไม่พบบัญชีอีเมลนี้ในระบบ';

  static String get emailOrPasswordIncorrect =>
      en ? 'Incorrect email or password' : 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';

  static String get accountDisabled =>
      en ? 'This account has been disabled' : 'บัญชีนี้ถูกปิดการใช้งาน';

  static String get emailSignInFailed =>
      en ? 'Email sign-in failed' : 'เข้าสู่ระบบด้วยอีเมลไม่สำเร็จ';

  // ---------------------------------------------------------------------------
  // Auth verification (OTP)
  // ---------------------------------------------------------------------------

  static String get verifyOtpTitle => en ? 'Verify OTP' : 'ยืนยันรหัส OTP';
  static String get verifyEmailRegisterTitle => en
      ? 'Verify email to register'
      : 'ยืนยันอีเมลเพื่อสมัครสมาชิก';
  static String get setNewPasswordTitle =>
      en ? 'Set new password' : 'ตั้งรหัสผ่านใหม่';
  static String get verifyEmailTitle => en ? 'Verify email' : 'ยืนยันอีเมล';

  static String get verifyPhoneIdentity =>
      en ? 'Verify with phone number' : 'ยืนยันตัวตนด้วยเบอร์โทร';

  static String get verifyEmailNewAccount => en
      ? 'Verify email to create a new account'
      : 'ยืนยันอีเมลเพื่อเปิดบัญชีใหม่';

  static String get verifyOtpResetPassword => en
      ? 'Verify OTP to reset password'
      : 'ยืนยัน OTP เพื่อตั้งรหัสผ่านใหม่';

  static String get verifyEmailIdentity =>
      en ? 'Verify with email' : 'ยืนยันตัวตนด้วยอีเมล';

  static String phoneRegisterOtpHint(String phone) => en
      ? 'Enter the 6-digit code sent to $phone to verify the new phone number'
      : 'กรอกรหัส 6 หลักที่ส่งไปที่ $phone เพื่อยืนยันเบอร์โทรของผู้ใช้ใหม่';

  static String phoneSignInOtpHint(String phone) => en
      ? 'Enter the 6-digit code sent to $phone before signing in'
      : 'กรอกรหัส 6 หลักที่ส่งไปที่ $phone ก่อนเข้าสู่ระบบ';

  static String resetPasswordOtpHint(String email) => en
      ? 'Enter the 6-digit code sent to $email, set a new password, then you will go to the home screen'
      : 'กรอกรหัส 6 หลักที่ส่งไปที่ $email แล้วตั้งรหัสผ่านใหม่ จากนั้นระบบจะพาเข้าหน้าแรกทันที';

  static String registerEmailOtpHint(String email) => en
      ? 'Enter the 6-digit code sent to $email to verify email, then your account will be created'
      : 'กรอกรหัส 6 หลักที่ส่งไปที่ $email เพื่อยืนยันอีเมล จากนั้นระบบจะเปิดบัญชีใหม่และพาเข้าหน้าแรก';

  static String signInEmailOtpHint(String email) => en
      ? 'Enter the 6-digit code sent to $email before signing in'
      : 'กรอกรหัส 6 หลักที่ส่งไปที่ $email ก่อนเข้าสู่ระบบ';

  static String get otpSixDigits => en ? '6-digit OTP' : 'รหัส OTP 6 หลัก';
  static String get otpSixDigitsFromEmail =>
      en ? '6-digit OTP from email' : 'รหัส OTP 6 หลักจากอีเมล';

  static String get checkSpamFolder => en
      ? 'If you do not see the email, check Spam or Promotions folders'
      : 'ถ้ายังไม่เจออีเมล ให้ตรวจสอบโฟลเดอร์ Spam หรือ Promotions ด้วย';

  static String setNewPasswordFor(String email) => en
      ? 'Set a new password for $email'
      : 'ตั้งรหัสผ่านใหม่สำหรับ $email';

  static String get newPassword => en ? 'New password' : 'รหัสผ่านใหม่';
  static String get confirmNewPassword =>
      en ? 'Confirm new password' : 'ยืนยันรหัสผ่านใหม่';

  static String get verifyPhone => en ? 'Verify phone' : 'ยืนยันเบอร์โทร';
  static String get verifyAndSignIn =>
      en ? 'Verify and sign in' : 'ยืนยันและเข้าสู่ระบบ';
  static String get checkOtp => en ? 'Check OTP' : 'ตรวจสอบ OTP';
  static String get setNewPassword =>
      en ? 'Set new password' : 'ตั้งรหัสผ่านใหม่';
  static String get verifyEmailAndCreateAccount => en
      ? 'Verify email and create account'
      : 'ยืนยันอีเมลและเปิดบัญชี';

  static String resendOtpIn(int seconds) => en
      ? 'Resend code in $seconds seconds'
      : 'ส่งรหัสอีกครั้งใน $seconds วินาที';

  static String get resendOtp => en ? 'Resend OTP' : 'ส่งรหัส OTP อีกครั้ง';

  static String get pleaseEnterOtpSixDigits =>
      en ? 'Please enter a 6-digit OTP' : 'กรุณากรอกรหัส OTP 6 หลัก';

  static String get verifyEmailStatusFailed =>
      en ? 'Failed to verify email status' : 'ตรวจสอบสถานะอีเมลไม่สำเร็จ';

  static String get newPasswordMinSix => en
      ? 'New password must be at least 6 characters'
      : 'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร';

  static String get newPasswordMismatch => en
      ? 'New password and confirmation do not match'
      : 'รหัสผ่านใหม่และรหัสยืนยันไม่ตรงกัน';

  static String get resetPasswordFailed =>
      en ? 'Failed to reset password' : 'ตั้งรหัสผ่านใหม่ไม่สำเร็จ';

  static String get otpVerifiedSetNewPassword => en
      ? 'OTP verified — please set a new password'
      : 'OTP ถูกต้อง กรุณาตั้งรหัสผ่านใหม่';

  static String get verifyOtpFailed =>
      en ? 'OTP verification failed' : 'ตรวจสอบ OTP ไม่สำเร็จ';

  static String get invalidEmailOrOtp =>
      en ? 'Invalid email or OTP format' : 'รูปแบบอีเมลหรือรหัส OTP ไม่ถูกต้อง';

  static String get otpExpired =>
      en ? 'OTP expired — request a new code' : 'OTP หมดอายุแล้ว กรุณาขอรหัสใหม่';

  static String get invalidOtp =>
      en ? 'Incorrect OTP' : 'รหัส OTP ไม่ถูกต้อง';

  static String get emailNotFoundForOtp => en
      ? 'No data found for this email'
      : 'ไม่พบข้อมูลสำหรับอีเมลนี้';

  static String get emailVerificationFailed =>
      en ? 'Email verification failed' : 'เกิดข้อผิดพลาดในการยืนยันอีเมล';

  static String get emailOtpRestartAppAlt => en
      ? 'Close and reopen the app before using Email OTP'
      : 'ต้องปิดแอปแล้วเปิดใหม่ก่อนใช้งาน Email OTP';

  static String get emailOtpNotReady => en
      ? 'Email OTP is not ready — check SMTP secrets and deploy Cloud Functions'
      : 'ระบบ Email OTP ยังไม่พร้อม กรุณาตรวจ SMTP secrets และ deploy Cloud Functions';

  static String unexpectedFunctionError(Object error, {required String fallback}) {
    final message = error.toString();
    if (message.contains('Unable to establish connection on channel') ||
        message.contains('CloudFunctionsHostApi.call')) {
      return emailOtpRestartAppAlt;
    }
    if (message.contains('NOT_FOUND') ||
        message.contains('failed-precondition') ||
        message.contains('unavailable')) {
      return emailOtpNotReady;
    }
    return en ? '$fallback: $error' : '$fallback: $error';
  }

  static String get invalidPhoneFormat => en
      ? 'Invalid phone format — e.g. 0812345678 or +66812345678'
      : 'รูปแบบเบอร์โทรไม่ถูกต้อง เช่น 0812345678 หรือ +66812345678';

  static String otpSmsSentTo(String phone) =>
      en ? 'OTP SMS sent to $phone' : 'ส่ง OTP SMS ไปที่ $phone แล้ว';

  static String cannotSendOtp(Object error) =>
      en ? 'Unable to send OTP: $error' : 'ไม่สามารถส่ง OTP ได้: $error';

  static String get otpRestartApp => en
      ? 'Close and reopen the app once to load OTP'
      : 'ต้องปิดแอปแล้วรันใหม่ 1 ครั้ง เพื่อโหลดระบบ OTP';

  static String get verifyOtpFailedGeneric =>
      en ? 'OTP verification failed' : 'ยืนยัน OTP ไม่สำเร็จ';

  static String verifyOtpFailedWithError(Object error) => en
      ? 'OTP verification failed: $error'
      : 'ยืนยัน OTP ไม่สำเร็จ: $error';

  static String get customTokenNotFoundAfterOtp => en
      ? 'Custom token not found after OTP verification'
      : 'ไม่พบ custom token หลังยืนยัน OTP';

  static String get sendOtpBeforeVerify => en
      ? 'Please send OTP before verifying'
      : 'กรุณากดส่ง OTP ก่อนยืนยัน';

  static String get otpExpiredResend => en
      ? 'OTP expired — request a new code'
      : 'OTP หมดอายุ กรุณาขอรหัสใหม่';

  static String get otpTooFrequent => en
      ? 'OTP requested too often — please wait and try again'
      : 'ขอ OTP บ่อยเกินไป กรุณารอแล้วลองใหม่';

  static String get smsUnavailable => en
      ? 'Unable to send SMS — check Firebase Billing (Blaze) and enable Phone sign-in'
      : 'ไม่สามารถส่ง SMS ได้ ตรวจ Firebase Billing (Blaze) และเปิด Phone sign-in';

  static String get sendOtpFailed =>
      en ? 'Failed to send OTP' : 'ส่ง OTP ไม่สำเร็จ';

  static String get cannotSendEmailOtpGeneric =>
      en ? 'Unable to send email OTP' : 'ไม่สามารถส่ง OTP ทางอีเมลได้';

  // ---------------------------------------------------------------------------
  // Privacy / legal
  // ---------------------------------------------------------------------------

  static String get privacyOnboardingTitle =>
      en ? 'Privacy and terms' : 'ความเป็นส่วนตัวและข้อกำหนด';

  static String get privacyOnboardingIntro => en
      ? 'Please review how VANTALAD uses your data before continuing.'
      : 'โปรดอ่านการใช้ข้อมูลส่วนบุคคลของ VANTALAD ก่อนใช้งานต่อ';

  static String get privacyPolicy =>
      en ? 'Privacy policy' : 'นโยบายความเป็นส่วนตัว';
  static String get termsOfService =>
      en ? 'Terms of service' : 'ข้อกำหนดการใช้งาน';
  static String get dataWeCollect =>
      en ? 'Data we collect' : 'ข้อมูลที่เราเก็บ';
  static String get lastUpdated => en ? 'Last updated' : 'อัปเดตล่าสุด';

  static String lastUpdatedWithDate(String date) =>
      en ? 'Last updated: $date' : 'อัปเดตล่าสุด: $date';

  static String get privacyAcceptRequired => en
      ? 'I accept the Terms of Service and Privacy Policy (required)'
      : 'ยอมรับข้อกำหนดการใช้งานและนโยบายความเป็นส่วนตัว (จำเป็น)';

  static String get privacyOrderNotificationsOptional => en
      ? 'Order status notifications'
      : 'รับการแจ้งเตือนสถานะออเดอร์';

  static String get privacyOrderNotificationsOptionalSubtitle => en
      ? 'Optional — you can change this later in Settings'
      : 'ไม่บังคับ — เปลี่ยนได้ภายหลังในตั้งค่า';

  static String get privacyPromotionsOptional => en
      ? 'Promotions and special offers'
      : 'รับข่าวโปรโมชันและสิทธิพิเศษ';

  static String get privacyMarketingOptionalSubtitle => en
      ? 'Optional marketing messages'
      : 'ข้อความการตลาด (ไม่บังคับ)';

  static String get privacyMustAcceptGate => en
      ? 'You must accept the terms and privacy policy before use'
      : 'ต้องยอมรับข้อกำหนดและนโยบายความเป็นส่วนตัวก่อนใช้งาน';

  static String get privacyReviewTermsAgain =>
      en ? 'Review terms again' : 'ดูข้อกำหนดอีกครั้ง';

  static String get privacyTitle =>
      en ? 'Privacy & security' : 'ความเป็นส่วนตัวและความปลอดภัย';

  static String get consentPreferences =>
      en ? 'Consent preferences' : 'การตั้งค่าความยินยอม';

  static String get pushNotifications =>
      en ? 'Order notifications' : 'แจ้งเตือนสถานะออเดอร์';

  static String get pushNotificationsSubtitle => en
      ? 'Optional push alerts for orders and messages'
      : 'การแจ้งเตือนออเดอร์และข้อความ (ไม่บังคับ)';

  static String get marketingMessages =>
      en ? 'Promotions' : 'ข่าวโปรโมชัน';

  static String get marketingMessagesSubtitle => en
      ? 'Optional marketing messages'
      : 'ข้อความการตลาด (ไม่บังคับ)';

  static String get privacyRights =>
      en ? 'Your privacy rights' : 'สิทธิข้อมูลส่วนบุคคล';

  static String get requestDataExport =>
      en ? 'Request data export' : 'ขอส่งออกข้อมูล';

  static String get requestDataExportSubtitle => en
      ? 'Receive a copy of your personal data'
      : 'ขอรับสำเนาข้อมูลส่วนบุคคลของคุณ';

  static String get requestDataCorrection =>
      en ? 'Request data correction' : 'ขอแก้ไขข้อมูล';

  static String get requestDataCorrectionSubtitle => en
      ? 'Ask us to correct inaccurate data'
      : 'ขอให้แก้ไขข้อมูลที่ไม่ถูกต้อง';

  static String get requestAccountDeletion =>
      en ? 'Request account deletion' : 'ขอลบบัญชี';

  static String get requestAccountDeletionSubtitle => en
      ? 'Submit a deletion request to admin'
      : 'ส่งคำขอลบบัญชีและข้อมูลไปยังแอดมิน';

  static String get managePermissions =>
      en ? 'App permissions' : 'จัดการสิทธิ์แอป';

  static String get managePermissionsSubtitle => en
      ? 'Location, notifications, camera'
      : 'ตำแหน่ง แจ้งเตือน กล้อง';

  static String get appVersion => en ? 'App version' : 'เวอร์ชันแอป';

  static String get openAppSettings =>
      en ? 'Open system app settings' : 'เปิดตั้งค่าแอปของระบบ';

  static String saveNotificationSettingsFailed(Object error) => en
      ? 'Failed to save notification settings: $error'
      : 'บันทึกการตั้งค่าแจ้งเตือนไม่สำเร็จ: $error';

  static String saveMarketingSettingsFailed(Object error) => en
      ? 'Failed to save marketing settings: $error'
      : 'บันทึกการตั้งค่าการตลาดไม่สำเร็จ: $error';

  static String get privacyRequestSignInRequired => en
      ? 'Please sign in before submitting a request'
      : 'กรุณาเข้าสู่ระบบก่อนส่งคำขอ';

  static String get privacyRequestConfirmBody => en
      ? 'We will create a privacy request and notify admin. Continue?'
      : 'ระบบจะสร้างคำขอ PDPA และแจ้งแอดมิน ต้องการดำเนินการต่อหรือไม่?';

  static String privacyRequestSubmitted(String requestId) => en
      ? 'Request submitted ($requestId)'
      : 'ส่งคำขอแล้ว ($requestId)';

  static String privacyRequestFailed(Object error) =>
      en ? 'Request failed: $error' : 'ส่งคำขอไม่สำเร็จ: $error';

  // ---------------------------------------------------------------------------
  // Catalog / products
  // ---------------------------------------------------------------------------

  static String get catalogNoProductsYet =>
      en ? 'No products yet' : 'ยังไม่มีสินค้า';
  static String get catalogDiscountProducts =>
      en ? 'Discounted products' : 'สินค้าส่วนลด';
  static String get catalogUnnamedProduct =>
      en ? 'Unnamed product' : 'ไม่ระบุชื่อสินค้า';
  static String get catalogSearchProducts =>
      en ? 'Search products' : 'ค้นหาสินค้า';
  static String get catalogSearchNationwide => en
      ? 'Search nationwide shipping products'
      : 'ค้นหาสินค้าส่งทั่วประเทศ';
  static String get catalogSearchInShop =>
      en ? 'Search products in this shop' : 'ค้นหาสินค้าในร้านนี้';
  static String catalogSearchInCategory(String title) => en
      ? 'Search products in $title'
      : 'ค้นหาสินค้าในหมวด$title';
  static String catalogLoadFailed(Object error) =>
      en ? 'Failed to load: $error' : 'โหลดข้อมูลไม่สำเร็จ: $error';
  static String catalogNoSearchResults(String query) => en
      ? 'No products matching "$query"'
      : 'ไม่พบสินค้าที่ตรงกับ "$query"';
  static String get catalogShopNoActiveProducts => en
      ? 'This shop has no active products available to order right now'
      : 'ร้านนี้ยังไม่มีสินค้า active ให้สั่งออนไลน์ตอนนี้';
  static String get catalogCategoryEmpty => en
      ? 'No open shops in this category yet, or shops have not listed products'
      : 'ยังไม่มีร้านที่เปิดอยู่ในหมวดนี้ หรือร้านยังไม่ได้เลือกสินค้าแสดง';
  static String get catalogSearchPrompt => en
      ? 'Type a product, shop, or category to search'
      : 'พิมพ์ชื่อสินค้า ร้าน หรือประเภทสินค้าเพื่อค้นหา';
  static String get catalogRecentReviews =>
      en ? 'Recent reviews' : 'รีวิวล่าสุด';
  static String get catalogFilterAll => en ? 'All' : 'ทั้งหมด';
  static String get catalogNewBadge => en ? 'New' : 'ใหม่';
  static String catalogShopPager(int current, int total) =>
      en ? 'Shop $current / $total' : 'ร้าน $current / $total';
  static String get catalogSwipeShopHint => en
      ? 'Swipe left/right to change shop, or scroll down for the next shop'
      : 'ปัดซ้าย-ขวาเพื่อเปลี่ยนร้าน หรือเลื่อนลงเพื่อดูร้านถัดไป';
  static String catalogDistanceAway(String distance) =>
      en ? '$distance away' : 'ห่าง $distance';
  static String catalogSwipeProductHint(int current, int total) => en
      ? 'Swipe left/right for other products ($current/$total)'
      : 'ปัดซ้าย/ขวาเพื่อดูสินค้าอื่น ($current/$total)';
  static String catalogAddedToCart(int quantity) => en
      ? 'Added $quantity item(s) to cart'
      : 'เพิ่ม $quantity ชิ้นลงตะกร้าแล้ว';
  static String get catalogGoToCart => en ? 'Go to cart' : 'ไปที่ตะกร้า';
  static String get catalogColor => en ? 'Color' : 'สี';
  static String get catalogSize => en ? 'Size' : 'ขนาด';
  static String get catalogSelectVariant => en
      ? 'Please select product options'
      : 'กรุณาเลือกตัวเลือกสินค้า';
  static String catalogPrepTime(int minutes) => en
      ? 'Preparation time: about $minutes min'
      : 'เวลาเตรียมสินค้า: ประมาณ $minutes นาที';
  static String catalogDeliveryEta(int minutes, String distance) => en
      ? 'Estimated delivery: about $minutes min ($distance away)'
      : 'เวลาส่งถึงคุณ: ประมาณ $minutes นาที (ห่าง $distance)';
  static String catalogStockRemaining(int count) =>
      en ? 'Stock left: $count' : 'สต๊อกคงเหลือ: $count';
  static String get catalogStockUnlimited =>
      en ? 'Stock left: unlimited' : 'สต๊อกคงเหลือ: ไม่จำกัด';
  static String get catalogOutOfStock =>
      en ? 'Temporarily out of stock' : 'สินค้าหมดสต๊อกชั่วคราว';
  static String catalogStockAfterOrder(int count) => en
      ? '$count left after this order'
      : 'จะเหลือหลังสั่งครั้งนี้ $count';
  static String get catalogToppings => en ? 'Toppings' : 'ท็อปปิ้ง';
  static String get catalogAddToCart => en ? 'Add to cart' : 'เพิ่มลงตะกร้า';
  static String get catalogOther => en ? 'Other' : 'อื่นๆ';

  static String formatDistanceKm(double? distanceKm) {
    if (distanceKm == null) {
      return '';
    }
    if (distanceKm < 1) {
      final meters = (distanceKm * 1000).round();
      return en ? '$meters m' : '$meters ม.';
    }
    final formatted =
        distanceKm.toStringAsFixed(distanceKm >= 10 ? 0 : 1);
    return en ? '$formatted km' : '$formatted กม.';
  }

  static String? catalogDeliveryDistanceLabel({
    required double? shopDistanceKm,
    required int totalMinutes,
  }) {
    final distanceText = formatDistanceKm(shopDistanceKm);
    if (distanceText.isEmpty) {
      return null;
    }
    return en
        ? '$distanceText away · delivery ~$totalMinutes min'
        : 'ห่าง $distanceText · ส่งถึง ~$totalMinutes นาที';
  }

  static String catalogTaxonomyLabel(String thaiLabel) {
    if (!en) {
      return thaiLabel;
    }
    return _catalogTaxonomyEn[thaiLabel] ?? thaiLabel;
  }

  static const Map<String, String> _catalogTaxonomyEn = <String, String>{
    'ยาและเวชภัณฑ์': 'Medicine & health products',
    'ยาแก้ปวด / ลดไข้': 'Pain relief / fever',
    'ยาแก้แพ้ / หวัด / ไอ': 'Allergy / cold / cough',
    'ยาทางเดินอาหาร': 'Digestive medicine',
    'ยาภายนอก': 'Topical medicine',
    'เวชภัณฑ์': 'Medical supplies',
    'อุปกรณ์การแพทย์': 'Medical devices',
    'วิตามิน / อาหารเสริม': 'Vitamins / supplements',
    'แม่และเด็ก': 'Mother & baby',
    'สุขภาพช่องปาก': 'Oral care',
    'ดูแลผิว / ของใช้ส่วนตัว': 'Skincare / personal care',
    'ผักสด': 'Fresh vegetables',
    'ผักใบ': 'Leafy greens',
    'ผักสวนครัว': 'Garden vegetables',
    'ผลไม้': 'Fruit',
    'ผลไม้สด': 'Fresh fruit',
    'มะม่วง': 'Mango',
    'กล้วย': 'Banana',
    'ส้ม': 'Orange',
    'ทุเรียน': 'Durian',
    'แก้วมังกร': 'Dragon fruit',
    'เนื้อสัตว์': 'Meat',
    'หมูสด': 'Fresh pork',
    'ไก่สด': 'Fresh chicken',
    'เนื้อสด': 'Fresh beef',
    'อาหารทะเลสด': 'Fresh seafood',
    'ปลาสด': 'Fresh fish',
    'กุ้งสด': 'Fresh shrimp',
    'ปูสด': 'Fresh crab',
    'หอยสด': 'Fresh shellfish',
    'ปลาหมึกสด': 'Fresh squid',
    'อาหารทะเลแปรรูป': 'Processed seafood',
    'ปลาหมึกแห้ง': 'Dried squid',
    'ปลาแห้ง / ปลาแดดเดียว': 'Dried / sun-dried fish',
    'ไข่ / เต้าหู้': 'Eggs / tofu',
    'ไข่': 'Eggs',
    'เต้าหู้': 'Tofu',
    'อาหารพร้อมทาน': 'Ready-to-eat food',
    'ของแห้ง / วัตถุดิบ': 'Dry goods / ingredients',
    'ข้าวสาร': 'Rice',
    'เส้น / บะหมี่': 'Noodles',
    'เครื่องปรุง / ซอส': 'Seasonings / sauces',
    'น้ำปลา': 'Fish sauce',
    'ซอส / ซีอิ๊ว': 'Sauces / soy sauce',
    'ขนม / เบเกอรี่': 'Snacks / bakery',
    'ขนม': 'Snacks',
    'เบเกอรี่': 'Bakery',
    'เครื่องดื่ม': 'Beverages',
    'น้ำดื่ม': 'Drinking water',
    'ชา': 'Tea',
    'กาแฟ': 'Coffee',
    'เสื้อผ้า': 'Clothing',
    'เสื้อ': 'Shirts',
    'กางเกง': 'Pants',
    'กระโปรง': 'Skirts',
    'ชุดนักเรียน / เครื่องแบบ': 'School uniforms',
    'ชุดนักเรียน': 'School uniform',
    'รองเท้า / กระเป๋า': 'Shoes / bags',
    'รองเท้านักเรียน': 'School shoes',
    'รองเท้า': 'Shoes',
    'กระเป๋า': 'Bags',
    'ของใช้ในบ้าน': 'Household items',
    'ซักผ้า': 'Laundry',
    'ล้างจาน': 'Dishwashing',
    'ของใช้ส่วนตัว': 'Personal care',
    'เครื่องเขียน / อุปกรณ์เรียน': 'Stationery / school supplies',
    'สมุด / กระดาษ': 'Notebooks / paper',
    'ปากกา / ดินสอ': 'Pens / pencils',
    'ของสด': 'Fresh goods',
    'อื่นๆ': 'Other',
  };

  // ---------------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------------

  static String get favoritesTitle => en ? 'Favorites' : 'รายการโปรด';
  static String get favoritesEmpty => en
      ? 'No favorites yet\nTap the heart on a product or shop to save'
      : 'ยังไม่มีรายการโปรด\nกดไอคอนหัวใจที่สินค้าหรือร้านค้าเพื่อบันทึก';
  static String get favoriteProductKind => productFallback;
  static String get favoriteShopKind => shopFallback;
  static String get removeFromFavorites =>
      en ? 'Remove from favorites' : 'ลบออกจากรายการโปรด';

  // ---------------------------------------------------------------------------
  // Cart
  // ---------------------------------------------------------------------------

  static String get cartTitle => en ? 'Cart' : 'ตะกร้า';
  static String get myCartTitle => en ? 'My cart' : 'ตะกร้าของฉัน';
  static String get cartEmpty => en ? 'Your cart is empty' : 'ยังไม่มีสินค้าในตะกร้า';
  static String get shareProduct => en ? 'Share product' : 'แชร์สินค้า';
  static String get sharedProductUnavailable => en
      ? 'This shared product is no longer available.'
      : 'ไม่พบสินค้าที่แชร์มา หรือสินค้าถูกปิดการขายแล้ว';
  static String get myCoupons => en ? 'My coupons' : 'คูปองของฉัน';
  static String get subtotalLabel => en ? 'Subtotal' : 'รวมค่าสินค้า';
  static String get shippingFeeLabel => en ? 'Delivery fee' : 'ค่าส่ง';
  static String get marketCollectionFeeLabel =>
      en ? 'Multi-shop collection fee (market)' : 'ค่ารวบรวมสินค้าหลายร้าน (ตลาด)';
  static String get marketServiceFeeLabel =>
      en ? 'Platform fee' : 'ค่าธรรมเนียมแพลตฟอร์ม';
  static String get grandTotalLabel => en ? 'Total due' : 'ยอดชำระทั้งหมด';
  static String get removeItem => en ? 'Remove item' : 'ลบสินค้า';
  static String get choosePaymentMethod =>
      en ? 'Choose your payment method' : 'เลือกวิธีชำระเงินที่ต้องการ';
  static String get scanPromptPay => en ? 'Scan PromptPay' : 'สแกนจ่ายพร้อมเพย์';
  static String get scanPromptPayHint => en
      ? 'Scan the QR code, attach a slip, then confirm before creating the order'
      : 'สแกน QR ชำระเงิน แล้วแนบสลิปเพื่อยืนยันก่อนสร้างออเดอร์';
  static String get confirmCodOrderTitle => en
      ? 'Confirm cash-on-delivery order'
      : 'ยืนยันคำสั่งซื้อแบบจ่ายปลายทาง';
  static String get orderItems => en ? 'Order items' : 'รายการสินค้า';
  static String itemCount(int count) => en ? '$count items' : '$count ชิ้น';
  static String quantityPieces(int qty) => en ? '$qty items' : '$qty ชิ้น';
  static String distanceKmFormatted(double km) =>
      en ? '${km.toStringAsFixed(1)} km' : '${km.toStringAsFixed(1)} กม.';
  static String toppingsLine(String toppings) =>
      en ? 'Toppings: $toppings' : 'ท็อปปิ้ง: $toppings';
  static String optionsLine(String options) =>
      en ? 'Options: $options' : 'ตัวเลือก: $options';
  static String quantityLine(int qty, num unitPrice, num total) => en
      ? 'Qty $qty x ฿${unitPrice.toStringAsFixed(0)} = ฿${total.toStringAsFixed(0)}'
      : 'จำนวน $qty x ฿${unitPrice.toStringAsFixed(0)} = ฿${total.toStringAsFixed(0)}';
  static String quantityLineShort(int qty, num unitPrice) => en
      ? 'Qty $qty x ฿${unitPrice.toStringAsFixed(0)}'
      : 'จำนวน $qty x ฿${unitPrice.toStringAsFixed(0)}';
  static String priceLabel(num price) => en
      ? 'Price ฿${price.toStringAsFixed(0)}'
      : 'ราคา ฿${price.toStringAsFixed(0)}';
  static String overStockBy(int shortfall) => en
      ? 'Over stock by $shortfall'
      : 'จำนวนเกินสต๊อก $shortfall';
  static String totalOverStock(int total) => en
      ? 'Total over stock: $total'
      : 'จำนวนเกินสต๊อกรวม: $total';
  static String productSubtotal(num amount) => en
      ? 'Subtotal: ฿${amount.toStringAsFixed(0)}'
      : 'ค่าสินค้า: ฿${amount.toStringAsFixed(0)}';
  static String shippingFeeAmount(num amount) => en
      ? 'Delivery: ฿${amount.toStringAsFixed(0)}'
      : 'ค่าส่ง: ฿${amount.toStringAsFixed(0)}';
  static String totalDiscount(num amount) => en
      ? 'Total discount: -฿${amount.toStringAsFixed(0)}'
      : 'ส่วนลดรวม: -฿${amount.toStringAsFixed(0)}';
  static String deliverTo(String label) => en
      ? 'Deliver to: $label'
      : 'จัดส่งที่: $label';
  static String coordinatesLabel(double lat, double lng) => en
      ? 'Coordinates ${lat.toStringAsFixed(6)} • ${lng.toStringAsFixed(6)}'
      : 'พิกัด ${lat.toStringAsFixed(6)} • ${lng.toStringAsFixed(6)}';
  static String get confirmOrder => en ? 'Confirm order' : 'ยืนยันสั่งซื้อ';
  static String createOrderFailed(Object error) => en
      ? 'Could not create order: $error'
      : 'ไม่สามารถสร้างออเดอร์ได้: $error';
  static String get createOrderFailedGeneric =>
      en ? 'Could not create order' : 'ไม่สามารถสร้างออเดอร์ได้';
  static String get promptPayNotReady => en
      ? 'PromptPay scan payment is not ready'
      : 'ระบบสแกนจ่ายพร้อมเพย์ยังไม่พร้อม';
  static String get qrCaptureFailed => en
      ? 'Could not capture QR code. Please try again.'
      : 'ยังจับภาพคิวอาร์โค้ดไม่ได้ ลองใหม่อีกครั้ง';
  static String get qrFileCreateFailed => en
      ? 'Could not create QR code file'
      : 'สร้างไฟล์คิวอาร์โค้ดไม่สำเร็จ';
  static String get qrDownloadSuccess => en
      ? 'QR code downloaded'
      : 'ดาวน์โหลดคิวอาร์โค้ดแล้ว';
  static String get qrDownloadFailed => en
      ? 'QR download failed. Please try again.'
      : 'ดาวน์โหลดคิวอาร์โค้ดไม่สำเร็จ ลองใหม่อีกครั้ง';
  static String get photoPermissionDenied => en
      ? 'Photo save permission denied'
      : 'ไม่ได้รับสิทธิ์บันทึกรูปลงเครื่อง';
  static String get qrSaveSuccess => en
      ? 'QR code saved to device'
      : 'บันทึกคิวอาร์โค้ดลงเครื่องแล้ว';
  static String get qrSaveFailed => en
      ? 'Could not save QR code. Please try again.'
      : 'บันทึกคิวอาร์โค้ดไม่สำเร็จ ลองใหม่อีกครั้ง';
  static String get slipOkVerified => en ? 'Slip OK verified' : 'Slip OK ตรวจสอบผ่าน';
  static String get slipOkRejected => en ? 'Slip OK rejected' : 'Slip OK ตรวจสอบไม่ผ่าน';
  static String get slipOkError =>
      en ? 'Slip OK returned an error' : 'Slip OK ส่งกลับข้อผิดพลาด';
  static String get slipCheckResult =>
      en ? 'Slip verification result' : 'ผลการตรวจสลิป';
  static String get slipSystemNotReady => en
      ? 'Slip submission is not ready'
      : 'ระบบส่งสลิปยังไม่พร้อมใช้งาน';
  static String get selectSlipFirst => en
      ? 'Please select a slip image first'
      : 'กรุณาเลือกรูปสลิปก่อนส่งตรวจ';
  static String slipSubmitFailed(Object error) => en
      ? 'Slip submission failed: $error'
      : 'ส่งสลิปไม่สำเร็จ: $error';
  static String amountDueBaht(double amount) => en
      ? 'Amount due ฿${amount.toStringAsFixed(2)}'
      : 'ยอดที่ต้องชำระ ฿${amount.toStringAsFixed(2)}';
  static String get savingQrToDevice => en
      ? 'Saving QR code to device...'
      : 'กำลังบันทึก...';
  static String get submitSlipForReview => en
      ? 'Submit slip for verification'
      : 'ส่งสลิปเพื่อตรวจสอบ';
  static String get promptPayConfigMissing => en
      ? 'No PromptPay or Merchant QR configured for a real QR code'
      : 'ยังไม่มีข้อมูล PromptPay หรือ Merchant QR สำหรับสร้างคิวอาร์โค้ดจริง';
  static String get promptPayConfigHint => en
      ? 'Set values in Firestore at payment_config/collection and the QR will auto-bind the amount'
      : 'ให้ใส่ค่าใน Firestore ที่ payment_config/collection แล้วคิวอาร์โค้ดจะผูกยอดให้อัตโนมัติ';
  static String get verifyingAmountFromServer => en
      ? 'Verifying amount from server, please wait'
      : 'กำลังยืนยันยอดจาก server กรุณารอสักครู่';
  static String get estimatedAmountOffline => en
      ? 'This amount is estimated locally and cannot be paid yet. Connect to the internet and recalculate.'
      : 'ยอดนี้เป็นประมาณการจากเครื่อง ยังชำระไม่ได้ กรุณาเชื่อมต่ออินเทอร์เน็ตแล้วคำนวณใหม่';
  static String get qrByAmount => en ? 'Amount-based QR' : 'คิวอาร์โค้ดตามยอด';
  static String get qrCreateFailed => en
      ? 'Could not create QR code yet'
      : 'ยังไม่สามารถสร้างคิวอาร์โค้ดได้';
  static String paymentTotalBaht(String amount) => en
      ? 'Payment total ฿$amount'
      : 'ยอดชำระ ฿$amount';
  static String get attachSlip => en ? 'Attach slip' : 'แนบสลิป';
  static String get attachSlipHint => en
      ? 'Choose a slip image from your device to submit for payment verification'
      : 'เลือกรูปสลิปจากเครื่องเพื่อเตรียมส่งตรวจการชำระเงิน';
  static String get selectSlip => en ? 'Select slip' : 'เลือกรูปสลิป';
  static String get changeSlip => en ? 'Change slip' : 'เปลี่ยนรูปสลิป';
  static String get removeSlip => en ? 'Remove slip' : 'ลบสลิป';
  static String get changeDeliveryLocation =>
      en ? 'Change delivery location' : 'เปลี่ยนพิกัดส่ง';
  static String get pasteCoordinates => en ? 'Paste coordinates' : 'วางพิกัด';
  static String get pasteCoordinatesHint => en
      ? 'Paste latitude and longitude values'
      : 'วางค่า latitude, longitude ที่คัดลอกมา';
  static String get pasteShareLink => shareAction;
  static String get pasteShareLinkHint => en
      ? 'Paste a coordinate link shared from maps'
      : 'วางลิงก์พิกัดที่แชร์มาจากแผนที่';
  static String get changeViaGoogleMaps => en
      ? 'Change via Google Maps'
      : 'เปลี่ยนด้วยกูเกิลแมพ';
  static String get changeViaGoogleMapsHint => en
      ? 'Open maps to pick a new location'
      : 'เปิดแผนที่เพื่อเลือกตำแหน่งใหม่';
  static String shippingSummary(String distanceKm, String minutes) => en
      ? 'Delivery includes $distanceKm km • ~$minutes min'
      : 'ค่าส่งรวม $distanceKm กม. • เวลา $minutes นาที';
  static String get calculatingDistanceFromGoogle => en
      ? 'Calculating distance via Google Routes API'
      : 'กำลังคำนวณระยะทางจาก Google Routes API';
  static String get serverPricingFailed => en
      ? 'Could not calculate price from server. Please try again.'
      : 'ไม่สามารถคำนวณราคาจากเซิร์ฟเวอร์ได้ กรุณาลองใหม่';
  static String get cartOrLocationIncomplete => en
      ? 'Cart or delivery coordinates incomplete'
      : 'ข้อมูลตะกร้าหรือพิกัดจัดส่งไม่ครบ';
  static String get appCheckFailed => en
      ? 'Security verification failed. Update the app or try again.'
      : 'ระบบยืนยันความปลอดภัยไม่ผ่าน กรุณาอัปเดตแอปหรือลองใหม่';
  static String get webAppCheckNotConfigured => en
      ? 'Web App Check is not configured — use the mobile app or contact admin'
      : 'เว็บยังไม่ได้ตั้งค่า App Check — กรุณาใช้แอปมือถือหรือติดต่อผู้ดูแล';
  static String get appCheckNotReady => en
      ? 'Security verification is not ready. Try again or use the mobile app.'
      : 'ระบบยืนยันความปลอดภัยไม่พร้อม กรุณาลองใหม่หรือใช้แอปมือถือ';
  static String get serverConnectionFailed => en
      ? 'Could not connect to server. Please try again.'
      : 'เชื่อมต่อเซิร์ฟเวอร์ไม่สำเร็จ กรุณาลองใหม่';
  static String get signInRequiredBeforePricing => signInRequiredFirst;

  // ---------------------------------------------------------------------------
  // Nationwide cart
  // ---------------------------------------------------------------------------

  static String get nationwideCartTitle =>
      en ? 'Nationwide shipping cart' : 'ตะกร้าส่งทั่วประเทศ';
  static String get nationwideCartEmpty => en
      ? 'No nationwide shipping items yet'
      : 'ยังไม่มีสินค้าส่งทั่วประเทศ';
  static String get deliveryAddress => en ? 'Delivery address' : 'ที่อยู่จัดส่ง';
  static String get noSavedAddresses => en
      ? 'No saved addresses yet'
      : 'ยังไม่มีที่อยู่ที่บันทึกไว้';
  static String savedAddressPrimary(String name) => en
      ? '$name • Primary'
      : '$name • หลัก';
  static String get editThisAddress => en ? 'Edit this address' : 'แก้ไขที่อยู่นี้';
  static String get deleteThisAddress => en ? 'Delete this address' : 'ลบที่อยู่นี้';
  static String get addNewAddress => en ? 'Add new address' : 'เพิ่มที่อยู่ใหม่';
  static String get saveCurrentFormAsPrimary => en
      ? 'Save current form as primary address'
      : 'บันทึกฟอร์มปัจจุบันเป็นที่อยู่หลัก';
  static String get pinDeliveryLocation =>
      en ? 'Pin delivery location' : 'ปักพิกัดจัดส่ง';
  static String get useTheseCoordinates => en ? 'Use these coordinates' : 'ใช้พิกัดนี้';
  static String get deliveryCoordinates => en ? 'Delivery coordinates' : 'พิกัดจัดส่ง';
  static String get addressSavedForLater => en
      ? 'Address saved for next time'
      : 'บันทึกที่อยู่นี้ไว้ใช้ครั้งต่อไปแล้ว';
  static String get deliveryAddressConfirmed => en
      ? 'Delivery address confirmed'
      : 'ยืนยันที่อยู่จัดส่งแล้ว';
  static String get addressFetchedFromCoordinates => en
      ? 'Address fetched from coordinates — please review'
      : 'ดึงที่อยู่จากพิกัดแล้ว กรุณาตรวจสอบอีกครั้ง';
  static String addressFetchFailed(Object error) => en
      ? 'Could not fetch address: $error'
      : 'ดึงที่อยู่ไม่สำเร็จ: $error';
  static String get scanPay => en ? 'Scan to pay' : 'สแกนจ่าย';
  static String get nationwideScanPayHint => en
      ? 'Order is created and the shop is notified only after slip verification passes'
      : 'ระบบจะสร้างออเดอร์และแจ้งร้านค้าหลังตรวจสลิปผ่านเท่านั้น';
  static String get nationwideCartEmptyError => en
      ? 'Nationwide shipping cart is empty'
      : 'ไม่มีสินค้าในตะกร้าส่งทั่วประเทศ';
  static String get confirmAddressBeforePay => en
      ? 'Confirm delivery address before paying'
      : 'กรุณายืนยันที่อยู่จัดส่งก่อนสแกนจ่าย';
  static String get signInRequiredBeforeOrder => signInRequiredFirst;
  static String get emptySlipFile => en ? 'Slip file is empty' : 'ไฟล์สลิปว่างเปล่า';
  static String get slipNotVerified => en
      ? 'Slip has not passed verification'
      : 'สลิปยังไม่ผ่านการตรวจสอบ';
  static String nationwideOrderCreated(int count) => en
      ? 'Nationwide order created ($count items)'
      : 'สร้างออเดอร์ส่งทั่วประเทศแล้ว $count รายการ';
  static String nationwideSlipVerifiedAndCreated(int count) => en
      ? 'Slip verified and nationwide order created'
      : 'ตรวจสลิปผ่านและสร้างออเดอร์ส่งทั่วประเทศแล้ว';
  static String nationwideOrderCreatedWithMessage(String message, int count) => en
      ? '$message\nNationwide order created ($count items)'
      : '$message\nสร้างออเดอร์ส่งทั่วประเทศแล้ว $count รายการ';
  static String get createNationwideOrderFailed => en
      ? 'Could not create nationwide shipping order'
      : 'ไม่สามารถสร้างออเดอร์ส่งทั่วประเทศได้';
  static String get fetchingAddressFromGoogle => en
      ? 'Fetching address from Google...'
      : 'กำลังดึงที่อยู่จาก Google...';
  static String get pinAndAutoFillAddress => en
      ? 'Pin location and auto-fill address'
      : 'ปักพิกัดและกรอกที่อยู่อัตโนมัติ';
  static String deliveryCoordinatesFormatted(double lat, double lng) => en
      ? 'Delivery coordinates: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
      : 'พิกัดจัดส่ง: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  static String get recipientName => en ? 'Recipient name' : 'ชื่อผู้รับ';
  static String get phoneNumber => en ? 'Phone number' : 'เบอร์โทร';
  static String get streetAddress =>
      en ? 'House no. / street / village' : 'บ้านเลขที่ / ถนน / หมู่บ้าน';
  static String get subDistrict => en ? 'Sub-district' : 'ตำบล/แขวง';
  static String get district => en ? 'District' : 'อำเภอ/เขต';
  static String get province => en ? 'Province' : 'จังหวัด';
  static String get postalCode => en ? 'Postal code' : 'รหัสไปรษณีย์';
  static String get confirmDeliveryAddress =>
      en ? 'Confirm delivery address' : 'ยืนยันที่อยู่จัดส่ง';
  static String get lineSubtotal => en ? 'Line subtotal' : 'รวมรายการนี้';
  static String get estimatedShippingFee =>
      en ? 'Estimated shipping' : 'ค่าส่งประมาณการ';
  static String get mockShippingNote => en
      ? 'Shipping fee is mock/manual while ShipPop integration is pending'
      : 'ค่าส่งนี้เป็น mock/manual ระหว่างรอเชื่อมต่อ ShipPop';
  static String parcelDimensions(String dims) => en ? '$dims cm' : '$dims ซม.';
  static String parcelWeightKg(double kg) => en
      ? '${kg.toStringAsFixed(1)} kg'
      : '${kg.toStringAsFixed(1)} กก.';
  static String pricePerPiece(num price) => en
      ? '฿${price.toStringAsFixed(0)} / item'
      : '฿${price.toStringAsFixed(0)} / ชิ้น';
  static String fieldRequired(String label) => en
      ? 'Please enter $label'
      : 'กรุณากรอก$label';
  static String allItemsCount(int count) => en
      ? 'All ($count items)'
      : 'ทั้งหมด ($count รายการ)';
  static String categoryItemsCount(String label, int count) => en
      ? '$label ($count items)'
      : '$label ($count รายการ)';

  // ---------------------------------------------------------------------------
  // Nationwide category picker
  // ---------------------------------------------------------------------------

  static String get noNationwideProductsNow => en
      ? 'No nationwide shipping products right now'
      : 'ยังไม่มีสินค้าส่งทั่วประเทศในตอนนี้';
  static String get noNationwideProductsInCategory => en
      ? 'No nationwide products in this category'
      : 'ยังไม่มีสินค้าส่งทั่วประเทศในประเภทนี้';
  static String get productCategory => en ? 'Product category' : 'ประเภทสินค้า';
  static String loadProductsFailed(Object error) => en
      ? 'Failed to load products: $error'
      : 'โหลดสินค้าไม่สำเร็จ: $error';

  // ---------------------------------------------------------------------------
  // Map picker
  // ---------------------------------------------------------------------------

  static String get selectedLocation => en ? 'Selected location' : 'ตำแหน่งที่เลือก';
  static String get currentLocation => en ? 'Current location' : 'ตำแหน่งปัจจุบัน';
  static String locationFetchFailed(Object error) => en
      ? 'Could not get location: $error'
      : 'ไม่สามารถดึงตำแหน่งได้: $error';
  static String get enableLocationServices => en
      ? 'Please enable device location services'
      : 'กรุณาเปิดบริการระบุตำแหน่งของอุปกรณ์';
  static String get grantLocationPermission => en
      ? 'Please allow location access'
      : 'กรุณาอนุญาตให้แอพเข้าถึงตำแหน่ง';
  static String get openLocationSettings => en
      ? 'Please enable location permission in system settings'
      : 'กรุณาเปิดสิทธิ์ตำแหน่งจากการตั้งค่าเครื่อง';
  static String get locationNotFound => en ? 'Location not found' : 'ไม่พบตำแหน่งที่ค้นหา';
  static String placeSearchFailed(Object error) => en
      ? 'Place search failed: $error'
      : 'ค้นหาสถานที่ไม่สำเร็จ: $error';
  static String get searchPlaceOrAddress =>
      en ? 'Search place or address' : 'ค้นหาสถานที่หรือที่อยู่';

  // ---------------------------------------------------------------------------
  // Shop map
  // ---------------------------------------------------------------------------

  static String get shopMapTitle => en ? 'Shop map' : 'แผนที่ร้าน';
  static String get noShopsWithCoordinates => en
      ? 'No shops with coordinates to show on the map'
      : 'ยังไม่พบร้านค้าที่มีพิกัดสำหรับแสดงบนแผนที่';
  static String get shopsInYourArea => en ? 'Shops in your area' : 'ร้านในพื้นที่ของคุณ';
  static String shopsNearMarket(int count, String center) => en
      ? '$count shops • Center $center'
      : '$count ร้าน • ศูนย์กลาง $center';
  static String get marketRadiusCircle => en
      ? '10 km radius circle from Non Sung market'
      : 'วงกลมรัศมี 10 กม. จากตลาดโนนสูง';
  static String get shopImageModeHint => en
      ? 'Shop image mode: visible radius up to 1 km'
      : 'โหมดรูปร้าน: รัศมีที่แสดงไม่เกิน 1 กม.';
  static String get zoomForShopImages => en
      ? 'Zoom in to see shop images within 1 km'
      : 'ซูมเข้าอีกเพื่อดูรูปร้านในรัศมี 1 กม.';
  static String get shopListCollapsedHint => en
      ? 'Shop list collapsed — tap to expand'
      : 'ย่อแถบร้านอยู่ แตะเพื่อขยาย';
  static String nearbyShopsCount(int count) => en
      ? 'Nearby shops ($count shops)'
      : 'ร้านใกล้คุณ $count ร้าน';
  static String get marketCenterLabel => en
      ? 'Non Sung Market, Non Sung, Mueang Udon Thani, Udon Thani'
      : 'ตลาดโนนสูง ตำบลโนนสูง อำเภอเมืองอุดรธานี จังหวัดอุดรธานี';
  static String mapCenterLabel(String center) => en
      ? 'Center $center'
      : 'ศูนย์กลาง $center';
  static String get youAreHere => en ? 'You are here' : 'คุณอยู่ที่นี่';
  static String get enterShop => en ? 'Enter shop' : 'เข้าร้าน';
  static String get distanceUnknown => en ? 'Distance unknown' : 'ไม่พบระยะทาง';
  static String distanceFromYouKm(double km) => en
      ? '${km.toStringAsFixed(1)} km from you'
      : 'ห่างจากคุณ ${km.toStringAsFixed(1)} กม.';
  static String shopCount(int count) => en ? '$count shops' : '$count ร้าน';

  // ---------------------------------------------------------------------------
  // Travel payment
  // ---------------------------------------------------------------------------

  static String get travelPaymentTitle => en ? 'Pay for ride' : 'ชำระค่าการเดินทาง';
  static String get travelPaymentSubtitle => en
      ? 'Choose payment before creating the order and matching a rider'
      : 'เลือกวิธีชำระเงินก่อนสร้างออเดอร์และแมตช์ไรเดอร์';
  static String travelRouteSubtitle(String from, String to) => en
      ? 'From $from to $to'
      : 'จาก $from ไป $to';
  static String get createTravelOrderFailed =>
      en ? 'Could not create travel order' : 'ไม่สามารถสร้างออเดอร์เดินทางได้';
  static String get omisePaymentNotReady => en
      ? 'Omise payment is not ready'
      : 'ระบบชำระเงิน Omise ยังไม่พร้อม';
  static String get pickupPoint => en ? 'Pickup' : 'จุดรับ';
  static String get destination => en ? 'Destination' : 'ปลายทาง';
  static String get distance => en ? 'Distance' : 'ระยะทาง';
  static String get vehicleType => en ? 'Vehicle type' : 'ประเภทรถ';
  static String get scheduleTime => en ? 'Time' : 'เวลา';
  static String distanceKmOrMeters(double value) {
    if (value < 1) {
      final meters = (value * 1000).round();
      return en ? '$meters m' : '$meters เมตร';
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${en ? 'km' : 'กม.'}';
  }

  // ---------------------------------------------------------------------------
  // Travel tracking
  // ---------------------------------------------------------------------------

  static String get passengerPickup => en ? 'Passenger pickup' : 'จุดรับผู้โดยสาร';
  static String get updatingRoute => en ? 'Updating route...' : 'กำลังอัปเดตเส้นทาง...';
  static String get cannotMakeCall => en ? 'Cannot make a call' : 'ไม่สามารถโทรออกได้';
  static String get cannotCallRider => en ? 'Cannot call rider' : 'ไม่สามารถโทรหาไรเดอร์ได้';
  static String get chatDriver => en ? 'Chat driver' : 'แชทหาคนขับ';
  static String get findingRider => en ? 'Finding a rider' : 'กำลังหาไรเดอร์';
  static String get waitingRiderAccept => en ? 'Waiting for rider to accept' : 'รอไรเดอร์รับงาน';
  static String get driverComing => en ? 'Driver is on the way' : 'คนขับกำลังมา';
  static String get travelingToDestination =>
      en ? 'Traveling to destination' : 'กำลังเดินทางไปปลายทาง';
  static String get arrivedAtDestination =>
      en ? 'Arrived at destination' : 'ถึงจุดหมายแล้ว';
  static String scheduledMatchHint(String schedule) => en
      ? 'Scheduled for $schedule — rider will be matched before departure'
      : 'กำหนดเดินทาง $schedule — ระบบจะจับคู่ไรเดอร์ก่อนเวลาเดินทาง';
  static String get scheduledMatchGeneric => en
      ? 'Rider will be matched before your scheduled departure'
      : 'ระบบจะจับคู่ไรเดอร์ก่อนเวลาเดินทางที่คุณกำหนด';
  static String get matchingNearestRider => en
      ? 'Matching the nearest rider'
      : 'ระบบกำลังจับคู่ไรเดอร์ที่ใกล้ที่สุด';
  static String get riderMatchedWaitingConfirm => en
      ? 'Rider matched — waiting for confirmation'
      : 'ระบบจับคู่ไรเดอร์แล้ว รอไรเดอร์ยืนยันรับงาน';
  static String get boardImmediatelyHint => en
      ? 'Board immediately — driver cannot wait'
      : 'ขึ้นรถทันที คนขับไม่สามารถจอดรอได้';
  static String get trackPickupToDestination => en
      ? 'Track route from pickup to destination (~1 min updates)'
      : 'ติดตามเส้นทางจากจุดรับไปปลายทาง (อัปเดตทุก ~1 นาที)';
  static String get safeTripWish => en ? 'Have a safe trip' : 'ขอให้เดินทางปลอดภัย';
  static String etaMinutesCount(int minutes) =>
      en ? '$minutes min' : '$minutes นาที';

  // ---------------------------------------------------------------------------
  // Travel planner
  // ---------------------------------------------------------------------------

  static String get departNow => en ? 'Depart now' : 'ให้รถออกตอนนี้';
  static String thaiDateTime(int day, int month, int year, String time) => en
      ? '$day/$month/$year $time'
      : '$day/$month/$year $time น.';
  static String get selectedPickup => en ? 'Selected pickup' : 'จุดรับที่เลือก';
  static String get selectedDestination =>
      en ? 'Selected destination' : 'จุดหมายที่เลือก';
  static String get geocodingFallback => en
      ? 'Search via Geocoding (fallback)'
      : 'ค้นหาด้วย Geocoding (fallback)';
  static String get placeDetailsLoadFailed => en
      ? 'Could not load place details'
      : 'ไม่สามารถโหลดรายละเอียดสถานที่ได้';
  static String get searchLocationNotFound =>
      en ? 'Search location not found' : 'ไม่พบตำแหน่งที่ค้นหา';
  static String get selectTimeAndVehicleFirst => en
      ? 'Please select time and vehicle type first'
      : 'กรุณาเลือกเวลาและประเภทรถก่อน';
  static String get tapMapForPickup => en
      ? 'Tap the map or drag the green pin to set pickup'
      : 'เลือกจุดรับโดยแตะแผนที่หรือลากหมุดสีเขียว';
  static String get enableLocationForTravel =>
      en ? 'Enable location to start your ride' : 'เปิดตำแหน่งเพื่อเริ่มเดินทาง';
  static String get webLocationPermissionHint => en
      ? 'Web needs browser permission before using your current location as pickup'
      : 'เว็บต้องได้รับอนุญาตจากเบราว์เซอร์ก่อน ระบบจึงจะใช้ตำแหน่งปัจจุบันเป็นจุดรับ';
  static String get locationRequiredForPickup => en
      ? 'Current location is required as the passenger pickup point'
      : 'ระบบต้องใช้ตำแหน่งปัจจุบันเป็นจุดรับผู้โดยสาร';
  static String get webLocationBlockHint => en
      ? 'If you tapped Block: click the lock icon next to vantalad.web.app → Location → Allow, then refresh'
      : 'ถ้าเคยกด "Block": คลิกไอคอน 🔒 หรือ ⓘ ข้าง vantalad.web.app → Location → Allow แล้วรีเฟรชหน้า';
  static String get enableLocation => en ? 'Enable location' : 'เปิดตำแหน่ง';
  static String get pickPickupOnMapInstead => en
      ? 'Pick pickup on map instead'
      : 'เลือกจุดรับบนแผนที่แทน';
  static String get yourLocation => en ? 'Your location' : 'ตำแหน่งของคุณ';
  static String get findingLocation => en ? 'Finding location...' : 'กำลังค้นหาตำแหน่ง...';
  static String get whereTo => en ? 'Where to?' : 'ไปไหน?';
  static String get pickDestinationHint => en
      ? 'Pick destination on the map or search above'
      : 'เลือกจุดหมายบนแผนที่หรือค้นหาด้านบน';
  static String get calculatingRoadRoute => en
      ? 'Calculating road route...'
      : 'กำลังคำนวณเส้นทางตามถนน...';
  static String startingFareApprox(int fare) => en
      ? 'From ~$fare THB'
      : 'เริ่มต้น ~$fare บาท';
  static String get roadRouteFailed => en
      ? 'Could not calculate road route'
      : 'ไม่สามารถคำนวณเส้นทางตามถนนได้';
  static String get selectVehicleType => en ? 'Select vehicle type' : 'เลือกประเภทรถ';
  static String get confirmTrip => en ? 'Confirm trip' : 'ยืนยันการเดินทาง';
  static String get pickPlace => en ? 'Pick a place' : 'เลือกสถานที่';
  static String get travelDate => en ? 'Travel date' : 'วันที่เดินทาง';
  static String get travelTime => en ? 'Travel time' : 'เวลาเดินทาง';
  static String get selectDate => en ? 'Select date' : 'เลือกวันที่';
  static String get selectTime => en ? 'Select time' : 'เลือกเวลา';
  static String get scheduleDateTimeRequired => en
      ? 'Please select travel date and time'
      : 'กรุณาเลือกวันที่และเวลาเดินทาง';
  static String scheduledTripSummary(String date, String time) => en
      ? 'Scheduled for $date at $time'
      : 'กำหนดเดินทางวันที่ $date เวลา $time';
  static String get confirmSelection => en ? 'Confirm selection' : 'ยืนยันตัวเลือกนี้';
  static String get selectDateTimeBeforeConfirm => en
      ? 'Select date and time before confirming'
      : 'เลือกวันและเวลาก่อนยืนยัน';
  static String confirmFareApprox(int fare) => en
      ? 'Confirm ~$fare THB'
      : 'ยืนยัน ~$fare บาท';
  static String onlineVehicleCount(int count) => en
      ? 'Online $count vehicles'
      : 'ออนไลน์ $count คัน';
  static String get offline => en ? 'Offline' : 'ออฟไลน์';
  static String fareApprox(int fare) => en ? '~$fare THB' : '~$fare บาท';
  static String distanceFindingVehicles(double km) => en
      ? '${km.toStringAsFixed(1)} km · Finding nearby vehicles...'
      : '${km.toStringAsFixed(1)} กม. · กำลังค้นหารถใกล้คุณ...';
  static String distanceOnlineVehicles(double km, int count) => en
      ? '${km.toStringAsFixed(1)} km · $count vehicles online'
      : '${km.toStringAsFixed(1)} กม. · พบรถออนไลน์ $count คัน';
  static String noVehicleOnlineSchedule(String vehicle) => en
      ? 'No $vehicle online — please schedule date and time'
      : 'ไม่มีรถ$vehicleออนไลน์ — กรุณากำหนดวันและเวลาเดินทาง';
  static String get setDateAndTime => en ? 'Set date & time' : 'กำหนดวันและเวลา';
  static String thaiTimeSuffix(String time) => en ? time : '$time น.';

  static List<String> get thaiMonthNames => en
      ? <String>[
          'January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December',
        ]
      : <String>[
          'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
          'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
        ];

  // ---------------------------------------------------------------------------
  // Order roadmap
  // ---------------------------------------------------------------------------

  static String get orderHistoryTitle => en ? 'Order history' : 'ประวัติออเดอร์';
  static String get deliveryRoadmapTitle =>
      en ? 'Delivery roadmap' : 'Roadmap การจัดส่ง';
  static String get noActiveOrders => en
      ? 'No orders in progress'
      : 'ไม่มีออเดอร์ที่กำลังดำเนินการ';
  static String get completedOrdersInHistory => en
      ? 'Delivered, cancelled, or refunded orders are in History'
      : 'ออเดอร์ที่ส่งสำเร็จ ยกเลิก หรือขอคืนเงินแล้วจะอยู่ในปุ่มประวัติ';
  static String get viewOrderHistory => en ? 'View order history' : 'ดูประวัติออเดอร์';
  static String get signInRequiredForOrders => en
      ? 'Please sign in to view order roadmap'
      : 'กรุณาเข้าสู่ระบบเพื่อดูโรดแมปออเดอร์';
  static String get signInRequiredForHistory => en
      ? 'Please sign in to view order history'
      : 'กรุณาเข้าสู่ระบบเพื่อดูประวัติออเดอร์';
  static String loadRoadmapFailed(Object error) => en
      ? 'Failed to load roadmap: $error'
      : 'โหลดโรดแมปไม่สำเร็จ: $error';
  static String loadHistoryFailed(Object error) => en
      ? 'Failed to load history: $error'
      : 'โหลดประวัติไม่สำเร็จ: $error';
  static String get noCompletedOrderHistory => en
      ? 'No completed order history yet'
      : 'ยังไม่มีประวัติออเดอร์ที่ส่งสำเร็จ';
  static String get historyProductsSection => en ? 'Products' : 'สินค้า';
  static String get historyTravelSection => en ? 'Travel' : 'การเดินทาง';
  static String loadOrderFailed(String orderId, Object error) => en
      ? 'Failed to load order $orderId: $error'
      : 'โหลดออเดอร์ $orderId ไม่สำเร็จ: $error';
  static String orderNotFound(String orderId) => en
      ? 'Order $orderId not found'
      : 'ไม่พบข้อมูลออเดอร์ $orderId';
  static String pickupPointLabel(String label) => en
      ? 'Pickup: ${label.isNotEmpty ? label : '-'}'
      : 'จุดรับ: ${label.isNotEmpty ? label : '-'}';
  static String shopLabel(String name) => en
      ? 'Shop: ${name.isNotEmpty ? name : '-'}'
      : 'ร้าน: ${name.isNotEmpty ? name : '-'}';
  static String dropoffLabel(String label) => en
      ? 'Drop-off: ${label.isNotEmpty ? label : '-'}'
      : 'จุดส่ง: ${label.isNotEmpty ? label : '-'}';
  static String get substituteNoCharge =>
      en ? 'Substitute — no charge' : 'ทดแทน — ไม่คิดเงิน';
  static String paymentTotalThb(double total) => en
      ? 'Total: THB ${total.toStringAsFixed(1)}'
      : 'ยอดชำระ: THB ${total.toStringAsFixed(1)}';
  static String vehicleTypeLabel(String label) => en
      ? 'Vehicle: $label'
      : 'ประเภทรถ: $label';
  static String travelScheduleLabel(String label) => en
      ? 'Schedule: $label'
      : 'เวลาเดินทาง: $label';
  static String get travelDetails => en ? 'Travel details' : 'รายละเอียดการเดินทาง';
  static String get orderProducts => en ? 'Order products' : 'สินค้าในออเดอร์';
  static String get riderProofPhoto => en ? 'Rider proof photo' : 'รูปยืนยันจากไรเดอร์';
  static String get proofPhotoLoadFailed => en
      ? 'Failed to load proof photo'
      : 'โหลดรูปยืนยันไม่สำเร็จ';
  static String get chatRider => en ? 'Chat rider' : 'แชทไรเดอร์';
  static String get callRider => en ? 'Call rider' : 'โทรไรเดอร์';
  static String get callRiderUnavailable => en
      ? 'Call rider unavailable'
      : 'โทรไรเดอร์ไม่ได้';
  static String get claimProduct => en ? 'Claim product' : 'ขอเคลมสินค้า';
  static String get contactAdminAboutOrder => en
      ? 'Contact admin about this order'
      : 'ติดต่อแอดมินเรื่องออเดอร์นี้';
  static String get riderAcceptedOrder => en ? 'Rider accepted' : 'ไรเดอร์รับออเดอร์';
  static String get riderAtPickup => en ? 'Rider at pickup' : 'ไรเดอร์ถึงจุดรับแล้ว';
  static String get shopAcceptedOrder => en ? 'Shop accepted order' : 'ร้านค้ารับออเดอร์';
  static String get waitingPassengerBoard => en
      ? 'Waiting for passenger to board'
      : 'กำลังรอผู้โดยสารขึ้นรถ';
  static String get riderScannedPickup => en
      ? 'Rider scanned pickup'
      : 'ไรเดอร์สแกนรับสินค้า';
  static String get travelingToDropoff => en
      ? 'Traveling to drop-off'
      : 'กำลังเดินทางไปจุดส่ง';
  static String get riderDelivering => en ? 'Rider delivering' : 'ไรเดอร์กำลังไปส่ง';
  static String get deliveredToCustomer => en ? 'Delivered to customer' : 'ส่งถึงลูกค้าแล้ว';
  static String confirmedByAt(String name, String at) => en
      ? 'Confirmed by $name at $at'
      : 'ยืนยันโดย $name เมื่อ $at';
  static String confirmedBy(String name) => en
      ? 'Confirmed by $name'
      : 'ยืนยันโดย $name';
  static String capturedAt(String at) => en ? 'Captured at $at' : 'ถ่ายเมื่อ $at';
  static String get cannotCallSelf => en
      ? 'Cannot call your own account'
      : 'ไม่สามารถโทรหาบัญชีตัวเองได้';
  static String startCallFailed(Object error) => en
      ? 'Failed to start call: $error'
      : 'เริ่มการโทรไม่สำเร็จ: $error';
  static String get riderInfoMissingForCall => en
      ? 'Rider info not found for calling'
      : 'ไม่พบข้อมูลไรเดอร์สำหรับโทรออก';
  static String get signInRequiredBeforeCallRider => signInRequiredFirst;
  static String quantityPiecesOrDash(int quantity) => en
      ? quantity > 0 ? '$quantity items' : '-'
      : quantity > 0 ? '$quantity ชิ้น' : '-';
  static String get reviewProductsShopRider => en
      ? 'Review product, shop, and rider'
      : 'รีวิวสินค้า ร้านค้า และไรเดอร์';
  static String get reviewProductsShop => en
      ? 'Review product and shop'
      : 'รีวิวสินค้าและร้านค้า';
  static String get reviewRider => en ? 'Review rider' : 'รีวิวไรเดอร์';
  static String get reviewHelpOthers => en
      ? 'Reviews from completed orders help other customers decide'
      : 'รีวิวจากออเดอร์ที่ส่งสำเร็จ ช่วยให้ลูกค้าคนอื่นตัดสินใจง่ายขึ้น';
  static String get reviewOrEdit => en ? 'Review / edit review' : 'รีวิว / แก้ไขรีวิว';
  static String quantityCount(int qty) => en ? 'Qty $qty' : 'จำนวน $qty';
  static String get reviewShop => en ? 'Review shop' : 'รีวิวร้านค้า';
  static String get rateAtLeastOne => en
      ? 'Please rate at least one item'
      : 'กรุณาให้คะแนนอย่างน้อย 1 รายการ';
  static String get reviewSaveFailed => en ? 'Failed to save review' : 'บันทึกรีวิวไม่สำเร็จ';
  static String reviewSaveFailedWithError(Object error) => en
      ? 'Failed to save review: $error'
      : 'บันทึกรีวิวไม่สำเร็จ: $error';
  static String reviewSavedPartial(int saved, int total) => en
      ? 'Saved $saved/$total reviews'
      : 'บันทึกรีวิวได้ $saved/$total รายการ';
  static String get reviewSaved => en ? 'Review saved' : 'บันทึกรีวิวเรียบร้อยแล้ว';
  static String reviewMaxImagesHint(int max) => en
      ? 'Rate and attach up to $max images per item. Default is 5 stars.'
      : 'ให้คะแนนและแนบรูปได้สูงสุด $max รูปต่อรายการ ค่าเริ่มต้นคือ 5 ดาว';
  static String get saveReview => en ? 'Save review' : 'บันทึกรีวิว';
  static String get commentOptional => optionalLabel;
  static String get optionalLabel => en ? 'Comment (optional)' : 'ความคิดเห็น (ไม่บังคับ)';
  static String get addPhoto => en ? 'Add photo' : 'เพิ่มรูป';
  static String maxPhotosPerReview(int max) => en
      ? 'Up to $max photos per review'
      : 'อัปโหลดได้สูงสุด $max รูปต่อรีวิว';
  static String waitExtraMinutes(int minutes) => en
      ? 'Wait extended $minutes minutes — shop will see this order again'
      : 'รอเพิ่ม $minutes นาที ร้านค้าจะเห็นออเดอร์นี้อีกครั้ง';
  static String saveWaitFailed(Object error) => en
      ? 'Failed to save wait: $error'
      : 'บันทึกการรอไม่สำเร็จ: $error';
  static String get orderCancelled => en ? 'Order cancelled' : 'ยกเลิกออเดอร์แล้ว';
  static String cancelOrderFailed(Object error) => en
      ? 'Failed to cancel order: $error'
      : 'ยกเลิกออเดอร์ไม่สำเร็จ: $error';
  static String get waitingShopExtra15 => en
      ? 'Waiting for shop 15 more minutes'
      : 'กำลังรอร้านค้าอีก 15 นาที';
  static String get shopRejectedOrder => en
      ? 'Shop rejected this order'
      : 'ร้านค้าปฏิเสธออเดอร์นี้';
  static String get shopNotAcceptedAfterRider => en
      ? 'Shop has not accepted after rider picked up'
      : 'ร้านค้ายังไม่รับออเดอร์หลังไรเดอร์รับงานแล้ว';
  static String get canCancelIfShopLate => en
      ? 'If the shop does not accept in time, you can cancel the order'
      : 'หากร้านค้ายังไม่รับงานภายในเวลาที่กำหนด คุณสามารถยกเลิกออเดอร์ได้';
  static String get canWaitOrCancelRefund => en
      ? 'You can wait 15 more minutes or cancel and request a refund'
      : 'คุณสามารถเลือกรออีก 15 นาที หรือยกเลิกออเดอร์และขอคืนเงินได้';
  static String get canWaitOrCancel => en
      ? 'You can wait 15 more minutes or cancel this order'
      : 'คุณสามารถเลือกรออีก 15 นาที หรือยกเลิกออเดอร์นี้ได้';
  static String get waiting => en ? 'Waiting...' : 'รออยู่...';
  static String get wait15More => en ? 'Wait 15 more minutes' : 'รออีก 15 นาที';
  static String get cancelOrder => en ? 'Cancel order' : 'ยกเลิกออเดอร์';
  static String get savingReview => en ? 'Saving...' : 'กำลังบันทึก...';
  static String get submittingSlip => en ? 'Submitting slip...' : 'กำลังส่งสลิป...';

  // ---------------------------------------------------------------------------
  // Main / home / location setup (main.dart)
  // ---------------------------------------------------------------------------

  static String get appTitle => en ? 'VANTALAD' : 'แว๊นตลาด';
  static String get appBrand => appTitle;
  static String get splashTagline => en
      ? 'Non Sung Market online delivery'
      : 'ตลาดโนนสูง ออนไลน์ เดลิเวอรี่';

  static String get homeTab => en ? 'Home' : 'โฮม';
  static String get cartTab => cartTitle;
  static String get customerTab => customer;
  static String get notificationsTab =>
      en ? 'Notifications' : 'แจ้งเตือน';
  static String get settingsTab => settingsTitle;

  static String quickActionLabel(String id) {
    switch (id) {
      case 'travel':
        return en ? 'Travel' : 'เดินทาง';
      case 'restaurant':
        return en ? 'Restaurants' : 'ร้านอาหาร';
      case 'market':
        return en ? 'Market' : 'ตลาด';
      case 'shop':
        return shopFallback;
      case 'pharmacy':
        return en ? 'Pharmacy' : 'ร้านขายยา';
      case 'shop-map':
        return mapLabel;
      case 'nationwide-shipping':
        return nationwideShipping;
      case 'more':
        return en ? 'More' : 'เพิ่มเติม';
      default:
        return id;
    }
  }

  static String get locationAutoDetectFailed => en
      ? 'Could not detect location automatically. Please pick a point on the map and confirm.'
      : 'ไม่สามารถระบุตำแหน่งอัตโนมัติได้ กรุณาเลือกพิกัดบนแผนที่แล้วกดยืนยัน';

  static String get browserLocationUnsupported => en
      ? 'This browser does not support location. Please pick a point on the map instead.'
      : 'เบราว์เซอร์ไม่รองรับการระบุตำแหน่ง กรุณาเลือกพิกัดบนแผนที่แทน';

  static String get enableCustomerLocationTitle =>
      en ? 'Enable customer location' : 'เปิดตำแหน่งลูกค้า';

  static String get enableCustomerLocationBody => en
      ? 'Location is off. Enable Location before automatic detection can work.'
      : 'ระบบยังปิดตำแหน่งอยู่ ต้องเปิด Location ก่อนจึงจะระบุตำแหน่งอัตโนมัติได้';

  static String get goEnableLocation =>
      en ? 'Open location settings' : 'ไปเปิดตำแหน่ง';

  static String get resumeAppAutoDetectLocation => en
      ? 'Return to the app and we will try to detect your location again'
      : 'กลับเข้าแอปแล้วระบบจะลองระบุตำแหน่งให้อัตโนมัติ';

  static String get cannotOpenLocationSettings => en
      ? 'Could not open location settings. Please enable Location manually on your device.'
      : 'ไม่สามารถเปิดหน้าตั้งค่าตำแหน่งได้ กรุณาเปิด Location ในเครื่องด้วยตนเอง';

  static String get browserLocationPermissionHint => en
      ? 'Tap the lock icon in the browser address bar and allow location access'
      : 'กรุณากดไอคอนแม่กุญแจในแถบที่อยู่ของเบราว์เซอร์ แล้วอนุญาตการเข้าถึงตำแหน่ง';

  static String get locationPermissionRequiredTitle => en
      ? 'Location permission required'
      : 'ต้องอนุญาตสิทธิ์ตำแหน่ง';

  static String get locationPermissionDeniedForeverBody => en
      ? 'Location permission was permanently denied. Open app settings to allow it.'
      : 'คุณปิดสิทธิ์ตำแหน่งแบบถาวรไว้ กรุณาไปที่ตั้งค่าแอปเพื่ออนุญาตสิทธิ์ตำแหน่ง';

  static String get goAppSettings => en ? 'Open app settings' : 'ไปตั้งค่าแอป';

  static String get cannotOpenAppSettings => en
      ? 'Could not open App Settings. Please enable location permission manually in app settings.'
      : 'ไม่สามารถเปิดหน้า App Settings ได้ กรุณาเปิดสิทธิ์ตำแหน่งในตั้งค่าแอปด้วยตนเอง';

  static String get locationPermissionDeniedWeb => en
      ? 'Allow location when the browser asks, or pick a point on the map'
      : 'กรุณาอนุญาตตำแหน่งเมื่อเบราว์เซอร์ถาม หรือเลือกพิกัดบนแผนที่';

  static String get locationPermissionDeniedNative => en
      ? 'Location permission not granted. Please allow it to continue.'
      : 'ยังไม่ได้รับสิทธิ์ตำแหน่ง กรุณาอนุญาตเพื่อใช้งานต่อ';

  static String get searchingCurrentCoordinates => en
      ? 'Finding your current coordinates...'
      : 'กำลังค้นหาพิกัดปัจจุบันของคุณ...';

  static String autoDetectLocationFailedWithError(Object error) => en
      ? 'Automatic location detection failed: $error'
      : 'ดึงตำแหน่งอัตโนมัติไม่สำเร็จ: $error';

  static String get pickYourLocationTitle =>
      en ? 'Pick your location' : 'เลือกพิกัดของคุณ';

  static String get confirmThisLocation =>
      en ? 'Confirm this location' : 'ยืนยันพิกัดนี้';

  static String get enterValidLatLng => en
      ? 'Please enter valid latitude and longitude'
      : 'กรุณากรอกละติจูดและลองจิจูดให้ถูกต้อง';

  static String get coordinatesOutOfRange => en
      ? 'Coordinates are outside the usable range'
      : 'ค่าพิกัดอยู่นอกช่วงที่ใช้งานได้';

  static String get manualCoordinatesFallback =>
      en ? 'Manually entered coordinates' : 'พิกัดที่กรอกเอง';

  static String get specifyLocationBeforeHome => en
      ? 'Please set a location before entering the home screen'
      : 'กรุณาระบุตำแหน่งก่อนเข้าสู่หน้าหลัก';

  static String get confirmLocationTitle =>
      en ? 'Confirm location' : 'ยืนยันตำแหน่ง';

  static String get specifyLocationBeforeUse => en
      ? 'Set your location before use'
      : 'ระบุตำแหน่งก่อนเข้าใช้งาน';

  static String get locationSetupHint => en
      ? 'We will try to find your coordinates automatically first. If that fails, pick a location yourself and confirm to continue.'
      : 'แอพจะลองหาพิกัดของคุณอัตโนมัติก่อน หากไม่ได้คุณสามารถเลือกพิกัดเองแล้วกดยืนยันเพื่อเข้าสู่หน้าหลัก';

  static String get readyLocationLabel =>
      en ? 'Ready-to-use location' : 'ตำแหน่งที่พร้อมใช้งาน';

  static String get noConfirmedLocationYet => en
      ? 'No confirmed location yet'
      : 'ยังไม่มีตำแหน่งที่ยืนยัน';

  static String get pickLocationOnMap =>
      en ? 'Pick location on map' : 'เลือกพิกัดเองบนแผนที่';

  static String get saveManualCoordinates => en
      ? 'Save entered coordinates'
      : 'บันทึกพิกัดที่กรอกเอง';

  static String get retryAutoDetectLocation => en
      ? 'Try automatic location again'
      : 'ลองระบุตำแหน่งอัตโนมัติอีกครั้ง';

  static String get confirmAndEnterHome => en
      ? 'Confirm and go to home'
      : 'ยืนยันและเข้าสู่หน้าหลัก';

  static String get cartExpiredRestoredStock => en
      ? 'Cart expired after 1 hour — product stock restored'
      : 'ตะกร้าหมดเวลา 1 ชั่วโมง คืนสต๊อกสินค้าแล้ว';

  static String get cannotReserveStock =>
      en ? 'Could not reserve product stock' : 'ไม่สามารถจองสต๊อกสินค้าได้';

  static String cannotReserveStockWithMessage(String message) => en
      ? 'Could not reserve product stock ($message)'
      : 'ไม่สามารถจองสต๊อกสินค้าได้ ($message)';

  static String get pressBackAgainToExit => en
      ? 'Press back again to exit the app'
      : 'กดปุ่มกลับอีกครั้งเพื่อออกจากแอป';

  static String get destinationUpdated => en
      ? 'Destination coordinates updated'
      : 'อัปเดตพิกัดปลายทางเรียบร้อยแล้ว';

  static String get travelPlannerConfigured => en
      ? 'Pickup, destination, time, and vehicle type are set'
      : 'ตั้งค่าจุดรับ จุดส่ง เวลา และประเภทรถเรียบร้อยแล้ว';

  static String get noReorderableProducts => en
      ? 'No products available to reorder'
      : 'ไม่พบสินค้าที่สั่งซ้ำได้';

  static String get addedToCartCheckPrice => en
      ? 'Added to cart — check current prices before paying'
      : 'เพิ่มสินค้าในตะกร้าแล้ว — ตรวจสอบราคาปัจจุบันก่อนชำระเงิน';

  static String get pasteSharedCoordinatesTitle => pasteCoordinates;

  static String get pasteSharedCoordinatesHint => en
      ? 'e.g. 13.7563,100.5018 or a Google Maps URL'
      : 'เช่น 13.7563,100.5018 หรือ Google Maps URL';

  static String get sharedLinkNoCoordinates => en
      ? 'No coordinates found in this link. Try sharing with coordinates or a map pin instead.'
      : 'ไม่พบพิกัดในลิงก์นี้ ลองแชร์แบบมีพิกัดหรือปักหมุดจากแผนที่แทน';

  static String get sharedCoordinatesFallback =>
      en ? 'Shared coordinates' : 'พิกัดที่แชร์มา';

  static String get destinationUpdatedFromShare => en
      ? 'Destination updated from shared coordinates'
      : 'อัปเดตปลายทางจากพิกัดที่แชร์มาแล้ว';

  static String cannotUseSharedCoordinates(Object error) => en
      ? 'Could not use shared coordinates: $error'
      : 'ไม่สามารถใช้พิกัดที่แชร์มาได้: $error';

  static String get qrNotShopQr =>
      en ? 'This QR code is not a shop QR' : 'QR นี้ไม่ใช่ QR ร้านค้า';

  static String get shopProductsFromQr =>
      en ? 'Shop products from QR' : 'สินค้าร้านจาก QR';

  static String categoryNotConnected(String label) => en
      ? 'Category $label is not connected to shop data yet'
      : 'หมวด $label ยังไม่ได้เชื่อมต่อข้อมูลร้านค้า';

  static String get searchAllProductsInBrand => en
      ? 'Search all products in VANTALAD'
      : 'ค้นหาทุกสินค้าในแว๊นตลาด';

  static String get shopProductsTitle =>
      en ? 'Shop products' : 'สินค้าร้าน';

  static String get signInBeforeCheckoutConfirm => en
      ? 'Please sign in before confirming your order'
      : 'กรุณาเข้าสู่ระบบก่อนยืนยันคำสั่งซื้อ';

  static String get pleaseTryAgain =>
      en ? 'Please try again' : 'กรุณาลองใหม่อีกครั้ง';

  static String get identityVerificationFailedRetry => en
      ? 'Could not verify your identity. Please try again.'
      : 'ไม่สามารถยืนยันตัวตนล่าสุดได้ กรุณาลองใหม่อีกครั้ง';

  static String get cashOnDeliveryLabel =>
      en ? 'Cash on delivery' : 'จ่ายปลายทาง';

  static String get cashOnDeliveryStatusLabel => cashOnDeliveryLabel;

  static String get customerCreatedCodOrder => en
      ? 'Customer created a cash-on-delivery order'
      : 'ลูกค้าสร้างออเดอร์แบบจ่ายปลายทาง';

  static String get customerCreatedTravelCodOrder => en
      ? 'Customer created a cash-on-delivery travel request'
      : 'ลูกค้าสร้างคำขอเดินทางแบบจ่ายปลายทาง';

  static String get noCheckoutQuoteYet => en
      ? 'Checkout quote is not ready yet. Please wait for pricing.'
      : 'ยังไม่มี checkout quote กรุณารอระบบคำนวณยอดสักครู่';

  static String get paymentVerifiedStatusLabel =>
      en ? 'Paid' : 'ชำระเงินแล้ว';

  static String get customerPaidOmiseCreatedOrder => en
      ? 'Customer paid via Omise and the order was created'
      : 'ลูกค้าชำระเงินผ่าน Omise และสร้างออเดอร์แล้ว';

  static String get checkoutContextIncomplete => en
      ? 'Checkout data is incomplete'
      : 'ข้อมูล checkout ไม่ครบ';

  static String get customerPaidPromptPayCreatedOrder => en
      ? 'Customer paid via PromptPay and the order was created'
      : 'ลูกค้าสแกนจ่ายพร้อมเพย์และสร้างออเดอร์แล้ว';

  static String get slipVerifiedAndOrderCreated => en
      ? 'Slip verified and order created'
      : 'ตรวจสลิปผ่านและสร้างออเดอร์แล้ว';

  static String slipVerifiedOrderCreatedMessage(String message, int count) =>
      en
          ? '$message\nOrder created ($count items)'
          : '$message\nสร้างออเดอร์แล้ว $count รายการ';

  static String get saveDiscountFailedContactAdmin => en
      ? 'Failed to record discount usage. Please contact support.'
      : 'บันทึกการใช้ส่วนลดไม่สำเร็จ กรุณาติดต่อผู้ดูแลระบบ';

  static String get travelSlipPaymentNotSupported => en
      ? 'Slip payment for travel is not supported yet'
      : 'การชำระด้วยสลิปสำหรับเดินทางยังไม่รองรับ';

  static String get travelServiceLabel =>
      en ? 'Travel service' : 'บริการเดินทาง';

  static String get orderSuccessTrackInCustomerTab => en
      ? 'Order placed — track status in the Customer tab'
      : 'สั่งซื้อสำเร็จ — ติดตามสถานะได้ที่แท็บลูกค้า';

  static String createOrderFailedWithError(Object error) =>
      en ? 'Could not create order: $error' : 'ไม่สามารถสร้างออเดอร์ได้: $error';

  static String createTravelOrderFailedWithError(Object error) => en
      ? 'Could not create travel order: $error'
      : 'ไม่สามารถสร้างออเดอร์เดินทางได้: $error';

  static String get customerPaidOmiseCreatedTravelOrder => en
      ? 'Customer paid via Omise and the travel request was created'
      : 'ลูกค้าชำระเงินผ่าน Omise และสร้างคำขอเดินทางแล้ว';

  static String tabUnderDevelopment(String tabLabel) => en
      ? '$tabLabel page is under development'
      : 'หน้า $tabLabel กำลังพัฒนา';

  static List<String> get bottomNavTabLabels => <String>[
        homeTab,
        cartTab,
        customerTab,
        notificationsTab,
        settingsTab,
      ];

  static String get homeFeaturedProductsShelf =>
      en ? 'Featured products' : 'สินค้าแนะนำ';

  static String get homeBestSellingShelf =>
      en ? 'Best sellers' : 'สินค้าขายดี';

  static String get homePersonalizedShelf => en
      ? 'Products you may like'
      : 'สินค้าที่คุณอาจรู้จัก';

  // ---------------------------------------------------------------------------
  // Help center (UI chrome — article bodies stay in help_center_content)
  // ---------------------------------------------------------------------------

  static String get helpSearchHint =>
      en ? 'Search help articles' : 'ค้นหาบทความช่วยเหลือ';
  static String get helpPopular =>
      en ? 'Popular articles' : 'บทความยอดนิยม';
  static String get helpCategories => en ? 'Categories' : 'หมวดหมู่';
  static String get helpStillNeed =>
      en ? 'Still need help?' : 'ยังต้องการความช่วยเหลือ?';
  static String get helpContactCta =>
      en ? 'Contact admin support' : 'ติดต่อแอดมิน';
  static String get helpNoArticlesFound =>
      en ? 'No articles found' : 'ไม่พบบทความ';
  static String get helpRatesRealtimeSync => en
      ? 'Rates sync from admin settings in real time'
      : 'อัตราดึงจากตั้งค่าแอดมินแบบ real-time';
  static String get deleteAccount => en ? 'Delete account' : 'ลบบัญชี';
  static String get deleteAccountSubtitle => en
      ? 'Permanently delete your account and data'
      : 'ลบบัญชีและข้อมูลของคุณอย่างถาวร';

  // ---------------------------------------------------------------------------
  // In-app notifications (notification_screen)
  // ---------------------------------------------------------------------------

  static String get notificationsTitle => notificationsTab;
  static String get chatTitle => en ? 'Chat' : 'แชต';
  static String get notificationSignInTitle => signInRequired;
  static String get notificationSignInMessage => en
      ? 'Sign in to view your notifications'
      : 'เข้าสู่ระบบเพื่อดูแจ้งเตือนของคุณ';
  static String get notificationLoadFailedTitle => en
      ? 'Failed to load notifications'
      : 'โหลดแจ้งเตือนไม่สำเร็จ';
  static String get notificationLoadFailedMessage => en
      ? 'Check your internet connection and try again'
      : 'กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
  static String get notificationEmptyTitle =>
      en ? 'No notifications yet' : 'ยังไม่มีแจ้งเตือน';
  static String get notificationEmptyMessage => en
      ? 'Order updates and important messages will appear here'
      : 'อัปเดตคำสั่งซื้อและข้อความสำคัญจะแสดงที่นี่';
  static String get notificationAllRead =>
      en ? 'All notifications read' : 'อ่านแจ้งเตือนครบแล้ว';
  static String notificationNewCount(int count) => en
      ? '$count new notification(s)'
      : 'มีแจ้งเตือนใหม่ $count รายการ';
  static String get markAllRead => en ? 'Mark all read' : 'อ่านทั้งหมด';
  static String get notificationNoTicketId => en
      ? 'This notification has no message ID'
      : 'แจ้งเตือนนี้ไม่มีรหัสข้อความ';
  static String get notificationNoOrderId => en
      ? 'This notification has no order ID'
      : 'แจ้งเตือนนี้ไม่มีรหัสออเดอร์';
  static String get badgeNew => en ? 'New' : 'ใหม่';
  static String get notificationNewDefaultTitle =>
      en ? 'New notification' : 'แจ้งเตือนใหม่';
  static String get notificationActionAdminAnnouncement => en
      ? 'Admin announcement'
      : 'ประกาศจากแอดมิน';
  static String get notificationActionAdminMessage =>
      en ? 'Admin message' : 'ข้อความแอดมิน';
  static String get notificationActionMessage =>
      en ? 'Message' : 'ข้อความ';
  static String get notificationActionOpenOrder =>
      en ? 'Open order' : 'เปิดออเดอร์';
  static String get notificationActionDefault =>
      en ? 'Notification' : 'แจ้งเตือน';

  static String timeAgoMinutes(int minutes) =>
      en ? '$minutes min' : '$minutes นาที';
  static String timeAgoHours(int hours) => en ? '$hours hr' : '$hours ชม.';
  static String timeAgoDays(int days) => en ? '$days d' : '$days วัน';
  static String timeAgoDate(int day, int month, int year) => en
      ? '$day/$month/$year'
      : '$day/$month/${year + 543}';

  // ---------------------------------------------------------------------------
  // Legacy notifications_screen (merchant-style order alerts)
  // ---------------------------------------------------------------------------

  static String get alertsTitle => en ? 'Alerts' : 'การแจ้งเตือน';
  static String get orderAcceptedSnack =>
      en ? 'Order accepted' : 'รับออเดอร์เรียบร้อยแล้ว';
  static String get orderRejectedSnack =>
      en ? 'Order rejected' : 'ปฏิเสธออเดอร์แล้ว';
  static String errorOccurred(Object error) =>
      en ? 'An error occurred: $error' : 'เกิดข้อผิดพลาด: $error';
  static String get signInForAlerts => en
      ? 'Please sign in to view alerts'
      : 'กรุณาเข้าสู่ระบบเพื่อดูการแจ้งเตือน';
  static String get noAlertsYet =>
      en ? 'No alerts yet' : 'ยังไม่มีการแจ้งเตือน';
  static String get alertFallbackTitle =>
      en ? 'Notification' : 'แจ้งเตือน';
  static String get noTimeData => en ? 'No time data' : 'ไม่มีข้อมูลเวลา';
  static String newOrderNumber(String id) =>
      en ? 'New order #$id' : 'ออเดอร์ใหม่ #$id';
  static String get orderTimeLabel => en ? 'Time' : 'เวลา';
  static String itemCountLabel(int count) =>
      en ? 'Items: $count' : 'จำนวน: $count รายการ';
  static String totalAmountBaht(String amount) =>
      en ? 'Total: $amount THB' : 'ยอดรวม: $amount บาท';
  static String get reject => en ? 'Reject' : 'ปฏิเสธ';
  static String get acceptOrder => en ? 'Accept order' : 'รับออเดอร์';

  // ---------------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------------

  static String get searchTooltip => en ? 'Search' : 'ค้นหา';
  static String get addFriendTooltip => en ? 'Add friend' : 'เพิ่มเพื่อน';
  static String get friendAddedSuccess =>
      en ? 'Friend added' : 'เพิ่มเพื่อนสำเร็จ';
  static String get userNotFound => en ? 'User not found' : 'ไม่พบผู้ใช้';
  static String get loadFriendsError => en
      ? 'Failed to load friend list'
      : 'เกิดข้อผิดพลาดในการโหลดรายชื่อเพื่อน';
  static String get noFriendsYet =>
      en ? 'No friends yet' : 'ยังไม่มีเพื่อนในระบบ';
  static String get searchFriendsOrMessages => en
      ? 'Search friends or messages'
      : 'ค้นหาเพื่อนหรือข้อความ';
  static String get officialAccount =>
      en ? 'Official account' : 'บัญชีทางการ';
  static String get addFriendByShopName => en
      ? 'Add friend by shop name'
      : 'เพิ่มเพื่อนด้วยชื่อร้าน';
  static String get addFriendByShopHint => en
      ? 'Pick a shop below to add as a friend'
      : 'เลือกจากรายชื่อร้านค้าด้านล่างเพื่อเพิ่มเป็นเพื่อน';
  static String get shopsYouMayKnow =>
      en ? 'Shops you may know' : 'ร้านค้าที่อาจรู้จัก';
  static String get noShopsToAddFriend => en
      ? 'No other shops available to add yet'
      : 'ยังไม่มีร้านค้าอื่นที่พร้อมให้เพิ่มเป็นเพื่อน';
  static String get addAction => en ? 'Add' : 'เพิ่ม';
  static String get pleaseSignInAgain => en
      ? 'Please sign in again'
      : 'โปรดเข้าสู่ระบบอีกครั้ง';
  static String get currentUserNotFound => en
      ? 'Current user not found'
      : 'ไม่พบข้อมูลผู้ใช้ปัจจุบัน';
  static String cannotStartChatRoom(Object error) => en
      ? 'Could not start chat room: $error'
      : 'ไม่สามารถเริ่มห้องแชทได้: $error';
  static String get startConversationFirst =>
      en ? 'Start the conversation' : 'เริ่มต้นสนทนาก่อนเลย';
  static String get typeMessageHint =>
      en ? 'Type a message' : 'พิมพ์ข้อความ';
  static String sendMessageFailed(Object error) => en
      ? 'Failed to send message: $error'
      : 'ส่งข้อความไม่สำเร็จ: $error';
  static String get pickFromGallery =>
      en ? 'Choose from gallery' : 'เลือกรูปจากคลังภาพ';
  static String get takePhoto => en ? 'Take photo' : 'ถ่ายรูป';
  static String get pickVideoFile => en
      ? 'Record or choose video'
      : 'บันทึก/เลือกรูปแบบวิดีโอ';
  static String get pickDocument =>
      en ? 'Choose document' : 'เลือกไฟล์เอกสาร';
  static String uploadFileFailed(Object error) => en
      ? 'Upload failed: $error'
      : 'อัปโหลดไฟล์ไม่สำเร็จ: $error';
  static String get videoFile => en ? 'Video file' : 'ไฟล์วิดีโอ';
  static String get attachmentFile => en ? 'Attachment' : 'ไฟล์แนบ';
  static String get callDeclined => en ? 'Call declined' : 'ยกเลิกสาย';
  static String get callMissed => en ? 'Missed call' : 'ไม่ได้รับสาย';
  static String callDuration(int minutes, String seconds) => en
      ? 'Talked $minutes:$seconds'
      : 'สนทนา $minutes:$seconds';
  static String get callLogDefault =>
      en ? 'Call log' : 'บันทึกการโทร';

  // ---------------------------------------------------------------------------
  // Voice / video call
  // ---------------------------------------------------------------------------

  static String get callServerDataMissing => en
      ? 'Call data not found on server — please try again'
      : 'ไม่พบข้อมูลการโทรจากเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง';
  static String get microphonePermission => en ? 'Microphone' : 'ไมโครโฟน';
  static String get cameraPermission => en ? 'Camera' : 'กล้อง';
  static String permissionRequiredForCall(String name) => en
      ? 'Allow $name access to use calling'
      : 'ต้องอนุญาต$nameก่อนจึงจะใช้การโทรได้';
  static String get reconnecting =>
      en ? 'Reconnecting...' : 'กำลังเชื่อมต่อใหม่...';
  static String get callConnectionFailed => en
      ? 'Connection failed — please try again'
      : 'การเชื่อมต่อล้มเหลว กรุณาลองใหม่อีกครั้ง';
  static String cannotConnectCallService(Object error) => en
      ? 'Could not connect to calling service ($error)'
      : 'ไม่สามารถเชื่อมต่อบริการโทรได้ ($error)';
  static String get incomingCall => en ? 'Incoming call' : 'มีสายเข้า';
  static String get acceptCall => en ? 'Accept' : 'รับสาย';
  static String get declineCall => en ? 'Decline' : 'ไม่รับ';
  static String get cameraOffSelf =>
      en ? 'Your camera is off' : 'คุณปิดกล้อง';
  static String get waitingForPeer => en
      ? 'Waiting for the other party...'
      : 'กำลังรอคู่สนทนา...';
  static String get enableCamera => en ? 'Turn camera on' : 'เปิดกล้อง';
  static String get disableCamera => en ? 'Turn camera off' : 'ปิดกล้อง';
  static String get speaker => en ? 'Speaker' : 'ลำโพง';
  static String get hangUp => en ? 'Hang up' : 'วางสาย';
  static String get enableMic => en ? 'Unmute' : 'เปิดไมค์';
  static String get disableMic => en ? 'Mute' : 'ปิดไมค์';
  static String get connecting => en ? 'Connecting...' : 'กำลังเชื่อมต่อ...';
  static String get peerAcceptedConnecting => en
      ? 'Other party answered — connecting...'
      : 'อีกฝ่ายรับสายแล้ว กำลังเชื่อมต่อ...';
  static String get callingVideo =>
      en ? 'Calling (video)...' : 'กำลังโทรหา (วิดีโอ)';
  static String get callingAudio =>
      en ? 'Calling...' : 'กำลังโทรหา';
  static String get talkingWith =>
      en ? 'Talking with' : 'กำลังสนทนากับ';
  static String get callServiceConnectFailed => en
      ? 'Could not connect to calling service — please try again'
      : 'เชื่อมต่อบริการโทรไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  static String get cannotReachCaller => en
      ? 'Could not reach the caller'
      : 'ไม่สามารถเชื่อมต่อกับผู้โทรได้';
  static String get destinationNoAnswer => en
      ? 'No answer from destination'
      : 'ปลายทางไม่ตอบรับการโทร';

  // ---------------------------------------------------------------------------
  // Admin support
  // ---------------------------------------------------------------------------

  static String maxImagesAttached(int max) => en
      ? 'You can attach up to $max images'
      : 'แนบรูปได้สูงสุด $max รูป';
  static String pickImageFailed(Object error) => en
      ? 'Could not pick image: $error'
      : 'เลือกรูปไม่สำเร็จ: $error';
  static String get selectTopic =>
      en ? 'Please select a topic' : 'กรุณาเลือกหัวข้อ';
  static String get enterCustomTopic => en
      ? 'Please enter your topic'
      : 'กรุณาพิมพ์หัวข้อที่ต้องการสอบถาม';
  static String get topicTooLong => en ? 'Topic is too long' : 'หัวข้อยาวเกินไป';
  static String get messageSentToAdmin => en
      ? 'Message sent to admin — awaiting reply'
      : 'ส่งข้อความถึงแอดมินแล้ว รอการติดต่อกลับ';
  static String sendFailed(Object error) =>
      en ? 'Send failed: $error' : 'ส่งไม่สำเร็จ: $error';
  static String sentFrom(String label) =>
      en ? 'Sent from: $label' : 'ส่งจาก: $label';
  static String get contactAdminIntro => en
      ? 'Choose a topic, describe the issue, and attach images (auto-compressed)'
      : 'เลือกหัวข้อที่ตรงกับปัญหา อธิบายรายละเอียด และแนบรูปประกอบได้ (บีบอัดอัตโนมัติ)';
  static String linkedToOrder(String orderId) => en
      ? 'Linked to order: $orderId'
      : 'ผูกกับออเดอร์: $orderId';
  static String get topicToAsk =>
      en ? 'Topic' : 'หัวข้อที่ต้องการสอบถาม';
  static String get customTopicLabel =>
      en ? 'Custom topic' : 'พิมพ์หัวข้อเอง';
  static String get detailsLabel => en ? 'Details' : 'รายละเอียด';
  static String get detailsHint => en
      ? 'Describe the issue, when it happened, or order ID if any'
      : 'อธิบายปัญหา วันที่เกิดขึ้น หรือเลขออเดอร์ (ถ้ามี)';
  static String attachImagesCount(int current, int max) => en
      ? 'Attach images ($current/$max)'
      : 'แนบรูป ($current/$max)';
  static String get sending => en ? 'Sending...' : 'กำลังส่ง...';
  static String get sendToAdmin => en ? 'Send to admin' : 'ส่งถึงแอดมิน';
  static String get adminConversationTitle =>
      en ? 'Chat with admin' : 'สนทนากับแอดมิน';
  static String get callAdminTooltip =>
      en ? 'Call admin (in-app)' : 'โทรแอดมิน (ในแอป)';
  static String get noMessagesFound =>
      en ? 'No messages found' : 'ไม่พบข้อความ';
  static String get youLabel => en ? 'You' : 'คุณ';
  static String get adminLabel => en ? 'Admin' : 'แอดมิน';
  static String get ticketClosedReadOnly => en
      ? 'This ticket is closed — read-only history'
      : 'เรื่องนี้ปิดแล้ว — ดูประวัติการสนทนาได้อย่างเดียว';
  static String statusLabelText(String status) =>
      en ? 'Status: $status' : 'สถานะ: $status';
  static String get supportStatusOpen =>
      en ? 'Waiting for admin' : 'รอแอดมินตอบ';
  static String get supportStatusInProgress =>
      en ? 'In progress' : 'กำลังติดตาม';
  static String get supportStatusResolved =>
      en ? 'Resolved' : 'แก้ไขแล้ว';
  static String get supportStatusClosed => en ? 'Closed' : 'ปิดเรื่อง';
  static String get typeMessageToAdminHint => en
      ? 'Type a message to admin...'
      : 'พิมพ์ข้อความถึงแอดมิน...';
  static String get newMessageTooltip =>
      en ? 'New message' : 'ส่งข้อความใหม่';
  static String get contactNew => en ? 'New contact' : 'ติดต่อใหม่';
  static String get noSupportMessagesYet => en
      ? 'No messages yet'
      : 'ยังไม่มีข้อความ';
  static String get tapToAskAdmin => en
      ? 'Tap the button below to ask admin'
      : 'กดปุ่มด้านล่างเพื่อส่งคำถามถึงแอดมิน';
  static String loadFailedNewline(Object error) => en
      ? 'Load failed\n$error'
      : 'โหลดไม่สำเร็จ\n$error';

  static String adminSupportTopicLabel(String key) {
    return switch (key) {
      'order_issue' => en
          ? 'Order / order status issue'
          : 'ปัญหาการสั่งซื้อ / สถานะออเดอร์',
      'payment_refund' => en
          ? 'Payment / refund request'
          : 'การชำระเงิน / ขอคืนเงิน',
      'delivery_rider' => en
          ? 'Delivery / rider issue'
          : 'ปัญหาการจัดส่ง / ไรเดอร์',
      'product_shop' => en
          ? 'Product quality / shop issue'
          : 'คุณภาพสินค้า / ร้านค้า',
      'product_claim' => en ? 'Product claim' : 'ขอเคลมสินค้า',
      'account_login' => en ? 'Account / sign-in' : 'บัญชี / เข้าสู่ระบบ',
      'privacy_rights' => en
          ? 'Privacy rights (PDPA)'
          : 'สิทธิข้อมูลส่วนบุคคล (PDPA)',
      'app_bug' => en ? 'Report app bug' : 'แจ้งข้อผิดพลาดแอป',
      'custom' => en ? 'Other (custom topic)' : 'อื่นๆ (พิมพ์หัวข้อเอง)',
      _ => key,
    };
  }

  // ---------------------------------------------------------------------------
  // Product claim
  // ---------------------------------------------------------------------------

  static String get claimReasonMismatch =>
      en ? 'Not as described' : 'ไม่ตรงปก';
  static String get claimReasonDamaged => en ? 'Damaged' : 'เสียหาย';
  static String get claimReasonWrongItem =>
      en ? 'Wrong item' : 'ส่งผิดชิ้น';
  static String get claimReasonOther => en ? 'Other' : 'อื่น ๆ';
  static String get selectClaimProducts => en
      ? 'Select at least one item to claim'
      : 'เลือกสินค้าที่ต้องการเคลมอย่างน้อย 1 รายการ';
  static String get signInBeforeClaim => en
      ? 'Please sign in before submitting a claim'
      : 'กรุณาเข้าสู่ระบบก่อนขอเคลม';
  static String claimLoadOrderFailed(Object error) => en
      ? 'Failed to load order: $error'
      : 'โหลดออเดอร์ไม่สำเร็จ: $error';
  static String get selectProductsToClaim => en
      ? 'Select products to claim'
      : 'เลือกสินค้าที่ต้องการเคลม';
  static String get orderHasNoProducts => en
      ? 'This order has no product items'
      : 'ออเดอร์นี้ไม่มีรายการสินค้า';
  static String get reasonLabel => en ? 'Reason' : 'เหตุผล';
  static String get additionalDetailsOptional => en
      ? 'Additional details (optional)'
      : 'รายละเอียดเพิ่มเติม (ไม่บังคับ)';
  static String imageNumber(int n) => en ? 'Image $n' : 'รูป $n';
  static String get submitClaimToAdmin => en
      ? 'Submit claim to admin'
      : 'ส่งคำขอเคลมถึงแอดมิน';

  // ---------------------------------------------------------------------------
  // Shop QR scanner
  // ---------------------------------------------------------------------------

  static String get scanShopQrTitle =>
      en ? 'Scan shop QR' : 'สแกน QR ร้านค้า';
  static String get scanShopQrHint => en
      ? 'Scan the shop QR to open that shop\'s online catalog'
      : 'สแกน QR หน้าร้าน เพื่อเปิดรายการสินค้าออนไลน์ของร้านนั้น';

  // ---------------------------------------------------------------------------
  // Payment checkout / Omise
  // ---------------------------------------------------------------------------

  static String paymentFailed(Object error) => en
      ? 'Payment failed: $error'
      : 'ชำระเงินไม่สำเร็จ: $error';
  static String get paymentTitle => en ? 'Payment' : 'ชำระเงิน';
  static String get codTitle => cashOnDeliveryLabel;
  static String get codSubtitle => en
      ? 'Pay when you receive the order'
      : 'ชำระเงินเมื่อได้รับสินค้า';
  static String get omiseScanPromptPayQr =>
      en ? 'Scan PromptPay QR' : 'สแกน QR พร้อมเพย์';
  static String get omiseMobileBankTransfer =>
      en ? 'Mobile banking transfer' : 'โอนผ่านแอปธนาคาร';
  static String get omiseTrueMoneyOtpConfirm => en
      ? 'Confirm OTP in TrueMoney Wallet'
      : 'ยืนยัน OTP ใน TrueMoney Wallet';
  static String get selectBank => en ? 'Select bank' : 'เลือกธนาคาร';
  static String get selectBankHint => en
      ? 'The selected bank app will open to confirm payment'
      : 'ระบบจะเปิดแอปธนาคารที่เลือกเพื่อยืนยันการชำระเงิน';
  static String get trueMoneyPhoneTitle =>
      en ? 'TrueMoney Wallet number' : 'เบอร์ TrueMoney Wallet';
  static String get trueMoneyPhoneHint => en
      ? 'Enter the number linked to TrueMoney Wallet to receive OTP'
      : 'กรอกเบอร์ที่ผูกกับ TrueMoney Wallet เพื่อรับ OTP และยืนยันการชำระเงิน';
  static String get mobilePhoneLabel => en ? 'Mobile number' : 'เบอร์มือถือ';
  static String get invalidMobileTenDigits => en
      ? 'Enter a 10-digit mobile number (e.g. 0812345678)'
      : 'กรุณากรอกเบอร์มือถือ 10 หลัก (เช่น 0812345678)';
  static String get paymentCancelledMessage =>
      en ? 'Payment cancelled' : 'ยกเลิกการชำระเงิน';
  static String referenceCode(String label) => en
      ? 'Reference: $label'
      : 'รหัสอ้างอิง: $label';
  static String get paymentSuccess => en ? 'Payment successful' : 'ชำระเงินสำเร็จ';
  static String get waitingForPayment => en
      ? 'Waiting for payment...'
      : 'กำลังรอการชำระเงิน...';
  static String get checkAgain => en ? 'Check again' : 'ตรวจสอบอีกครั้ง';
  static String get pollStatusRetrying => en
      ? 'Status check failed — retrying...'
      : 'ตรวจสอบสถานะไม่สำเร็จ กำลังลองใหม่...';
  static String get scanTrueMoney => en ? 'Scan TrueMoney' : 'สแกนจ่าย TrueMoney';
  static String get scanQrBankHint => en
      ? 'Scan QR with your banking app, then wait for confirmation'
      : 'สแกน QR ด้วยแอปธนาคาร แล้วรอระบบยืนยัน';
  static String get scanQrTrueMoneyHint => en
      ? 'Scan QR with TrueMoney app, then wait for confirmation'
      : 'สแกน QR ด้วยแอป TrueMoney แล้วรอระบบยืนยัน';
  static String get payThenWaitConfirm => en
      ? 'Pay and wait for confirmation'
      : 'ชำระเงินแล้วรอระบบยืนยัน';
  static String amountBaht(String amount) =>
      en ? 'Amount ฿$amount' : 'ยอด ฿$amount';
  static String get paymentFailedShort =>
      en ? 'Payment failed' : 'การชำระเงินไม่สำเร็จ';
  static String get paymentTimedOut =>
      en ? 'Payment timed out' : 'หมดเวลาชำระเงิน';
  static String get omiseTestModeHint => en
      ? 'Omise test mode — TEST badge hidden with Live Key'
      : 'โหมดทดสอบ Omise — ป้าย TEST MODE จะไม่แสดงเมื่อใช้ Live Key';
  static String get saveToDevice => en ? 'Save to device' : 'บันทึกลงเครื่อง';
  static String get cannotLoadQr =>
      en ? 'Could not load QR' : 'ไม่สามารถโหลด QR ได้';
  static String get omisePublicKeyMissing => en
      ? 'Omise public key not found for card payment'
      : 'ไม่พบ Omise public key สำหรับชำระด้วยบัตร';
  static String get cardPaymentUnavailable => en
      ? 'Card payment unavailable'
      : 'ไม่สามารถชำระด้วยบัตรได้';
  static String cardPaymentFailed(Object message) => en
      ? 'Card payment failed: $message'
      : 'ชำระด้วยบัตรไม่สำเร็จ: $message';
  static String get enterCardDetails =>
      en ? 'Enter card details' : 'กรอกข้อมูลบัตร';
  static String get savedCards => en ? 'Saved cards' : 'บัตรที่บันทึกไว้';
  static String cardExpires(String label) =>
      en ? 'Expires $label' : 'หมดอายุ $label';
  static String get useNewCard => en ? 'Use new card' : 'ใช้บัตรใหม่';
  static String get payWithSavedCardHint => en
      ? 'Pay with saved card — tap Pay to continue'
      : 'ชำระด้วยบัตรที่บันทึกไว้ — กดชำระเงินเพื่อดำเนินการต่อ';
  static String get cardNumberLabel =>
      en ? 'Credit / debit card number' : 'เลขที่บัตรเครดิต / เดบิต';
  static String get nameOnCard => en ? 'Name on card' : 'ชื่อบนบัตร';
  static String get expiryDate => en ? 'Expiry date' : 'วันหมดอายุ';
  static String get cvvHint => en
      ? '3–4 digit code on the back of the card'
      : 'รหัส 3-4 หลักด้านหลังบัตร';
  static String get saveCardForLater => en
      ? 'Save this card for next time'
      : 'บันทึกบัตรนี้สำหรับทำรายการครั้งถัดไป';
  static String get pciDssNotice => en
      ? 'PCI DSS security standard for credit/debit payments'
      : 'รับรองมาตรฐานความปลอดภัย PCI DSS สำหรับการชำระด้วยบัตรเครดิต/เดบิต';
  static String get secure3dsNotice => en
      ? 'Secure payment with 3D Secure'
      : 'ชำระเงินปลอดภัยด้วยมาตรฐาน 3D Secure';
  static String payAmountBaht(String amount) => en
      ? 'Pay ฿$amount'
      : 'ชำระเงิน ฿$amount';

  // ---------------------------------------------------------------------------
  // Coupons / promotions
  // ---------------------------------------------------------------------------

  static String get noCouponsYet => en
      ? 'No coupons yet — claim from the home screen'
      : 'ยังไม่มีคูปอง — กดรับจากหน้าแรกได้เลย';
  static String couponCode(String code) => en ? 'Code: $code' : 'โค้ด: $code';
  static String get adminClaimCredit =>
      en ? 'Admin claim credit' : 'เครดิตเคลมจากแอดมิน';
  static String get useInCart => en ? 'Use in cart' : 'ใช้ในตะกร้า';
  static String get couponAlreadyClaimedView => en
      ? 'You already claimed this — see My coupons'
      : 'คุณรับคูปองนี้แล้ว — ดูได้ใน "คูปองของฉัน"';
  static String get couponSavedToMyCoupons => en
      ? 'Saved to My coupons'
      : 'เก็บคูปองใน "คูปองของฉัน" แล้ว';
  static String claimCouponFailed(Object error) => en
      ? 'Could not claim coupon: $error'
      : 'รับคูปองไม่สำเร็จ: $error';
  static String minSubtotalBaht(String amount) => en
      ? 'Min. ฿$amount'
      : 'ขั้นต่ำ ฿$amount';
  static String get specialCoupons => en ? 'Special coupons' : 'คูปองพิเศษ';
  static String get couponAlreadyClaimedShort =>
      en ? 'Already claimed' : 'คุณรับคูปองนี้แล้ว';
  static String get claimedBadge => en ? 'Claimed' : 'รับแล้ว';
  static String get homePromoTitle =>
      en ? 'VAN Market promos' : 'โปรโมชั่นแว๊นตลาด';
  static String get tapToShop => en ? 'Tap to shop' : 'แตะเพื่อช้อปเลย';
  static String get promosAvailable => en ? 'Available promos' : 'โปรที่ใช้ได้';
  static String get noPromosInCart => en
      ? 'No promos available for this cart'
      : 'ยังไม่มีโปรที่ใช้ได้ในตะกร้านี้';
  static String get couponsSection => en ? 'Coupons' : 'คูปอง';
  static String couponApplied(String code) => en
      ? 'Coupon $code applied'
      : 'ใช้คูปอง $code แล้ว';
  static String get totalDiscountLabel =>
      en ? 'Total discount' : 'ส่วนลดรวม';
  static String get enterCouponCode =>
      en ? 'Enter coupon code' : 'กรอกรหัสคูปอง';
  static String get removeCoupon => en ? 'Remove coupon' : 'ลบคูปอง';
  static String get apply => en ? 'Apply' : 'ใช้';
  static String promoApplied(String label) => en
      ? '$label applied'
      : 'ใช้ $label แล้ว';
  static String get promoDiscountLabel =>
      en ? 'Promo discount' : 'ส่วนลดโปร';
  static String get couponDiscountLabel =>
      en ? 'Coupon discount' : 'ส่วนลดคูปอง';

  // ---------------------------------------------------------------------------
  // Rider availability / no-rider flows
  // ---------------------------------------------------------------------------

  static String get riderStatusUnavailable => en
      ? 'Rider status unavailable'
      : 'สถานะไรเดอร์ไม่พร้อมใช้งาน';
  static String get loadingOnlineRiders => en
      ? 'Loading online riders...'
      : 'กำลังโหลดไรเดอร์ออนไลน์...';
  static String get liveUpdate => en ? 'Live' : 'อัปเดตสด';
  static String get riderAvailabilityPermissionHint => en
      ? 'Check connection or read permission for system/rider_availability'
      : 'เช็กการเชื่อมต่อหรือสิทธิ์อ่าน system/rider_availability';
  static String get noDeliveryRidersOnline => en
      ? 'No delivery riders online'
      : 'ยังไม่มีไรเดอร์ออนไลน์รับส่งของ';
  static String get noVehicleTypeOnline => en
      ? 'No vehicles of this type online'
      : 'ยังไม่มีรถประเภทนี้ออนไลน์';
  static String deliveryRidersOnlineCount(int count) => en
      ? '$count delivery rider(s) online'
      : 'ไรเดอร์ออนไลน์ $count คน';
  static String get noDeliveryRidersOnlineShort => en
      ? 'No delivery riders online'
      : 'ยังไม่มีไรเดอร์ออนไลน์';
  static String get vehicleFallback => en ? 'Vehicle' : 'รถ';
  static String vehicleTypeNotOnline(String label) => en
      ? 'No $label online'
      : 'ยังไม่มี$labelออนไลน์';
  static String get checkingRiders =>
      en ? 'Checking riders...' : 'กำลังตรวจสอบไรเดอร์...';
  static String get onlineLabel => en ? 'Online' : 'ออนไลน์';
  static String get noRiderDialogTitle => en
      ? 'No rider available right now'
      : 'ยังไม่พบไรเดอร์ในขณะนี้';
  static String get noRiderTravelBody => en
      ? 'Your travel request was created but no rider is online near pickup'
      : 'ระบบสร้างคำขอเดินทางแล้ว แต่ยังไม่มีไรเดอร์รับผู้โดยสารออนไลน์ใกล้จุดรับ';
  static String get noRiderDeliveryBody => en
      ? 'Your order was created but some shops cannot find a rider yet'
      : 'ออเดอร์ของคุณถูกสร้างแล้ว แต่บางร้านยังหาไรเดอร์ไม่ได้ทันที';
  static String get shopsWithoutRider => en
      ? 'Shops still waiting for a rider:'
      : 'ร้านที่ยังหาไรเดอร์ไม่ได้:';
  static String get noRiderNotifyHint => en
      ? 'You will be notified when a rider accepts, or track status on the order screen'
      : 'ระบบจะแจ้งเตือนเมื่อมีไรเดอร์รับงาน หรือคุณสามารถติดตามสถานะได้จากหน้าออเดอร์';
  static String get viewOrderStatus =>
      en ? 'View order status' : 'ดูสถานะออเดอร์';
  static String get waitingNewRider15 => en
      ? 'Waiting for a new rider — retry within 15 minutes'
      : 'กำลังรอไรเดอร์ใหม่ ระบบจะลองหาให้ภายใน 15 นาที';
  static String get findingRiderBeforeSchedule => en
      ? 'Finding a rider before departure time'
      : 'กำลังหาไรเดอร์ให้ก่อนเวลาเดินทาง';
  static String get scheduleTimeNoRider => en
      ? 'Departure time reached but no rider accepted'
      : 'ถึงเวลาเดินทางแล้ว แต่ยังไม่มีไรเดอร์รับงาน';
  static String get noRiderWithin15 => en
      ? 'No rider accepted within 15 minutes'
      : 'ยังไม่มีไรเดอร์รับงานภายใน 15 นาที';
  static String get refundIfNoRiderByDeadline => en
      ? 'If no rider by the deadline, you can request a refund'
      : 'หากยังไม่ได้ไรเดอร์ภายในเวลาที่กำหนด คุณสามารถขอคืนเงินได้';
  static String get cancelIfNoRiderByDeadline => en
      ? 'If no rider by the deadline, you can cancel the order'
      : 'หากยังไม่ได้ไรเดอร์ภายในเวลาที่กำหนด คุณสามารถยกเลิกออเดอร์ได้';
  static String get scheduleApproaching => en
      ? 'Your scheduled departure is approaching'
      : 'เวลาเดินทางที่คุณกำหนดใกล้ถึงแล้ว';
  static String scheduleApproachingAt(String label) => en
      ? 'Departure at $label is approaching'
      : 'เวลาเดินทาง $label ใกล้ถึงแล้ว';
  static String get wait15OrRefund => canWaitOrCancelRefund;
  static String get wait15OrCancel => canWaitOrCancel;
  static String get wait15RiderRetrySnack => en
      ? 'Waiting 15 more minutes — searching for a rider again'
      : 'รอเพิ่ม 15 นาที ระบบจะหาไรเดอร์ให้ใหม่';
  static String get refundRequestSubmitted => en
      ? 'Refund request submitted — our team will process it'
      : 'ส่งคำขอคืนเงินแล้ว ทีมงานจะดำเนินการให้';
  static String refundRequestFailed(Object error) => en
      ? 'Refund request failed: $error'
      : 'ส่งคำขอคืนเงินไม่สำเร็จ: $error';
  static String get requestRefund => en ? 'Request refund' : 'ขอคืนเงิน';

  // ---------------------------------------------------------------------------
  // Order history card / refund dialog
  // ---------------------------------------------------------------------------

  static String get orderAgain => en ? 'Order again' : 'สั่งซื้ออีกครั้ง';
  static String get travelAgain => en ? 'Travel again' : 'เดินทางอีกครั้ง';
  static String get pickupPointShort => pickupPoint;
  static String get dropoffPointShort => en ? 'Drop-off' : 'จุดส่ง';
  static String get paymentAmountLabel =>
      en ? 'Payment amount' : 'ยอดชำระ';
  static String get noChargeSubstitute => en
      ? 'Payment: no charge (substitute)'
      : 'ยอดชำระ: ไม่คิดเงิน (ทดแทน)';
  static String get refundDialogTitle => requestRefund;
  static String get refundDialogBody => en
      ? 'Enter correct account number, name, and bank — must be the account used to pay. Refunds cannot go to other accounts for legal reasons. Totals finalize at 6:00 PM daily; funds arrive between 6:00–8:00 PM.'
      : 'กรุณาใส่หมายเลขบัญชี ชื่อ และธนาคารให้ถูกต้อง และต้องเป็นบัญชีที่โอนมาซื้อเท่านั้น หากเป็นบัญชีอื่นจะไม่สามารถโอนคืนได้ เนื่องจากเกี่ยวข้องกับข้อกฎหมาย ระบบสรุปยอดเวลา 18:00 น. ของทุกวัน และเงินจะเข้าบัญชีช่วง 18:00-20:00 น.';
  static String get accountNumberLabel =>
      en ? 'Account number' : 'หมายเลขบัญชี';
  static String get accountNumberRequired => en
      ? 'Please enter account number'
      : 'กรุณาใส่หมายเลขบัญชี';
  static String get accountHolderName =>
      en ? 'Account holder name' : 'ชื่อเจ้าของบัญชี';
  static String get accountHolderRequired => en
      ? 'Please enter account holder name'
      : 'กรุณาใส่ชื่อเจ้าของบัญชี';
  static String get bankNameLabel => en ? 'Bank name' : 'ชื่อธนาคาร';
  static String get bankNameRequired => en
      ? 'Please enter bank name'
      : 'กรุณาใส่ชื่อธนาคาร';
  static String get confirmRefund => en ? 'Confirm refund' : 'ยืนยันคืนเงิน';

  // ---------------------------------------------------------------------------
  // Product comments
  // ---------------------------------------------------------------------------

  static String get commentsTitle => en ? 'Comments' : 'ความคิดเห็น';
  static String get writeComment => en ? 'Write a comment' : 'เขียนความคิดเห็น';
  static String get commentsLoadFailed => en
      ? 'Could not load comments temporarily'
      : 'โหลดความคิดเห็นไม่สำเร็จชั่วคราว';
  static String get noCommentsYet =>
      en ? 'No comments yet' : 'ยังไม่มีความคิดเห็น';
  static String commentsCount(int count, bool hasMore) => en
      ? 'Comments ($count${hasMore ? '+' : ''})'
      : 'ความคิดเห็น ($count${hasMore ? '+' : ''})';
  static String get viewMoreComments =>
      en ? 'View more comments' : 'ดูความคิดเห็นเพิ่ม';
  static String get signInToAttachPhotos => en
      ? 'Sign in to attach photos'
      : 'เข้าสู่ระบบเพื่อแนบรูปภาพ';
  static String maxCommentImages(int max) => en
      ? 'Up to $max images per comment'
      : 'แนบรูปได้สูงสุด $max รูป';
  static String get commentPermissionDenied => en
      ? 'No permission to post — try signing in again'
      : 'ไม่มีสิทธิ์โพสต์ความคิดเห็น กรุณาลองเข้าสู่ระบบใหม่';
  static String commentPostFailed(String message) => en
      ? 'Post failed: $message'
      : 'โพสต์ไม่สำเร็จ: $message';
  static String get postComment => en ? 'Post comment' : 'แสดงความคิดเห็น';
  static String get signInToComment => en
      ? 'Sign in to comment'
      : 'เข้าสู่ระบบเพื่อแสดงความคิดเห็น';
  static String get writeCommentHint =>
      en ? 'Write a comment...' : 'เขียนความคิดเห็น...';
  static String get attachPhotoTooltip =>
      en ? 'Attach photo' : 'แนบรูป';
  static String get postAction => en ? 'Post' : 'โพสต์';
  static String get justNow => en ? 'Just now' : 'เมื่อสักครู่';
}
