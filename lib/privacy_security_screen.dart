import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'data/legal_content.dart';
import 'legal_document_screen.dart';
import 'localization/settings_copy.dart';
import 'services/locale_service.dart';
import 'services/notification_service.dart';
import 'services/privacy_consent_service.dart';

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key, this.appVersionLabel});

  final String? appVersionLabel;

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _pushOptIn = false;
  bool _marketingOptIn = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final local =
        await PrivacyConsentService.instance.loadLocalSnapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      _pushOptIn = local?.pushOptIn ?? false;
      _marketingOptIn = local?.marketingOptIn ?? false;
      _loading = false;
    });
  }

  Future<void> _openSystemSettings() async {
    final opened = await openAppSettings();
    if (!opened && mounted) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _setPushOptIn(bool enabled) async {
    setState(() {
      _pushOptIn = enabled;
      _busy = true;
    });
    try {
      if (enabled) {
        await NotificationService().enablePushNotifications();
      }
      await PrivacyConsentService.instance.updatePreference(
        app: PrivacyAppKey.van2Customer,
        pushOptIn: enabled,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกการตั้งค่าแจ้งเตือนไม่สำเร็จ: $error')),
        );
      }
      await _loadPreferences();
      return;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setMarketingOptIn(bool enabled) async {
    setState(() {
      _marketingOptIn = enabled;
      _busy = true;
    });
    try {
      await PrivacyConsentService.instance.updatePreference(
        app: PrivacyAppKey.van2Customer,
        marketingOptIn: enabled,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกการตั้งค่าการตลาดไม่สำเร็จ: $error')),
        );
      }
      await _loadPreferences();
      return;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submitPrivacyRequest(String type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนส่งคำขอ')),
      );
      return;
    }

    final english = LocaleService.instance.isEnglish;
    final title = switch (type) {
      'export' => SettingsCopy.requestDataExport,
      'delete' => SettingsCopy.requestAccountDeletion,
      'correct' => SettingsCopy.requestDataCorrection,
      _ => SettingsCopy.privacyRights,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          english
              ? 'We will create a privacy request and notify admin. Continue?'
              : 'ระบบจะสร้างคำขอ PDPA และแจ้งแอดมิน ต้องการดำเนินการต่อหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(SettingsCopy.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(english ? 'Submit' : 'ส่งคำขอ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await PrivacyConsentService.instance.createPrivacyRequest(
        app: PrivacyAppKey.van2Customer,
        type: type,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            english
                ? 'Request submitted (${result.requestId})'
                : 'ส่งคำขอแล้ว (${result.requestId})',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ส่งคำขอไม่สำเร็จ: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(SettingsCopy.privacyTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: Text(SettingsCopy.privacyPolicy),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LegalDocumentScreen(
                          document: LegalContent.privacyPolicy,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(SettingsCopy.termsOfService),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LegalDocumentScreen(
                          document: LegalContent.termsOfService,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(SettingsCopy.dataWeCollect),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LegalDocumentScreen(
                          document: LegalContent.dataSummary,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    SettingsCopy.consentPreferences,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text(SettingsCopy.pushNotifications),
                  subtitle: Text(SettingsCopy.pushNotificationsSubtitle),
                  value: _pushOptIn,
                  onChanged: _busy ? null : _setPushOptIn,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.campaign_outlined),
                  title: Text(SettingsCopy.marketingMessages),
                  subtitle: Text(SettingsCopy.marketingMessagesSubtitle),
                  value: _marketingOptIn,
                  onChanged: _busy ? null : _setMarketingOptIn,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    SettingsCopy.privacyRights,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: Text(SettingsCopy.requestDataExport),
                  subtitle: Text(SettingsCopy.requestDataExportSubtitle),
                  onTap: _busy ? null : () => _submitPrivacyRequest('export'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: Text(SettingsCopy.requestDataCorrection),
                  subtitle: Text(SettingsCopy.requestDataCorrectionSubtitle),
                  onTap: _busy ? null : () => _submitPrivacyRequest('correct'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: Text(SettingsCopy.requestAccountDeletion),
                  subtitle: Text(SettingsCopy.requestAccountDeletionSubtitle),
                  onTap: _busy ? null : () => _submitPrivacyRequest('delete'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: Text(SettingsCopy.managePermissions),
                  subtitle: Text(SettingsCopy.managePermissionsSubtitle),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openSystemSettings,
                ),
                if (widget.appVersionLabel != null) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(SettingsCopy.appVersion),
                    subtitle: Text(widget.appVersionLabel!),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: _openSystemSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(SettingsCopy.openAppSettings),
                  ),
                ),
              ],
            ),
    );
  }
}
