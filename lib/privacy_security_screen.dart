import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'admin_contact_screen.dart';
import 'data/legal_content.dart';
import 'legal_document_screen.dart';
import 'localization/settings_copy.dart';
import 'services/admin_support_config.dart';

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key, this.appVersionLabel});

  final String? appVersionLabel;

  Future<void> _openSystemSettings(BuildContext context) async {
    final opened = await openAppSettings();
    if (!opened && context.mounted) {
      await Geolocator.openAppSettings();
    }
  }

  void _requestDeletion(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdminContactScreen(
          config: kVan2AdminSupportConfig,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(SettingsCopy.privacyTitle),
      ),
      body: ListView(
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
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: Text(SettingsCopy.managePermissions),
            subtitle: Text(SettingsCopy.managePermissionsSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openSystemSettings(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: Text(SettingsCopy.deleteAccount),
            subtitle: Text(SettingsCopy.deleteAccountSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _requestDeletion(context),
          ),
          if (appVersionLabel != null) ...<Widget>[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(SettingsCopy.appVersion),
              subtitle: Text(appVersionLabel!),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: () => _openSystemSettings(context),
              icon: const Icon(Icons.settings_outlined),
              label: Text(SettingsCopy.openAppSettings),
            ),
          ),
        ],
      ),
    );
  }
}
