import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'admin_contact_screen.dart';
import 'admin_support_inbox_screen.dart';
import 'help_center_screen.dart';
import 'l10n/l10n.dart';
import 'privacy_security_screen.dart';
import 'services/admin_support_config.dart';
import 'services/locale_service.dart';
import 'widgets/cached_app_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onLoggedOut,
    this.appVersionLabel,
  });

  final VoidCallback onLoggedOut;
  final String? appVersionLabel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _settingsAccent = Color(0xFFFF8A1E);
  static const Color _settingsAccentDark = Color(0xFFE55A00);

  bool _isSigningOut = false;
  String? _appVersionLabel;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersionLabel = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {}
  }

  String _displayName(User? user) {
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    final phoneNumber = user?.phoneNumber?.trim();
    if (phoneNumber != null && phoneNumber.isNotEmpty) return phoneNumber;
    return L10n.defaultUser;
  }

  String? _secondaryText(User? user) {
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    final phoneNumber = user?.phoneNumber?.trim();
    if (phoneNumber != null && phoneNumber.isNotEmpty) return phoneNumber;
    return null;
  }

  Widget _buildAvatar(User? user) {
    final photoUrl = user?.photoURL?.trim();
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CachedAppAvatar(
        imageUrl: photoUrl,
        radius: 22,
        backgroundColor: Colors.white,
      );
    }

    final name = user?.displayName?.trim();
    final email = user?.email?.trim();
    final label = (name != null && name.isNotEmpty)
        ? name
        : (email != null && email.isNotEmpty ? email : null);
    final letter = label?.characters.first.toUpperCase();

    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.white,
      child: letter != null
          ? Text(
              letter,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _settingsAccentDark,
              ),
            )
          : const Icon(
              Icons.person_rounded,
              color: _settingsAccentDark,
            ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final service = LocaleService.instance;
    final selected = await showModalBottomSheet<Locale>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  L10n.chooseLanguage,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ListTile(
                title: Text(L10n.languageThai),
                trailing: service.locale == LocaleService.thai
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(LocaleService.thai),
              ),
              ListTile(
                title: Text(L10n.languageEnglish),
                trailing: service.locale == LocaleService.english
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(LocaleService.english),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      await service.setLocale(selected);
    }
  }

  Future<void> _handleLogout() async {
    if (_isSigningOut) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(L10n.logoutTitle),
          content: Text(L10n.logoutConfirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(L10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(L10n.logout),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _isSigningOut = true);
    try {
      await FirebaseAuth.instance.signOut();
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}

      if (!mounted) {
        return;
      }

      widget.onLoggedOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${L10n.logout}: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final name = _displayName(currentUser);
        final secondary = _secondaryText(currentUser);
        final localeLabel = L10n.localeLabel(LocaleService.instance.locale);

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: _settingsAccent,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              L10n.settingsTitle,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(74),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: Row(
                  children: <Widget>[
                    _buildAvatar(currentUser),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (secondary != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              secondary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: ListView(
            children: <Widget>[
              _sectionTitle(L10n.helpSection),
              ListTile(
                leading: const Icon(Icons.help_outline_rounded),
                title: Text(L10n.helpCenter),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HelpCenterScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.support_agent_rounded),
                title: Text(L10n.contactAdmin),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminContactScreen(
                        config: kVan2AdminSupportConfig,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.mark_chat_unread_outlined),
                title: Text(L10n.adminMessages),
                subtitle: Text(L10n.adminMessagesSubtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminSupportInboxScreen(
                        config: kVan2AdminSupportConfig,
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              _sectionTitle(L10n.securitySection),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(L10n.privacySecurity),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PrivacySecurityScreen(
                        appVersionLabel:
                            _appVersionLabel ?? widget.appVersionLabel,
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              _sectionTitle(L10n.languageSection),
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(L10n.language),
                subtitle: Text(localeLabel),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickLanguage,
              ),
              const Divider(height: 1),
              _sectionTitle(L10n.accountSection),
              ListTile(
                enabled: !_isSigningOut,
                leading: _isSigningOut
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
                title: Text(
                  _isSigningOut ? L10n.loggingOut : L10n.logout,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _isSigningOut ? null : _handleLogout,
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
