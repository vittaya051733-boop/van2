import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'data/legal_content.dart';
import 'legal_document_screen.dart';
import 'l10n/l10n.dart';
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
          SnackBar(content: Text(L10n.saveNotificationSettingsFailed(error))),
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
          SnackBar(content: Text(L10n.saveMarketingSettingsFailed(error))),
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
        SnackBar(content: Text(L10n.privacyRequestSignInRequired)),
      );
      return;
    }

    final title = switch (type) {
      'export' => L10n.requestDataExport,
      'delete' => L10n.requestAccountDeletion,
      'correct' => L10n.requestDataCorrection,
      _ => L10n.privacyRights,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(L10n.privacyRequestConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.submit),
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
          content: Text(L10n.privacyRequestSubmitted(result.requestId)),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.privacyRequestFailed(error))),
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
        title: Text(L10n.privacyTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: Text(L10n.privacyPolicy),
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
                  title: Text(L10n.termsOfService),
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
                  title: Text(L10n.dataWeCollect),
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
                    L10n.consentPreferences,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text(L10n.pushNotifications),
                  subtitle: Text(L10n.pushNotificationsSubtitle),
                  value: _pushOptIn,
                  onChanged: _busy ? null : _setPushOptIn,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.campaign_outlined),
                  title: Text(L10n.marketingMessages),
                  subtitle: Text(L10n.marketingMessagesSubtitle),
                  value: _marketingOptIn,
                  onChanged: _busy ? null : _setMarketingOptIn,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    L10n.privacyRights,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: Text(L10n.requestDataExport),
                  subtitle: Text(L10n.requestDataExportSubtitle),
                  onTap: _busy ? null : () => _submitPrivacyRequest('export'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: Text(L10n.requestDataCorrection),
                  subtitle: Text(L10n.requestDataCorrectionSubtitle),
                  onTap: _busy ? null : () => _submitPrivacyRequest('correct'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: Text(L10n.requestAccountDeletion),
                  subtitle: Text(L10n.requestAccountDeletionSubtitle),
                  onTap: _busy ? null : () => _submitPrivacyRequest('delete'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: Text(L10n.managePermissions),
                  subtitle: Text(L10n.managePermissionsSubtitle),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openSystemSettings,
                ),
                if (widget.appVersionLabel != null) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(L10n.appVersion),
                    subtitle: Text(widget.appVersionLabel!),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: _openSystemSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(L10n.openAppSettings),
                  ),
                ),
              ],
            ),
    );
  }
}
