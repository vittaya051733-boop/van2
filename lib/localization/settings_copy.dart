import 'package:flutter/material.dart';

import '../services/locale_service.dart';

class SettingsCopy {
  SettingsCopy._();

  static bool get _en => LocaleService.instance.isEnglish;

  static String get settingsTitle => _en ? 'Settings' : 'ตั้งค่า';
  static String get helpSection => _en ? 'Help' : 'ช่วยเหลือ';
  static String get helpCenter => _en ? 'Help center' : 'ศูนย์ช่วยเหลือ';
  static String get contactAdmin => _en ? 'Contact admin' : 'ติดต่อแอดมิน';
  static String get adminMessages => _en ? 'Messages to admin' : 'ข้อความถึงแอดมิน';
  static String get adminMessagesSubtitle => _en
      ? 'View admin replies and respond'
      : 'ดูคำตอบจากแอดมินและตอบกลับ';
  static String get securitySection => _en ? 'Security' : 'ความปลอดภัย';
  static String get privacySecurity =>
      _en ? 'Privacy & security' : 'ความเป็นส่วนตัวและความปลอดภัย';
  static String get languageSection => _en ? 'Language' : 'ตั้งค่าภาษา';
  static String get language => _en ? 'Language' : 'ภาษา';
  static String get accountSection => _en ? 'Account' : 'บัญชี';
  static String get logout => _en ? 'Sign out' : 'ออกจากระบบ';
  static String get loggingOut => _en ? 'Signing out...' : 'กำลังออกจากระบบ...';
  static String get logoutTitle => _en ? 'Sign out' : 'ออกจากระบบ';
  static String get logoutConfirm =>
      _en ? 'Do you want to sign out?' : 'คุณต้องการออกจากระบบใช่หรือไม่';
  static String get cancel => _en ? 'Cancel' : 'ยกเลิก';
  static String get userFallback => _en ? 'User' : 'ผู้ใช้';
  static String get chooseLanguage => _en ? 'Choose language' : 'เลือกภาษา';
  static String get thaiLabel => 'ไทย';
  static String get englishLabel => 'English';

  static String get helpSearchHint => _en
      ? 'Search help articles'
      : 'ค้นหาคำถาม เช่น คืนเงิน ติดตามออเดอร์';
  static String get helpPopular => _en ? 'Popular topics' : 'หัวข้อยอดนิยม';
  static String get helpCategories => _en ? 'Categories' : 'หมวดคำถาม';
  static String get helpStillNeed =>
      _en ? 'Still need help?' : 'ยังไม่เจอคำตอบ?';
  static String get helpContactCta =>
      _en ? 'Contact admin' : 'ติดต่อแอดมิน';

  static String get privacyTitle =>
      _en ? 'Privacy & security' : 'ความเป็นส่วนตัวและความปลอดภัย';
  static String get privacyPolicy =>
      _en ? 'Privacy policy' : 'นโยบายความเป็นส่วนตัว';
  static String get termsOfService =>
      _en ? 'Terms of service' : 'ข้อกำหนดการใช้งาน';
  static String get dataWeCollect =>
      _en ? 'Data we collect' : 'ข้อมูลที่เราเก็บ';
  static String get managePermissions =>
      _en ? 'App permissions' : 'จัดการสิทธิ์แอป';
  static String get managePermissionsSubtitle => _en
      ? 'Location, notifications, camera'
      : 'ตำแหน่ง แจ้งเตือน กล้อง';
  static String get deleteAccount =>
      _en ? 'Request account deletion' : 'ขอลบบัญชี';
  static String get deleteAccountSubtitle => _en
      ? 'Submit a request to admin support'
      : 'ส่งคำขอผ่านแอดมิน';
  static String get appVersion => _en ? 'App version' : 'เวอร์ชันแอป';
  static String get openAppSettings =>
      _en ? 'Open system app settings' : 'เปิดตั้งค่าแอปของระบบ';
  static String get lastUpdated => _en ? 'Last updated' : 'อัปเดตล่าสุด';
}
