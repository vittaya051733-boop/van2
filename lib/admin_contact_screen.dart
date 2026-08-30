import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'l10n/l10n.dart';
import 'services/admin_support_config.dart';
import 'services/admin_support_service.dart';
import 'services/locale_service.dart';

class AdminContactScreen extends StatefulWidget {
  const AdminContactScreen({
    super.key,
    required this.config,
    this.accentColor = const Color(0xFFFF8A1E),
    this.orderId,
  });

  final AdminSupportConfig config;
  final Color accentColor;
  final String? orderId;

  @override
  State<AdminContactScreen> createState() => _AdminContactScreenState();
}

class _AdminContactScreenState extends State<AdminContactScreen> {
  final _messageController = TextEditingController();
  final _customTopicController = TextEditingController();
  final _picker = ImagePicker();

  String? _selectedTopicKey;
  final List<File> _pendingImages = <File>[];
  bool _submitting = false;

  AdminSupportTopic? get _selectedTopic {
    final key = _selectedTopicKey;
    if (key == null) {
      return null;
    }
    for (final topic in widget.config.topics) {
      if (topic.key == key) {
        return topic;
      }
    }
    return null;
  }

  bool get _isCustomTopic =>
      _selectedTopicKey == AdminSupportTopic.customKey;

  @override
  void dispose() {
    _messageController.dispose();
    _customTopicController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining =
        AdminSupportService.maxImages - _pendingImages.length;
    if (remaining <= 0) {
      _showSnack(L10n.maxImagesAttached(AdminSupportService.maxImages));
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
      _showSnack(L10n.pickImageFailed(error));
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack(L10n.signInRequired);
      return;
    }

    final topic = _selectedTopic;
    if (topic == null) {
      _showSnack(L10n.selectTopic);
      return;
    }

    var topicLabel = L10n.adminSupportTopicLabel(topic.key);
    if (_isCustomTopic) {
      topicLabel = _customTopicController.text.trim();
      if (topicLabel.isEmpty) {
        _showSnack(L10n.enterCustomTopic);
        return;
      }
      if (topicLabel.length > AdminSupportService.maxCustomTopicLength) {
        _showSnack(L10n.topicTooLong);
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await AdminSupportService.submit(
        config: widget.config,
        topicKey: topic.key,
        topicLabel: topicLabel,
        message: _messageController.text,
        imageFiles: List<File>.from(_pendingImages),
        orderId: widget.orderId,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.messageSentToAdmin)),
      );
    } catch (error) {
      _showSnack(L10n.sendFailed(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showSnack(String message) {
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
        return Scaffold(
          appBar: AppBar(
            backgroundColor: widget.accentColor,
            foregroundColor: Colors.white,
            title: Text(
              L10n.contactAdmin,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      L10n.sentFrom(widget.config.sourceLabel),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF9A3412),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.contactAdminIntro,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF92400E),
                            height: 1.35,
                          ),
                    ),
                    if ((widget.orderId ?? '').trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        L10n.linkedToOrder(widget.orderId!.trim()),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                L10n.topicToAsk,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              ...widget.config.topics.map((topic) {
                return RadioListTile<String>(
                  value: topic.key,
                  groupValue: _selectedTopicKey,
                  contentPadding: EdgeInsets.zero,
                  title: Text(L10n.adminSupportTopicLabel(topic.key)),
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _selectedTopicKey = value),
                );
              }),
              if (_isCustomTopic) ...<Widget>[
                const SizedBox(height: 4),
                TextField(
                  controller: _customTopicController,
                  enabled: !_submitting,
                  maxLength: AdminSupportService.maxCustomTopicLength,
                  decoration: InputDecoration(
                    labelText: L10n.customTopicLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _messageController,
                enabled: !_submitting,
                maxLines: 6,
                maxLength: AdminSupportService.maxMessageLength,
                decoration: InputDecoration(
                  labelText: L10n.detailsLabel,
                  hintText: L10n.detailsHint,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickImages,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      L10n.attachImagesCount(
                        _pendingImages.length,
                        AdminSupportService.maxImages,
                      ),
                    ),
                  ),
                ],
              ),
              if (_pendingImages.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pendingImages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              _pendingImages[index],
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: -8,
                            right: -8,
                            child: IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              onPressed: _submitting
                                  ? null
                                  : () => setState(
                                        () => _pendingImages.removeAt(index),
                                      ),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_submitting ? L10n.sending : L10n.sendToAdmin),
              ),
            ],
          ),
        );
      },
    );
  }
}
