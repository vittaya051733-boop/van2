import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../utils/upload_image_compressor.dart';
import 'admin_support_config.dart';

class AdminSupportTicketSummary {
  const AdminSupportTicketSummary({
    required this.id,
    required this.sourceApp,
    required this.sourceLabel,
    required this.topicLabel,
    required this.message,
    required this.status,
    required this.unreadForRequester,
    required this.imageUrls,
    this.contactClosed = false,
    this.requesterName,
    this.requesterPhone,
    this.assignedAdminUid,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.createdAt,
  });

  factory AdminSupportTicketSummary.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return AdminSupportTicketSummary(
      id: doc.id,
      sourceApp: (data['sourceApp'] as String?)?.trim() ?? '',
      sourceLabel: (data['sourceLabel'] as String?)?.trim() ?? '',
      topicLabel: (data['topicLabel'] as String?)?.trim() ?? '',
      message: (data['message'] as String?)?.trim() ?? '',
      status: (data['status'] as String?)?.trim() ?? 'open',
      unreadForRequester: data['unreadForRequester'] == true,
      imageUrls: ((data['imageUrls'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .where((url) => url.trim().isNotEmpty)
          .toList(growable: false),
      contactClosed:
          data['contactClosed'] == true || data['status'] == 'closed',
      requesterName: (data['requesterName'] as String?)?.trim(),
      requesterPhone: (data['requesterPhone'] as String?)?.trim(),
      assignedAdminUid: (data['assignedAdminUid'] as String?)?.trim(),
      lastMessagePreview: (data['lastMessagePreview'] as String?)?.trim(),
      lastMessageAt: _readTimestamp(data['lastMessageAt']),
      createdAt: _readTimestamp(data['createdAt']),
    );
  }

  final String id;
  final String sourceApp;
  final String sourceLabel;
  final String topicLabel;
  final String message;
  final String status;
  final bool unreadForRequester;
  final List<String> imageUrls;
  final bool contactClosed;
  final String? requesterName;
  final String? requesterPhone;
  final String? assignedAdminUid;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;

  String get previewText {
    final last = lastMessagePreview?.trim();
    if (last != null && last.isNotEmpty) {
      return last;
    }
    return message;
  }

  bool get isContactClosed => contactClosed || status == 'closed';

  static DateTime? _readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }
}

class AdminSupportMessage {
  const AdminSupportMessage({
    required this.id,
    required this.senderRole,
    required this.senderUid,
    required this.senderName,
    required this.message,
    required this.imageUrls,
    this.createdAt,
  });

  factory AdminSupportMessage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return AdminSupportMessage(
      id: doc.id,
      senderRole: (data['senderRole'] as String?)?.trim() ?? 'requester',
      senderUid: (data['senderUid'] as String?)?.trim() ?? '',
      senderName: (data['senderName'] as String?)?.trim() ?? 'ผู้ใช้',
      message: (data['message'] as String?)?.trim() ?? '',
      imageUrls: ((data['imageUrls'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .where((url) => url.trim().isNotEmpty)
          .toList(growable: false),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  final String id;
  final String senderRole;
  final String senderUid;
  final String senderName;
  final String message;
  final List<String> imageUrls;
  final DateTime? createdAt;

  bool get isAdmin => senderRole == 'admin';
}

class AdminSupportService {
  AdminSupportService._();

  static const int maxImages = 4;
  static const int maxMessageLength = 2000;
  static const int maxCustomTopicLength = 120;
  static const String notificationAction = 'admin_support_reply';

  static CollectionReference<Map<String, dynamic>> get _tickets =>
      FirebaseFirestore.instance.collection('admin_support_tickets');

  static Stream<List<AdminSupportTicketSummary>> streamMyTickets(String uid) {
    return _tickets.where('requesterUid', isEqualTo: uid).limit(50).snapshots().map(
      (snapshot) {
        final items = snapshot.docs
            .map(AdminSupportTicketSummary.fromDoc)
            .toList(growable: true);
        items.sort((AdminSupportTicketSummary a, AdminSupportTicketSummary b) {
          final at = a.lastMessageAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.lastMessageAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
        return items;
      },
    );
  }

  static Stream<AdminSupportTicketSummary?> streamTicket(String ticketId) {
    return _tickets.doc(ticketId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      return AdminSupportTicketSummary.fromDoc(doc);
    });
  }

  static Stream<List<AdminSupportMessage>> streamMessages(String ticketId) {
    return _tickets
        .doc(ticketId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limit(200)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(AdminSupportMessage.fromDoc)
              .toList(growable: false),
        );
  }

  static Future<String> submit({
    required AdminSupportConfig config,
    required String topicKey,
    required String topicLabel,
    required String message,
    List<File> imageFiles = const <File>[],
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('กรุณาเข้าสู่ระบบก่อนติดต่อแอดมิน');
    }

    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw ArgumentError('กรุณาระบุรายละเอียด');
    }
    if (trimmedMessage.length > maxMessageLength) {
      throw ArgumentError('รายละเอียดยาวเกินไป');
    }

    final requesterName = _resolveRequesterName(user);
    final ticketRef = _tickets.doc();
    final ticketId = ticketRef.id;

    final imageUrls = await _uploadImages(
      requesterUid: user.uid,
      ticketId: ticketId,
      imageFiles: imageFiles,
    );

    final preview = _preview(trimmedMessage);
    await ticketRef.set(<String, dynamic>{
      'sourceApp': config.sourceApp,
      'sourceLabel': config.sourceLabel,
      'requesterUid': user.uid,
      'requesterName': requesterName,
      if (user.email?.trim().isNotEmpty == true)
        'requesterEmail': user.email!.trim(),
      if (user.phoneNumber?.trim().isNotEmpty == true)
        'requesterPhone': user.phoneNumber!.trim(),
      'topicKey': topicKey,
      'topicLabel': topicLabel.trim(),
      'message': trimmedMessage,
      'imageUrls': imageUrls,
      'status': 'open',
      'unreadForRequester': false,
      'unreadForAdmin': true,
      'lastMessagePreview': preview,
      'lastMessageRole': 'requester',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    return ticketId;
  }

  static Future<void> replyAsRequester({
    required String ticketId,
    required String message,
    List<File> imageFiles = const <File>[],
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('กรุณาเข้าสู่ระบบก่อน');
    }

    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw ArgumentError('กรุณาระบุข้อความ');
    }
    if (trimmedMessage.length > maxMessageLength) {
      throw ArgumentError('ข้อความยาวเกินไป');
    }

    final ticketRef = _tickets.doc(ticketId);
    final ticketSnap = await ticketRef.get();
    if (!ticketSnap.exists) {
      throw StateError('ไม่พบข้อความ');
    }
    final ticketData = ticketSnap.data() ?? <String, dynamic>{};
    if (ticketData['requesterUid'] != user.uid) {
      throw StateError('ไม่มีสิทธิ์ตอบข้อความนี้');
    }
    if (_isContactClosedMap(ticketData)) {
      throw StateError('เรื่องนี้ปิดแล้ว — ไม่สามารถส่งข้อความเพิ่มได้');
    }

    final imageUrls = await _uploadImages(
      requesterUid: user.uid,
      ticketId: ticketId,
      imageFiles: imageFiles,
    );

    final preview = _preview(trimmedMessage);
    final messageRef = ticketRef.collection('messages').doc();
    final batch = FirebaseFirestore.instance.batch();
    batch.set(messageRef, <String, dynamic>{
      'senderRole': 'requester',
      'senderUid': user.uid,
      'senderName': _resolveRequesterName(user),
      'message': trimmedMessage,
      'imageUrls': imageUrls,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(ticketRef, <String, dynamic>{
      'lastMessagePreview': preview,
      'lastMessageRole': 'requester',
      'unreadForAdmin': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> markReadAsRequester(String ticketId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final ticketRef = _tickets.doc(ticketId);
    final snap = await ticketRef.get();
    if (!snap.exists) {
      return;
    }
    final data = snap.data() ?? <String, dynamic>{};
    if (data['requesterUid'] != user.uid) {
      return;
    }
    if (data['unreadForRequester'] != true) {
      return;
    }
    try {
      await ticketRef.update(<String, dynamic>{
        'unreadForRequester': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Non-fatal: badge may stay until rules deploy; must not crash chat UI.
    }
  }

  static Future<List<String>> _uploadImages({
    required String requesterUid,
    required String ticketId,
    required List<File> imageFiles,
  }) async {
    if (imageFiles.isEmpty) {
      return <String>[];
    }

    final storage = FirebaseStorage.instance;
    final urls = <String>[];
    for (final source in imageFiles.take(maxImages)) {
      final compressed = await UploadImageCompressor.compressForUpload(source);
      final storagePath =
          'admin_support_uploads/$requesterUid/$ticketId/${DateTime.now().millisecondsSinceEpoch}_${compressed.fileName}';
      final ref = storage.ref().child(storagePath);
      await ref.putFile(
        compressed.file,
        SettableMetadata(contentType: compressed.contentType),
      );
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  static String _resolveRequesterName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    final phone = user.phoneNumber?.trim();
    if (phone != null && phone.isNotEmpty) {
      return phone;
    }
    return 'ผู้ใช้';
  }

  static String _preview(String message) {
    final trimmed = message.trim();
    if (trimmed.length <= 120) {
      return trimmed;
    }
    return '${trimmed.substring(0, 117)}...';
  }

  static bool _isContactClosedMap(Map<String, dynamic> data) {
    return data['contactClosed'] == true || data['status'] == 'closed';
  }
}
