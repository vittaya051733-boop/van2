import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'utils/admin_support_call_launcher.dart';
import 'l10n/l10n.dart';
import 'services/admin_support_service.dart';
import 'services/locale_service.dart';
import 'widgets/cached_app_image.dart';

class AdminSupportThreadScreen extends StatefulWidget {
  const AdminSupportThreadScreen({
    super.key,
    required this.ticketId,
    this.accentColor = const Color(0xFFFF8A1E),
  });

  final String ticketId;
  final Color accentColor;

  @override
  State<AdminSupportThreadScreen> createState() =>
      _AdminSupportThreadScreenState();
}

class _AdminSupportThreadScreenState extends State<AdminSupportThreadScreen> {
  final _messageController = TextEditingController();
  final _picker = ImagePicker();
  final _scrollController = ScrollController();
  final List<File> _pendingImages = <File>[];
  bool _sending = false;
  String? _assignedAdminUid;
  bool _contactClosed = false;

  @override
  void initState() {
    super.initState();
    AdminSupportService.markReadAsRequester(widget.ticketId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining =
        AdminSupportService.maxImages - _pendingImages.length;
    if (remaining <= 0) {
      _snack(L10n.maxImagesAttached(AdminSupportService.maxImages));
      return;
    }
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) {
        return;
      }
      setState(() {
        _pendingImages.addAll(
          picked.take(remaining).map((file) => File(file.path)),
        );
      });
    } catch (error) {
      _snack(L10n.pickImageFailed(error));
    }
  }

  Future<void> _sendReply() async {
    if (_contactClosed) {
      return;
    }
    setState(() => _sending = true);
    try {
      await AdminSupportService.replyAsRequester(
        ticketId: widget.ticketId,
        message: _messageController.text,
        imageFiles: List<File>.from(_pendingImages),
      );
      _messageController.clear();
      setState(() => _pendingImages.clear());
      await _scrollToBottom();
    } catch (error) {
      _snack(L10n.sendFailed(error));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return StreamBuilder<AdminSupportTicketSummary?>(
      stream: AdminSupportService.streamTicket(widget.ticketId),
      builder: (context, ticketSnapshot) {
        final ticket = ticketSnapshot.data;
        if (ticket != null) {
          if (ticket.assignedAdminUid != _assignedAdminUid ||
              ticket.isContactClosed != _contactClosed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _assignedAdminUid = ticket.assignedAdminUid;
                  _contactClosed = ticket.isContactClosed;
                });
              }
            });
          }
        }

        final contactClosed = ticket?.isContactClosed ?? _contactClosed;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: widget.accentColor,
            foregroundColor: Colors.white,
            title: Text(
              L10n.adminConversationTitle,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: <Widget>[
              if (!contactClosed)
                IconButton(
                  tooltip: L10n.callAdminTooltip,
                  onPressed: () => AdminSupportCallLauncher.startVoiceCallToAdmin(
                    context: context,
                    assignedAdminUid: _assignedAdminUid,
                  ),
                  icon: const Icon(Icons.phone_in_talk_outlined),
                ),
            ],
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: _buildThreadBody(ticket, ticketSnapshot),
              ),
              if (contactClosed)
                const _ClosedContactBanner()
              else
                _Composer(
                  controller: _messageController,
                  pendingImages: _pendingImages,
                  sending: _sending,
                  accentColor: widget.accentColor,
                  onPickImages: _pickImages,
                  onRemoveImage: (index) =>
                      setState(() => _pendingImages.removeAt(index)),
                  onSend: _sendReply,
                ),
            ],
          ),
        );
      },
    );
      },
    );
  }

  Widget _buildThreadBody(
    AdminSupportTicketSummary? ticket,
    AsyncSnapshot<AdminSupportTicketSummary?> ticketSnapshot,
  ) {
    if (ticket == null &&
        ticketSnapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ticket == null) {
      return Center(child: Text(L10n.noMessagesFound));
    }

    return StreamBuilder<List<AdminSupportMessage>>(
      stream: AdminSupportService.streamMessages(widget.ticketId),
      builder: (context, messagesSnapshot) {
        final replies =
            messagesSnapshot.data ?? const <AdminSupportMessage>[];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ticket.unreadForRequester) {
            AdminSupportService.markReadAsRequester(widget.ticketId);
          }
        });

        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          children: <Widget>[
            _ThreadHeader(ticket: ticket, accentColor: widget.accentColor),
            const SizedBox(height: 12),
            _MessageBubble(
              isMine: true,
              senderName: ticket.requesterName ?? L10n.youLabel,
              message: ticket.message,
              imageUrls: ticket.imageUrls,
              createdAt: ticket.createdAt,
              accentColor: widget.accentColor,
            ),
            ...replies.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _MessageBubble(
                  isMine: !item.isAdmin,
                  senderName: item.isAdmin ? L10n.adminLabel : item.senderName,
                  message: item.message,
                  imageUrls: item.imageUrls,
                  createdAt: item.createdAt,
                  accentColor: widget.accentColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ClosedContactBanner extends StatelessWidget {
  const _ClosedContactBanner();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return Material(
      color: const Color(0xFFF3F4F6),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            L10n.ticketClosedReadOnly,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
      },
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.ticket,
    required this.accentColor,
  });

  final AdminSupportTicketSummary ticket;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            ticket.topicLabel,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            L10n.statusLabelText(_statusLabel(ticket.status)),
            style: TextStyle(color: accentColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'open' => L10n.supportStatusOpen,
      'in_progress' => L10n.supportStatusInProgress,
      'resolved' => L10n.supportStatusResolved,
      'closed' => L10n.supportStatusClosed,
      _ => status,
    };
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.isMine,
    required this.senderName,
    required this.message,
    required this.imageUrls,
    required this.accentColor,
    this.createdAt,
  });

  final bool isMine;
  final String senderName;
  final String message;
  final List<String> imageUrls;
  final Color accentColor;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? accentColor.withValues(alpha: 0.12) : const Color(0xFFF1F5F9);
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: <Widget>[
        Text(
          senderName,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(message, style: const TextStyle(height: 1.4)),
              if (imageUrls.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: imageUrls
                      .map(
                        (url) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedAppImage(
                            imageUrl: url,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            lightweight: true,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.pendingImages,
    required this.sending,
    required this.accentColor,
    required this.onPickImages,
    required this.onRemoveImage,
    required this.onSend,
  });

  final TextEditingController controller;
  final List<File> pendingImages;
  final bool sending;
  final Color accentColor;
  final VoidCallback onPickImages;
  final ValueChanged<int> onRemoveImage;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (pendingImages.isNotEmpty)
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: pendingImages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              pendingImages[index],
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              onPressed: sending ? null : () => onRemoveImage(index),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: sending ? null : onPickImages,
                    icon: const Icon(Icons.photo_library_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: !sending,
                      maxLines: 4,
                      minLines: 1,
                      maxLength: AdminSupportService.maxMessageLength,
                      decoration: InputDecoration(
                        hintText: L10n.typeMessageToAdminHint,
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: sending ? null : onSend,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    child: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }
}
