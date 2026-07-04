import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'services/notification_service.dart';
import 'services/privacy_consent_service.dart';

/// Blocks [child] until the current privacy policy is accepted locally
/// (and remotely when a real account is signed in).
class PrivacyLaunchGate extends StatefulWidget {
  const PrivacyLaunchGate({
    super.key,
    required this.child,
    required this.app,
  });

  final Widget child;
  final String app;

  @override
  State<PrivacyLaunchGate> createState() => _PrivacyLaunchGateState();
}

class _PrivacyLaunchGateState extends State<PrivacyLaunchGate> {
  bool _ready = false;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runGate();
    });
  }

  Future<void> _runGate() async {
    try {
      final accepted = await PrivacyConsentService.instance.ensureConsent(
        context,
        app: widget.app,
        source: 'launch_gate',
      );
      if (!mounted) {
        return;
      }

      if (!accepted) {
        setState(() {
          _blocked = true;
        });
        return;
      }

      if (!kIsWeb) {
        final local = await PrivacyConsentService.instance.loadLocalSnapshot();
        if (local?.pushOptIn == true) {
          try {
            await NotificationService()
                .enablePushNotifications()
                .timeout(const Duration(seconds: 8));
          } catch (_) {
            // Push opt-in must not block app entry.
          }
        }
      }

      if (!mounted) {
        return;
      }
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return widget.child;
    }

    if (_blocked) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.policy_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'ต้องยอมรับข้อกำหนดและนโยบายความเป็นส่วนตัวก่อนใช้งาน',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _runGate,
                  child: const Text('ดูข้อกำหนดอีกครั้ง'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
