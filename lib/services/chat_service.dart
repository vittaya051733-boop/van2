import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../storage_helper.dart';

class ChatService {
  ChatService();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = StorageHelper.instance;

  String chatIdFor(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return 'chat_${sorted.join('_')}';
  }

  Stream<List<ChatMessage>> watchMessages(String chatId) {
    final ref = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true);

    return ref.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ChatMessage.fromSnapshot(doc))
              .toList(),
        );
  }

  Future<void> sendTextMessage({
    required UserProfile sender,
    required UserProfile target,
    required String text,
  }) async {
    final chatId = chatIdFor(sender.uid, target.uid);
    final chatDoc = _firestore.collection('chats').doc(chatId);
    await _ensureChatDocument(chatDoc, sender: sender, target: target);

    final now = DateTime.now();
    final messageRef = chatDoc.collection('messages').doc();
    final expiresAt = Timestamp.fromDate(now.add(const Duration(days: 30)));

    await messageRef.set({
      'senderId': sender.uid,
      'senderName': sender.displayName,
      'receiverId': target.uid,
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
    });

    await _updateChatSummary(
      chatDoc,
      lastMessage: text,
      lastMessageType: 'text',
      sender: sender,
    );
  }

  Future<void> sendMediaMessage({
    required UserProfile sender,
    required UserProfile target,
    required File file,
    required String messageType,
    required String fileName,
    String? contentType,
  }) async {
    final chatId = chatIdFor(sender.uid, target.uid);
    final chatDoc = _firestore.collection('chats').doc(chatId);
    await _ensureChatDocument(chatDoc, sender: sender, target: target);

    final storageRef = _storage
        .ref()
        .child('chat_uploads/$chatId/${DateTime.now().millisecondsSinceEpoch}_${p.basename(fileName)}');
    final metadata = SettableMetadata(contentType: contentType ?? _guessMimeType(fileName));
    await storageRef.putFile(file, metadata);
    final downloadUrl = await storageRef.getDownloadURL();

    final summaryText = _summaryForType(messageType, fileName);
    final expiresAt = Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)));
    final messageRef = chatDoc.collection('messages').doc();
    final fileSize = await file.length();
    await messageRef.set({
      'senderId': sender.uid,
      'senderName': sender.displayName,
      'receiverId': target.uid,
      'type': messageType,
      'text': summaryText,
      'mediaUrl': downloadUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'mediaContentType': metadata.contentType,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
    });

    await _updateChatSummary(
      chatDoc,
      lastMessage: summaryText,
      lastMessageType: messageType,
      sender: sender,
    );
  }

  Future<void> logCallEvent({
    required UserProfile initiator,
    required UserProfile target,
    required bool isVideo,
    required bool answered,
    Duration? duration,
    bool declined = false,
  }) async {
    final chatId = chatIdFor(initiator.uid, target.uid);
    final chatDoc = _firestore.collection('chats').doc(chatId);
    await _ensureChatDocument(chatDoc, sender: initiator, target: target);

    final String statusText;
    if (declined) {
      statusText = 'ยกเลิกสาย';
    } else if (!answered) {
      statusText = 'ไม่ได้รับสาย';
    } else {
      statusText = 'สนทนา ${_formatDuration(duration)}';
    }
    final base = isVideo ? 'วิดีโอคอล' : 'โทรด้วยเสียง';
    final description = '$base • $statusText';
    final messageRef = chatDoc.collection('messages').doc();
    await messageRef.set({
      'senderId': initiator.uid,
      'senderName': initiator.displayName,
      'receiverId': target.uid,
      'type': 'call',
      'callType': isVideo ? 'video' : 'voice',
      'direction': 'outgoing',
      'callStatus': answered ? 'answered' : (declined ? 'declined' : 'missed'),
      if (duration != null && answered) 'callDuration': duration.inSeconds,
      'text': description,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _updateChatSummary(
      chatDoc,
      lastMessage: description,
      lastMessageType: 'call',
      sender: initiator,
    );
  }

  Future<void> purgeExpiredMessages(String chatId) async {
    final now = Timestamp.fromDate(DateTime.now());
    final ref = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('expiresAt', isLessThanOrEqualTo: now)
        .limit(50);
    final snapshot = await ref.get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> _ensureChatDocument(
    DocumentReference<Map<String, dynamic>> chatDoc, {
    required UserProfile sender,
    required UserProfile target,
  }) async {
    final snapshot = await chatDoc.get();
    if (snapshot.exists) return;
    await chatDoc.set({
      'participants': [sender.uid, target.uid],
      'participantProfiles': {
        sender.uid: sender.toFirestore(),
        target.uid: target.toFirestore(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateChatSummary(
    DocumentReference<Map<String, dynamic>> chatDoc, {
    required String lastMessage,
    required String lastMessageType,
    required UserProfile sender,
  }) async {
    await chatDoc.set({
      'lastMessage': lastMessage,
      'lastMessageType': lastMessageType,
      'lastMessageSender': sender.uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  String _summaryForType(String type, String fileName) {
    switch (type) {
      case 'image':
        return 'ส่งรูปภาพ';
      case 'video':
        return 'ส่งวิดีโอ';
      case 'file':
        return 'ส่งไฟล์: $fileName';
      case 'call':
        return fileName;
      default:
        return fileName;
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '00:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
