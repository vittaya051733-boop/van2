import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n.dart';
import '../models/product_comment.dart';
import '../services/locale_service.dart';
import '../services/product_comment_service.dart';
import 'cached_app_image.dart';

Future<void> showProductCommentsSheet({
  required BuildContext context,
  required String productId,
  required String shopId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return ListenableBuilder(
        listenable: LocaleService.instance,
        builder: (context, _) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        L10n.commentsTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF111827),
                            ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        showProductCommentComposerSheet(
                          context: context,
                          productId: productId,
                          shopId: shopId,
                        );
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        L10n.writeComment,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: <Widget>[
                    ProductCommentList(productId: productId),
                  ],
                ),
              ),
            ],
          );
        },
      );
        },
      );
    },
  );
}

Future<void> showProductCommentComposerSheet({
  required BuildContext context,
  required String productId,
  required String shopId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _ProductCommentComposerSheet(
          productId: productId,
          shopId: shopId,
        ),
      );
    },
  );
}

class ProductCommentList extends StatefulWidget {
  const ProductCommentList({
    super.key,
    required this.productId,
  });

  final String productId;

  @override
  State<ProductCommentList> createState() => _ProductCommentListState();
}

class _ProductCommentListState extends State<ProductCommentList> {
  int _visibleLimit = ProductCommentService.defaultPageSize;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return StreamBuilder<List<ProductComment>>(
      stream: ProductCommentService.watchComments(
        productId: widget.productId,
        limit: _visibleLimit,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              L10n.commentsLoadFailed,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF92400E),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        }

        final comments = snapshot.data ?? const <ProductComment>[];
        final hasMore = comments.length >= _visibleLimit;

        if (comments.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              L10n.noCommentsYet,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 8),
                Text(
                  L10n.commentsCount(comments.length, hasMore),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF111827),
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final comment in comments) ...<Widget>[
              _CommentTile(comment: comment),
              if (comment != comments.last)
                const Divider(height: 20, color: Color(0xFFE5E7EB)),
            ],
            if (hasMore)
              TextButton(
                onPressed: () {
                  setState(() {
                    _visibleLimit += ProductCommentService.defaultPageSize;
                  });
                },
                child: Text(L10n.viewMoreComments),
              ),
          ],
        );
      },
    );
      },
    );
  }
}

class _ProductCommentComposerSheet extends StatefulWidget {
  const _ProductCommentComposerSheet({
    required this.productId,
    required this.shopId,
  });

  final String productId;
  final String shopId;

  @override
  State<_ProductCommentComposerSheet> createState() =>
      _ProductCommentComposerSheetState();
}

class _ProductCommentComposerSheetState
    extends State<_ProductCommentComposerSheet> {
  final TextEditingController _composerController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<File> _pendingImages = <File>[];
  bool _isPosting = false;

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar(L10n.signInToAttachPhotos);
      return;
    }

    final remaining =
        ProductCommentService.maxImagesPerComment - _pendingImages.length;
    if (remaining <= 0) {
      _showSnackBar(
        L10n.maxCommentImages(ProductCommentService.maxImagesPerComment),
      );
      return;
    }

    final picked = await _imagePicker.pickMultiImage(imageQuality: 90);
    if (!mounted || picked.isEmpty) {
      return;
    }

    setState(() {
      _pendingImages.addAll(
        picked.take(remaining).map((file) => File(file.path)),
      );
    });
  }

  Future<void> _submitComment() async {
    if (_isPosting) {
      return;
    }

    setState(() => _isPosting = true);
    try {
      await ProductCommentService.postComment(
        productId: widget.productId,
        shopId: widget.shopId,
        text: _composerController.text,
        pendingImages: List<File>.from(_pendingImages),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (error is FirebaseException) {
        _showSnackBar(
          error.code == 'permission-denied'
              ? L10n.commentPermissionDenied
              : L10n.commentPostFailed(error.message ?? error.code),
        );
      } else if (error is ArgumentError) {
        _showSnackBar(error.message?.toString() ?? error.toString());
      } else {
        _showSnackBar(error.toString().replaceFirst('StateError: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Text(
            L10n.postComment,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF111827),
                ),
          ),
          const SizedBox(height: 12),
          if (user == null)
            Text(
              L10n.signInToComment,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
            )
          else
            _CommentComposer(
              controller: _composerController,
              pendingImages: _pendingImages,
              isPosting: _isPosting,
              onPickImages: _pickImages,
              onRemoveImage: (index) {
                setState(() => _pendingImages.removeAt(index));
              },
              onSubmit: _submitComment,
              authorName: user.displayName ?? L10n.customer,
              authorPhotoUrl: user.photoURL,
            ),
        ],
      ),
    );
      },
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.pendingImages,
    required this.isPosting,
    required this.onPickImages,
    required this.onRemoveImage,
    required this.onSubmit,
    required this.authorName,
    this.authorPhotoUrl,
  });

  final TextEditingController controller;
  final List<File> pendingImages;
  final bool isPosting;
  final VoidCallback onPickImages;
  final ValueChanged<int> onRemoveImage;
  final VoidCallback onSubmit;
  final String authorName;
  final String? authorPhotoUrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AuthorAvatar(
          name: authorName,
          photoUrl: authorPhotoUrl,
          radius: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: L10n.writeCommentHint,
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              if (pendingImages.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
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
                            borderRadius: BorderRadius.circular(10),
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
                            child: Material(
                              color: Colors.black87,
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: () => onRemoveImage(index),
                                customBorder: const CircleBorder(),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: L10n.attachPhotoTooltip,
                    onPressed: isPosting ? null : onPickImages,
                    icon: const Icon(Icons.photo_camera_outlined),
                    color: const Color(0xFF2563EB),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: isPosting ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: isPosting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            L10n.postAction,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final ProductComment comment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AuthorAvatar(
          name: comment.authorName,
          photoUrl: comment.authorPhotoUrl,
          radius: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF111827),
                      ),
                  children: <InlineSpan>[
                    TextSpan(
                      text: comment.authorName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: ' · ${_formatRelativeTime(comment.createdAt)}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (comment.text.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  comment.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF374151),
                        height: 1.35,
                      ),
                ),
              ],
              if (comment.imageUrls.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: comment.imageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedAppImage(
                          imageUrl: comment.imageUrls[index],
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          lightweight: true,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.name,
    this.photoUrl,
    required this.radius,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmedPhoto = photoUrl?.trim();
    if (trimmedPhoto != null && trimmedPhoto.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE5E7EB),
        backgroundImage: NetworkImage(trimmedPhoto),
      );
    }

    final initial =
        name.trim().isNotEmpty ? name.trim().substring(0, 1).toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFDBEAFE),
      child: Text(
        initial,
        style: TextStyle(
          color: const Color(0xFF1D4ED8),
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}

String _formatRelativeTime(DateTime? value) {
  if (value == null) {
    return L10n.justNow;
  }

  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) {
    return L10n.justNow;
  }
  if (diff.inMinutes < 60) {
    return L10n.timeAgoMinutes(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return L10n.timeAgoHours(diff.inHours);
  }
  if (diff.inDays < 7) {
    return L10n.timeAgoDays(diff.inDays);
  }
  return L10n.timeAgoDate(value.day, value.month, value.year);
}
