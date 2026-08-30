import '../l10n/l10n.dart';

/// Backward-compatible wrapper during migration to [L10n].
class SettingsCopy {
  SettingsCopy._();

  static String get settingsTitle => L10n.settingsTitle;
  static String get helpSection => L10n.helpSection;
  static String get helpCenter => L10n.helpCenter;
  static String get contactAdmin => L10n.contactAdmin;
  static String get adminMessages => L10n.adminMessages;
  static String get adminMessagesSubtitle => L10n.adminMessagesSubtitle;
  static String get securitySection => L10n.securitySection;
  static String get privacySecurity => L10n.privacySecurity;
  static String get languageSection => L10n.languageSection;
  static String get language => L10n.language;
  static String get accountSection => L10n.accountSection;
  static String get logout => L10n.logout;
  static String get loggingOut => L10n.loggingOut;
  static String get logoutTitle => L10n.logoutTitle;
  static String get logoutConfirm => L10n.logoutConfirm;
  static String get cancel => L10n.cancel;
  static String get userFallback => L10n.userFallback;
  static String get chooseLanguage => L10n.chooseLanguage;
  static String get thaiLabel => L10n.thaiLabel;
  static String get englishLabel => L10n.englishLabel;

  static String get helpSearchHint => L10n.helpSearchHint;
  static String get helpPopular => L10n.helpPopular;
  static String get helpCategories => L10n.helpCategories;
  static String get helpStillNeed => L10n.helpStillNeed;
  static String get helpContactCta => L10n.helpContactCta;

  static String get privacyTitle => L10n.privacyTitle;
  static String get privacyPolicy => L10n.privacyPolicy;
  static String get termsOfService => L10n.termsOfService;
  static String get dataWeCollect => L10n.dataWeCollect;
  static String get managePermissions => L10n.managePermissions;
  static String get managePermissionsSubtitle => L10n.managePermissionsSubtitle;
  static String get deleteAccount => L10n.deleteAccount;
  static String get deleteAccountSubtitle => L10n.deleteAccountSubtitle;
  static String get appVersion => L10n.appVersion;
  static String get openAppSettings => L10n.openAppSettings;
  static String get lastUpdated => L10n.lastUpdated;

  static String get consentPreferences => L10n.consentPreferences;
  static String get pushNotifications => L10n.pushNotifications;
  static String get pushNotificationsSubtitle => L10n.pushNotificationsSubtitle;
  static String get marketingMessages => L10n.marketingMessages;
  static String get marketingMessagesSubtitle => L10n.marketingMessagesSubtitle;
  static String get privacyRights => L10n.privacyRights;
  static String get requestDataExport => L10n.requestDataExport;
  static String get requestDataExportSubtitle => L10n.requestDataExportSubtitle;
  static String get requestDataCorrection => L10n.requestDataCorrection;
  static String get requestDataCorrectionSubtitle =>
      L10n.requestDataCorrectionSubtitle;
  static String get requestAccountDeletion => L10n.requestAccountDeletion;
  static String get requestAccountDeletionSubtitle =>
      L10n.requestAccountDeletionSubtitle;
}
