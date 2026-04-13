import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/chat_message.dart';
import 'models/user_profile.dart';
import 'services/chat_service.dart';
import 'services/friend_service.dart';
import 'services/notification_service.dart';
import 'call_screen.dart';
import 'widgets/cached_app_image.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.friendProfile});

  final UserProfile friendProfile;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final FriendService _friendService = FriendService();
  final NotificationService _notificationService = NotificationService();
  final ImagePicker _imagePicker = ImagePicker();

  UserProfile? _currentProfile;
  bool _sending = false;
  bool _uploading = false;
  bool _startingCall = false;
  String? _error;

  String get _chatId => _chatService.chatIdFor(
        _currentProfile?.uid ?? '',
        widget.friendProfile.uid,
      );

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'โปรดเข้าสู่ระบบอีกครั้ง');
      return;
    }
    final profile = await _friendService.getProfile(user.uid) ??
        await _friendService.ensureCurrentUserProfile(user);
    if (!mounted) return;
    setState(() => _currentProfile = profile);
    await _chatService.purgeExpiredMessages(_chatId);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _currentProfile;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.friendProfile.photoUrl != null
                  ? NetworkImage(widget.friendProfile.photoUrl!)
                  : null,
              child: widget.friendProfile.photoUrl == null
                  ? Text(widget.friendProfile.displayName.characters.first.toUpperCase())
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.friendProfile.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'โทรด้วยเสียง',
            icon: const Icon(Icons.call_outlined),
            onPressed: _startingCall ? null : () => _startCall(isVideo: false),
          ),
          IconButton(
            tooltip: 'วิดีโอคอล',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: _startingCall ? null : () => _startCall(isVideo: true),
          ),
        ],
      ),
      body: profile == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator(),
            )
          : Column(
              children: [
                Expanded(child: _buildMessageList(profile)),
                if (_uploading)
                  const LinearProgressIndicator(minHeight: 2),
                _buildComposer(profile),
              ],
            ),
    );
  }

  Widget _buildMessageList(UserProfile profile) {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatService.watchMessages(_chatId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data ?? const [];
        if (messages.isEmpty) {
          return const Center(child: Text('เริ่มต้นสนทนาก่อนเลย'));
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMine = message.senderId == profile.uid;
            return _MessageBubble(message: message, isMine: isMine);
          },
        );
      },
    );
  }

  Widget _buildComposer(UserProfile profile) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.white,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _uploading ? null : () => _openAttachmentSheet(profile),
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'พิมพ์ข้อความ',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _handleSend(profile),
              ),
            ),
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: _sending ? null : () => _handleSend(profile),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSend(UserProfile profile) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _chatService.sendTextMessage(
        sender: profile,
        target: widget.friendProfile,
        text: text,
      );
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ส่งข้อความไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openAttachmentSheet(UserProfile profile) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกรูปจากคลังภาพ'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery, profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('ถ่ายรูป'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera, profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('บันทึก/เลือกรูปแบบวิดีโอ'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('เลือกไฟล์เอกสาร'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile(profile);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source, UserProfile profile) async {
    final file = await _imagePicker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    await _uploadFile(File(file.path), profile,
        type: 'image', contentType: null, fileName: file.name);
  }

  Future<void> _pickVideo(UserProfile profile) async {
    final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    await _uploadFile(File(file.path), profile,
        type: 'video', contentType: null, fileName: file.name);
  }

  Future<void> _pickFile(UserProfile profile) async {
    final result = await FilePicker.platform.pickFiles(withData: false, allowMultiple: false);
    if (result == null) return;
    final picked = result.files.single;
    if (picked.path == null) return;
    await _uploadFile(
      File(picked.path!),
      profile,
      type: 'file',
      contentType: null,
      fileName: picked.name,
    );
  }

  Future<void> _uploadFile(
    File file,
    UserProfile profile, {
    required String type,
    String? contentType,
    required String fileName,
  }) async {
    setState(() => _uploading = true);
    try {
      await _chatService.sendMediaMessage(
        sender: profile,
        target: widget.friendProfile,
        file: file,
        messageType: type,
        fileName: fileName,
        contentType: contentType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('อัปโหลดไฟล์ไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _startCall({required bool isVideo}) async {
    if (_startingCall) return;
    final caller = _currentProfile;
    if (caller == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเริ่มการโทรได้: ไม่พบข้อมูลผู้ใช้ปัจจุบัน')),
      );
      return;
    }

    setState(() => _startingCall = true);

    try {
      // 1. เรียก Cloud Function ผ่าน NotificationService เพื่อสร้าง token และส่ง notification
      final callData = await _notificationService.initiateCall(
        caller: caller,
        callee: widget.friendProfile,
        isVideo: isVideo,
      );

      if (!mounted) return;

      // 2. สร้างโปรไฟล์เป้าหมายจากข้อมูลที่ Cloud Function ส่งกลับ (ถ้ามี)
      UserProfile targetProfile = widget.friendProfile;
      final calleeProfileData = callData['calleeProfile'];
      if (calleeProfileData is Map<String, dynamic>) {
        targetProfile = targetProfile.copyWith(
          displayName: (calleeProfileData['displayName'] as String?) ?? targetProfile.displayName,
          phoneNumber: (calleeProfileData['phoneNumber'] as String?) ?? targetProfile.phoneNumber,
          photoUrl: (calleeProfileData['photoUrl'] as String?) ?? targetProfile.photoUrl,
        );
      }

      // 3. นำทางไปยังหน้าจอการโทร พร้อมข้อมูลที่ได้จาก Cloud Function
      final callResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            channelName: callData['channelId'] as String? ?? _chatId, // ใช้ channelId จาก function
            isVideo: isVideo,
            targetProfile: targetProfile,
            appIdOverride: callData['appId'] as String?,
            tokenOverride: callData['token'] as String?, // ใช้ token จาก function
            isIncoming: false,
          ),
        ),
      );

      final answered = (callResult is Map && callResult['answered'] == true);
      final durationMillis = (callResult is Map ? callResult['durationMillis'] as int? : null);
      final declined = (callResult is Map && callResult['declined'] == true);

      await _chatService.logCallEvent(
        initiator: caller,
        target: widget.friendProfile,
        isVideo: isVideo,
        answered: answered,
        duration: durationMillis != null ? Duration(milliseconds: durationMillis) : null,
        declined: declined,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการเริ่มการโทร: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _startingCall = false);
      }
    }
  }
}
 
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine ? const Color(0xFF00B900) : Colors.white;
    final textColor = isMine ? Colors.white : Colors.black87;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: _buildContent(context, textColor),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Color textColor) {
    switch (message.type) {
      case 'image':
        return GestureDetector(
          onTap: () => _openUrl(message.mediaUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: message.mediaUrl != null
                ? CachedAppImage(imageUrl: message.mediaUrl!, fit: BoxFit.cover)
                : const SizedBox.shrink(),
          ),
        );
      case 'video':
        return _buildAttachmentTile(context,
            icon: Icons.videocam,
            label: message.fileName ?? 'ไฟล์วิดีโอ',
            url: message.mediaUrl);
      case 'call':
        final callIcon = message.callType == 'video'
            ? Icons.videocam_outlined
            : Icons.call_made;
        final callLabel = _buildCallLabel(message);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(callIcon, color: textColor.withOpacity(0.8), size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                callLabel,
                style: TextStyle(color: textColor, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        );
      case 'file':
        return _buildAttachmentTile(context,
            icon: Icons.description,
            label: message.fileName ?? 'ไฟล์แนบ',
            url: message.mediaUrl,
            subtitle: _formatSize(message.fileSize));
      default:
        return Text(message.text ?? '', style: TextStyle(color: textColor, fontSize: 15));
    }
  }

  String _buildCallLabel(ChatMessage message) {
    final status = message.callStatus;
    if (status == 'declined') return 'ยกเลิกสาย';
    if (status == 'missed') return 'ไม่ได้รับสาย';
    if (status == 'answered') {
      final duration = message.callDurationSeconds ?? 0;
      final minutes = (duration ~/ 60).toString().padLeft(2, '0');
      final seconds = (duration % 60).toString().padLeft(2, '0');
      return 'สนทนา $minutes:$seconds';
    }
    return message.text ?? 'บันทึกการโทร';
  }

  Widget _buildAttachmentTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? url,
    String? subtitle,
  }) {
    return InkWell(
      onTap: url == null ? null : () => _openUrl(url),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.download, color: Colors.white70),
        ],
      ),
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes == 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  }

  Future<void> _openUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
