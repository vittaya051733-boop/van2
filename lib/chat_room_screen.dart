import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/chat_message.dart';
import 'models/user_profile.dart';
import 'l10n/l10n.dart';
import 'services/chat_service.dart';
import 'services/friend_service.dart';
import 'services/chat_warmup.dart';
import 'services/chat_warmup_cache.dart';
import 'services/locale_service.dart';
import 'widgets/cached_app_avatar.dart';
import 'widgets/cached_app_image.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.friendProfile,
    this.orderId,
  });

  final UserProfile friendProfile;
  final String? orderId;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final FriendService _friendService = FriendService();
  final ImagePicker _imagePicker = ImagePicker();

  UserProfile? _currentProfile;
  bool _sending = false;
  bool _uploading = false;
  bool _markingAsRead = false;
  String? _error;

  String get _chatId => _chatService.chatIdFor(
        _currentProfile?.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '',
        widget.friendProfile.uid,
      );

  String _chatIdForProfile(UserProfile profile) {
    return _chatService.chatIdFor(profile.uid, widget.friendProfile.uid);
  }

  Future<void> _bindOrderContext(UserProfile profile) async {
    final orderId = widget.orderId?.trim();
    if (orderId == null || orderId.isEmpty) {
      return;
    }
    await FirebaseFirestore.instance.collection('chats').doc(_chatIdForProfile(profile)).set(
      {
        'orderId': orderId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  void initState() {
    super.initState();
    ChatWarmupCache.instance.cacheProfile(widget.friendProfile);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      ChatWarmup.prefetchRoom(
        myUid: user.uid,
        peer: widget.friendProfile,
        chatService: _chatService,
        friendService: _friendService,
      );
    }
    _loadProfileFast();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  UserProfile _profileFromAuth(User user) {
    final displayName = user.displayName?.trim();
    return UserProfile(
      uid: user.uid,
      displayName: displayName != null && displayName.isNotEmpty
          ? displayName
          : L10n.customer,
      phoneNumber: user.phoneNumber,
      photoUrl: user.photoURL,
    );
  }

  Future<void> _loadProfileFast() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = L10n.pleaseSignInAgain);
      return;
    }

    setState(() => _currentProfile = _profileFromAuth(user));
    unawaited(_warmChatInBackground(user));
  }

  Future<void> _warmChatInBackground(User user) async {
    try {
      final profile = await _friendService.getProfile(user.uid) ??
          await _friendService.ensureCurrentUserProfile(user);
      if (profile == null) {
        if (!mounted) return;
        setState(() => _error = L10n.currentUserNotFound);
        return;
      }

      final chatId = _chatIdForProfile(profile);
      unawaited(
        _chatService.ensureChatAvailable(
          sender: profile,
          target: widget.friendProfile,
        ),
      );
      unawaited(_bindOrderContext(profile));
      unawaited(_chatService.purgeExpiredMessages(chatId));
      unawaited(
        _chatService.markChatAsRead(owner: profile, friend: widget.friendProfile),
      );

      if (!mounted) return;
      setState(() => _currentProfile = profile);
    } catch (e) {
      if (!mounted || _currentProfile != null) return;
      setState(() => _error = L10n.cannotStartChatRoom(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    final profile = _currentProfile;
    final friendName = widget.friendProfile.displayName.trim();
    final friendInitial =
        friendName.isNotEmpty ? friendName.characters.first.toUpperCase() : '?';
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CachedAppAvatar(
              imageUrl: widget.friendProfile.photoUrl,
              radius: 18,
              fallback: Text(friendInitial),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _buildChatTitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
      },
    );
  }

  String _buildChatTitle() {
    final orderId = widget.orderId?.trim();
    if (orderId == null || orderId.isEmpty) {
      return widget.friendProfile.displayName;
    }
    final shortOrderId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
    return L10n.en
        ? '${widget.friendProfile.displayName} • Order $shortOrderId'
        : '${widget.friendProfile.displayName} • ออเดอร์ $shortOrderId';
  }

  Widget _buildMessageList(UserProfile profile) {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatService.watchMessages(_chatId),
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.waiting &&
            messages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        _scheduleMarkAsRead(profile);
        if (messages.isEmpty) {
          return Center(child: Text(L10n.startConversationFirst));
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

  void _scheduleMarkAsRead(UserProfile profile) {
    if (_markingAsRead) {
      return;
    }
    _markingAsRead = true;
    unawaited(() async {
      try {
        await _chatService.markChatAsRead(owner: profile, friend: widget.friendProfile);
      } finally {
        _markingAsRead = false;
      }
    }());
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
                decoration: InputDecoration(
                  hintText: L10n.typeMessageHint,
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
            .showSnackBar(SnackBar(content: Text(L10n.sendMessageFailed(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openAttachmentSheet(UserProfile profile) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: LocaleService.instance,
        builder: (context, _) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(L10n.pickFromGallery),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery, profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(L10n.takePhoto),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera, profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: Text(L10n.pickVideoFile),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(L10n.pickDocument),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile(profile);
              },
            ),
          ],
        ),
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
            .showSnackBar(SnackBar(content: Text(L10n.uploadFileFailed(e))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
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
            label: message.fileName ?? L10n.videoFile,
            url: message.mediaUrl);
      case 'call':
        final callIcon = message.callType == 'video'
            ? Icons.videocam_outlined
            : Icons.call_made;
        final callLabel = _buildCallLabel(message);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(callIcon, color: textColor.withValues(alpha: 0.8), size: 18),
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
            label: message.fileName ?? L10n.attachmentFile,
            url: message.mediaUrl,
            subtitle: _formatSize(message.fileSize));
      default:
        return Text(message.text ?? '', style: TextStyle(color: textColor, fontSize: 15));
    }
  }

  String _buildCallLabel(ChatMessage message) {
    final status = message.callStatus;
    if (status == 'declined') return L10n.callDeclined;
    if (status == 'missed') return L10n.callMissed;
    if (status == 'answered') {
      final duration = message.callDurationSeconds ?? 0;
      final minutes = (duration ~/ 60).toString().padLeft(2, '0');
      final seconds = (duration % 60).toString().padLeft(2, '0');
      return L10n.callDuration(int.parse(minutes), seconds);
    }
    return message.text ?? L10n.callLogDefault;
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
