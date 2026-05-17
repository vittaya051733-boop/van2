import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onLoggedOut,
  });

  final VoidCallback onLoggedOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _settingsAccent = Color(0xFFFF8A1E);
  static const Color _settingsAccentDark = Color(0xFFE55A00);

  bool _isSigningOut = false;

  String _displayName(User? user) {
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    final phoneNumber = user?.phoneNumber?.trim();
    if (phoneNumber != null && phoneNumber.isNotEmpty) return phoneNumber;
    return 'ผู้ใช้';
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
      return CircleAvatar(
        radius: 22,
        backgroundColor: Colors.white,
        backgroundImage: NetworkImage(photoUrl),
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

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _handleLogout() async {
    if (_isSigningOut) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ออกจากระบบ'),
          content: const Text('คุณต้องการออกจากระบบใช่หรือไม่'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ออกจากระบบ'),
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
      } catch (_) {
        // Ignore Google sign-out errors and continue logout flow.
      }

      if (!mounted) {
        return;
      }

      widget.onLoggedOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ออกจากระบบไม่สำเร็จ: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final name = _displayName(currentUser);
    final secondary = _secondaryText(currentUser);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _settingsAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'ตั้งค่า',
          style: TextStyle(fontWeight: FontWeight.w800),
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
          _sectionTitle('ช่วยเหลือ'),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('ศูนย์ช่วยเหลือ'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _snack('ศูนย์ช่วยเหลือ (กำลังเตรียม)'),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('ติดต่อแอดมิน'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _snack('ติดต่อแอดมิน (กำลังเตรียม)'),
          ),
          const Divider(height: 1),
          _sectionTitle('ความปลอดภัย'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('ความเป็นส่วนตัวและความปลอดภัย'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _snack('ความปลอดภัย (กำลังเตรียม)'),
          ),
          const Divider(height: 1),
          _sectionTitle('ตั้งค่าภาษา'),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: const Text('ภาษา'),
            subtitle: const Text('ไทย'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _snack('ตั้งค่าภาษา (กำลังเตรียม)'),
          ),
          const Divider(height: 1),
          _sectionTitle('บัญชี'),
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
              _isSigningOut ? 'กำลังออกจากระบบ...' : 'ออกจากระบบ',
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
  }
}
