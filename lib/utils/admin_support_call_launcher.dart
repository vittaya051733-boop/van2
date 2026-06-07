import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../call_screen.dart';
import '../models/user_profile.dart';
import '../services/notification_service.dart';
import '../services/admin_support_config.dart';

class AdminSupportCallLauncher {
  AdminSupportCallLauncher._();

  static Future<void> startVoiceCallToAdmin({
    required BuildContext context,
    String? assignedAdminUid,
  }) async {
    final adminUid = await resolveAdminCalleeUid(
      ticketAssignedAdminUid: assignedAdminUid,
    );
    if (!context.mounted) {
      return;
    }
    if (adminUid == null || adminUid.isEmpty) {
      _showSnack(context, 'ยังไม่มีแอดมินรับเรื่อง — รอแอดมินตอบกลับก่อน');
      return;
    }

    await startVoiceCallToPeer(
      context: context,
      peerUid: adminUid,
      peerLabel: 'แอดมิน',
    );
  }

  static Future<void> startVoiceCallToPeer({
    required BuildContext context,
    required String peerUid,
    required String peerLabel,
    String? phoneNumber,
    String? photoUrl,
    String? sourceApp,
  }) async {
    final trimmedPeerUid = peerUid.trim();
    if (trimmedPeerUid.isEmpty) {
      _showSnack(context, 'ไม่พบบัญชีปลายทางสำหรับเริ่มการโทร');
      return;
    }

    try {
      final caller = await _buildCurrentUserProfile();
      if (!context.mounted) {
        return;
      }
      if (caller.uid == trimmedPeerUid) {
        throw Exception('ไม่สามารถเริ่มการโทรหาบัญชีตัวเองได้');
      }

      final callee = await _buildPeerProfile(
        uid: trimmedPeerUid,
        fallbackLabel: peerLabel,
        fallbackPhone: phoneNumber,
        fallbackPhotoUrl: photoUrl,
        sourceApp: sourceApp,
      );

      final callData = await NotificationService().initiateCall(
        caller: caller,
        callee: callee,
        isVideo: false,
      );

      if (!context.mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            channelName:
                (callData['channelId'] as String?) ??
                _fallbackChannelId(caller.uid, callee.uid),
            isVideo: false,
            targetProfile: callee,
            appIdOverride: callData['appId'] as String?,
            tokenOverride: callData['token'] as String?,
            isIncoming: false,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showSnack(context, 'เริ่มการโทรในแอปไม่สำเร็จ: $error');
    }
  }

  static Future<String?> resolveAdminCalleeUid({
    String? ticketAssignedAdminUid,
  }) async {
    final assigned = ticketAssignedAdminUid?.trim();
    if (assigned != null && assigned.isNotEmpty) {
      return assigned;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('admin_config')
          .doc('support')
          .get();
      final fromConfig = (doc.data()?['primaryAdminUid'] as String?)?.trim();
      if (fromConfig != null && fromConfig.isNotEmpty) {
        return fromConfig;
      }
    } catch (_) {
      // Fall back to compile-time config.
    }

    final configured = kAdminSupportCalleeUid.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return null;
  }

  static Future<UserProfile> _buildCurrentUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception('กรุณาเข้าสู่ระบบก่อนโทร');
    }

    try {
      final customerDoc = await FirebaseFirestore.instance
          .collection('customer_users')
          .doc(user.uid)
          .get();
      if (customerDoc.exists) {
        return UserProfile.fromSnapshot(customerDoc);
      }
    } catch (_) {
      // Use auth profile fallback.
    }

    return UserProfile(
      uid: user.uid,
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email?.trim().isNotEmpty == true
                ? user.email!.trim()
                : 'ผู้ใช้'),
      phoneNumber: user.phoneNumber,
      photoUrl: user.photoURL,
    );
  }

  static Future<UserProfile> _buildPeerProfile({
    required String uid,
    required String fallbackLabel,
    String? fallbackPhone,
    String? fallbackPhotoUrl,
    String? sourceApp,
  }) async {
    final collections = _peerCollectionsForSource(sourceApp);
    for (final collection in collections) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(collection)
            .doc(uid)
            .get();
        if (!doc.exists) {
          continue;
        }
        final data = doc.data();
        if (data == null) {
          continue;
        }
        return UserProfile.fromMap(uid, <String, dynamic>{
          ...data,
          if ((data['phoneNumber'] ?? data['phone']) == null &&
              fallbackPhone?.trim().isNotEmpty == true)
            'phoneNumber': fallbackPhone!.trim(),
          if ((data['photoUrl'] ?? data['imageUrl']) == null &&
              fallbackPhotoUrl?.trim().isNotEmpty == true)
            'photoUrl': fallbackPhotoUrl!.trim(),
        });
      } catch (_) {
        // Try next collection.
      }
    }

    return UserProfile(
      uid: uid,
      displayName: fallbackLabel.trim().isEmpty ? 'ผู้ติดต่อ' : fallbackLabel.trim(),
      phoneNumber: fallbackPhone,
      photoUrl: fallbackPhotoUrl,
    );
  }

  static List<String> _peerCollectionsForSource(String? sourceApp) {
    return switch (sourceApp) {
      'van1' => <String>[
          'market_registrations',
          'shop_registrations',
          'restaurant_registrations',
          'pharmacy_registrations',
          'other_registrations',
        ],
      'van3' => <String>['riders'],
      _ => <String>['customer_users', 'users', 'riders'],
    };
  }

  static String _fallbackChannelId(String uidA, String uidB) {
    final sorted = <String>[uidA, uidB]..sort();
    return 'call_${sorted.join('_')}';
  }

  static void _showSnack(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
