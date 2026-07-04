import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_support_thread_screen.dart';
import 'chat_room_screen.dart';
import 'chat_screen.dart';
import 'models/user_profile.dart';
import 'order_roadmap_screen.dart';
import 'services/admin_support_service.dart';
import 'utils/app_colors.dart';

class NotificationScreen extends StatelessWidget {
  NotificationScreen({
    super.key,
    FirebaseFirestore? firestore,
    this.onOpenOrder,
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;
  final void Function(List<String> orderIds)? onOpenOrder;

  Stream<List<_AppNotification>> _watchNotifications(String uid) {
    return firestore
        .collection('app_notifications')
        .where('recipientUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs
              .map(_AppNotification.fromSnapshot)
              .where((item) {
                final targetApp = item.targetApp.trim();
                return targetApp.isEmpty || targetApp == 'van2';
              })
              .toList(growable: false);
          final sorted = notifications.toList(growable: true)
            ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
          return sorted;
        });
  }

  Future<void> _markAsRead(_AppNotification item) async {
    if (item.isRead) {
      return;
    }
    await item.reference.set(<String, dynamic>{
      'isRead': true,
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _markAllAsRead(List<_AppNotification> items) async {
    final unread = items.where((item) => !item.isRead).toList(growable: false);
    if (unread.isEmpty) {
      return;
    }
    final batch = firestore.batch();
    for (final item in unread.take(450)) {
      batch.set(item.reference, <String, dynamic>{
        'isRead': true,
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> _openNotification(
    BuildContext context,
    _AppNotification item,
  ) async {
    try {
      await _markAsRead(item);
    } catch (_) {
      // เปิดออเดอร์/แชตได้แม้ mark read ล้ม (เช่น rules ชั่วคราว)
    }
    if (!context.mounted) {
      return;
    }

    if (item.isAdminSupportReply) {
      final ticketId = item.ticketId?.trim();
      if (ticketId != null && ticketId.isNotEmpty) {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => AdminSupportThreadScreen(ticketId: ticketId),
          ),
        );
        return;
      }
    }

    if (item.isAdminAnnouncement) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item.title),
          content: SingleChildScrollView(child: Text(item.body)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
      return;
    }

    if (item.isChat) {
      final senderId = item.senderId;
      if (senderId != null && senderId.isNotEmpty) {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatRoomScreen(
              friendProfile: UserProfile.fromMap(senderId, <String, dynamic>{
                'displayName': item.senderName ?? item.title,
              }),
            ),
          ),
        );
        return;
      }
    }

    final orderId = item.orderId?.trim();
    if (orderId == null || orderId.isEmpty) {
      if (item.isAdminSupportReply) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('แจ้งเตือนนี้ไม่มีรหัสข้อความ')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('แจ้งเตือนนี้ไม่มีรหัสออเดอร์')),
        );
      }
      return;
    }

    final openOrder = onOpenOrder;
    if (openOrder != null) {
      openOrder(<String>[orderId]);
      return;
    }

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderRoadmapScreen(orderIds: <String>[orderId]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('แจ้งเตือน'),
        actions: <Widget>[
          IconButton(
            tooltip: 'แชต',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ChatScreen()),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
        ],
      ),
      body: user == null || user.isAnonymous
          ? const _NotificationEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'กรุณาเข้าสู่ระบบ',
              message: 'เข้าสู่ระบบเพื่อดูแจ้งเตือนของคุณ',
            )
          : StreamBuilder<List<_AppNotification>>(
              stream: _watchNotifications(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _NotificationEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'โหลดแจ้งเตือนไม่สำเร็จ',
                    message: 'กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
                  );
                }

                final items = snapshot.data ?? const <_AppNotification>[];
                if (items.isEmpty) {
                  return const _NotificationEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'ยังไม่มีแจ้งเตือน',
                    message: 'อัปเดตคำสั่งซื้อและข้อความสำคัญจะแสดงที่นี่',
                  );
                }

                final unreadCount = items.where((item) => !item.isRead).length;
                return Column(
                  children: <Widget>[
                    _NotificationHeader(
                      unreadCount: unreadCount,
                      onMarkAllRead: unreadCount == 0
                          ? null
                          : () => _markAllAsRead(items),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _NotificationTile(
                            item: item,
                            onTap: () => _openNotification(context, item),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _NotificationHeader extends StatelessWidget {
  const _NotificationHeader({
    required this.unreadCount,
    required this.onMarkAllRead,
  });

  final int unreadCount;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            backgroundColor: Color(0xFFFFEDD5),
            child: Icon(Icons.notifications_active, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              unreadCount == 0
                  ? 'อ่านแจ้งเตือนครบแล้ว'
                  : 'มีแจ้งเตือนใหม่ $unreadCount รายการ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
          ),
          TextButton(
            onPressed: onMarkAllRead,
            child: const Text('อ่านทั้งหมด'),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final _AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = item.isRead ? const Color(0xFF9CA3AF) : AppColors.accent;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.isRead
                  ? const Color(0xFFE5E7EB)
                  : const Color(0xFFFFD7A3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: item.isRead
                    ? const Color(0xFFF3F4F6)
                    : const Color(0xFFFFEDD5),
                child: Icon(item.icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: item.isRead
                                      ? FontWeight.w700
                                      : FontWeight.w900,
                                  color: const Color(0xFF111827),
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.timeLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                    if (item.body.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF4B5563),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _NotificationChip(label: item.actionLabel),
                        if (!item.isRead)
                          const _NotificationChip(label: 'ใหม่'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationChip extends StatelessWidget {
  const _NotificationChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9A3412),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppNotification {
  const _AppNotification({
    required this.id,
    required this.reference,
    required this.title,
    required this.body,
    required this.action,
    required this.targetApp,
    required this.createdAt,
    required this.deliveredAt,
    required this.isRead,
    this.orderId,
    this.ticketId,
    this.senderId,
    this.senderName,
  });

  final String id;
  final DocumentReference<Map<String, dynamic>> reference;
  final String title;
  final String body;
  final String action;
  final String targetApp;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final bool isRead;
  final String? orderId;
  final String? ticketId;
  final String? senderId;
  final String? senderName;

  bool get isChat => action == 'chat_message';
  bool get isAdminSupportReply =>
      action == AdminSupportService.notificationAction;
  bool get isAdminAnnouncement => action == 'admin_announcement';

  DateTime get sortTime =>
      createdAt ?? deliveredAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  IconData get icon {
    if (isAdminAnnouncement) {
      return Icons.campaign_rounded;
    }
    if (isAdminSupportReply) {
      return Icons.support_agent_rounded;
    }
    if (isChat) {
      return Icons.chat_bubble_outline_rounded;
    }
    if (orderId != null && orderId!.isNotEmpty) {
      return Icons.receipt_long_rounded;
    }
    return Icons.notifications_none_rounded;
  }

  String get actionLabel {
    if (isAdminAnnouncement) {
      return 'ประกาศจากแอดมิน';
    }
    if (isAdminSupportReply) {
      return 'ข้อความแอดมิน';
    }
    if (isChat) {
      return 'ข้อความ';
    }
    if (orderId != null && orderId!.isNotEmpty) {
      return 'เปิดออเดอร์';
    }
    return 'แจ้งเตือน';
  }

  String get timeLabel {
    final value = createdAt ?? deliveredAt;
    if (value == null) {
      return '';
    }
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inMinutes < 1) {
      return 'ตอนนี้';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} นาที';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} ชม.';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} วัน';
    }
    return '${value.day}/${value.month}/${value.year + 543}';
  }

  factory _AppNotification.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final title = _readString(data['title']).isEmpty
        ? 'แจ้งเตือนใหม่'
        : _readString(data['title']);
    return _AppNotification(
      id: doc.id,
      reference: doc.reference,
      title: title,
      body: _readString(data['body']).isEmpty
          ? _readString(data['message'])
          : _readString(data['body']),
      action: _readString(data['action']),
      targetApp: _readString(data['targetApp']),
      createdAt: _readTimestamp(data['createdAt']),
      deliveredAt: _readTimestamp(data['deliveredAt']),
      isRead:
          data['isRead'] == true ||
          data['read'] == true ||
          data['readAt'] != null,
      orderId: _emptyToNull(_readString(data['orderId'])),
      ticketId: _emptyToNull(_readString(data['ticketId'])),
      senderId: _emptyToNull(_readString(data['senderId'])),
      senderName: _emptyToNull(_readString(data['senderName'])),
    );
  }

  static String _readString(Object? value) => value?.toString().trim() ?? '';

  static String? _emptyToNull(String value) => value.isEmpty ? null : value;

  static DateTime? _readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
