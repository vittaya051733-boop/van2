import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/product_comment.dart';
import '../models/product_reaction.dart';
import '../services/product_comment_service.dart';
import '../services/product_reaction_service.dart';

class ProductReactionBar extends StatelessWidget {
  const ProductReactionBar({
    super.key,
    required this.productId,
    required this.shopId,
    this.compact = false,
    this.showLikeDislike = true,
    this.showDislike = true,
    this.showCommentAction = true,
    this.showShareAction = false,
    this.singleRow = false,
    this.onCommentTap,
    this.onShareTap,
  });

  final String productId;
  final String shopId;
  final bool compact;
  final bool showLikeDislike;
  final bool showDislike;
  final bool showCommentAction;
  final bool showShareAction;
  final bool singleRow;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<List<ProductComment>>(
      stream: ProductCommentService.watchComments(
        productId: productId,
        limit: ProductCommentService.defaultPageSize,
      ),
      builder: (context, commentSnapshot) {
        final commentCount = commentSnapshot.data?.length ?? 0;

        return StreamBuilder<ProductReactionStats>(
          stream: ProductReactionService.watchStats(productId: productId),
          builder: (context, statsSnapshot) {
            final stats = statsSnapshot.data ??
                ProductReactionStats(
                  productId: productId,
                  shopId: shopId,
                  likeCount: 0,
                  dislikeCount: 0,
                  loveCount: 0,
                  shareCount: 0,
                );

            if (currentUserId == null) {
              return _ReactionRow(
                stats: stats,
                commentCount: commentCount,
                activeReaction: null,
                compact: compact,
                showLikeDislike: showLikeDislike,
                showDislike: showDislike,
                showCommentAction: showCommentAction,
                showShareAction: showShareAction,
                singleRow: singleRow,
                onCommentTap: onCommentTap,
                onShareTap: onShareTap,
                onToggleReaction: (type) => _promptSignIn(context),
              );
            }

            return StreamBuilder<ProductReactionType?>(
              stream: ProductReactionService.watchUserReaction(
                productId: productId,
                userId: currentUserId,
              ),
              builder: (context, reactionSnapshot) {
                return _ReactionRow(
                  stats: stats,
                  commentCount: commentCount,
                  activeReaction: reactionSnapshot.data,
                  compact: compact,
                  showLikeDislike: showLikeDislike,
                  showDislike: showDislike,
                  showCommentAction: showCommentAction,
                  showShareAction: showShareAction,
                  singleRow: singleRow,
                  onCommentTap: onCommentTap,
                  onShareTap: onShareTap,
                  onToggleReaction: (type) => _toggleReaction(context, type),
                );
              },
            );
          },
        );
      },
    );
  }

  void _promptSignIn(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('กรุณาเข้าสู่ระบบก่อนแสดงความรู้สึก'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleReaction(
    BuildContext context,
    ProductReactionType type,
  ) async {
    try {
      await ProductReactionService.toggleReaction(
        productId: productId,
        shopId: shopId,
        type: type,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.stats,
    required this.commentCount,
    required this.activeReaction,
    this.compact = false,
    this.showLikeDislike = true,
    this.showDislike = true,
    this.showCommentAction = true,
    this.showShareAction = false,
    this.singleRow = false,
    this.onCommentTap,
    this.onShareTap,
    this.onToggleReaction,
  });

  final ProductReactionStats stats;
  final int commentCount;
  final ProductReactionType? activeReaction;
  final bool compact;
  final bool showLikeDislike;
  final bool showDislike;
  final bool showCommentAction;
  final bool showShareAction;
  final bool singleRow;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;
  final ValueChanged<ProductReactionType>? onToggleReaction;

  @override
  Widget build(BuildContext context) {
    final spacing = compact ? 6.0 : 8.0;
    final children = _buildButtons();

    if (singleRow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: _intersperse(children, SizedBox(width: spacing)),
      );
    }

    return Wrap(
      spacing: spacing,
      runSpacing: compact ? 2 : 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  List<Widget> _buildButtons() {
    return <Widget>[
      if (showLikeDislike)
        _ReactionButton(
          compact: compact,
          icon: activeReaction == ProductReactionType.like
              ? Icons.thumb_up
              : Icons.thumb_up_outlined,
          activeColor: const Color(0xFF2563EB),
          count: stats.likeCount,
          isActive: activeReaction == ProductReactionType.like,
          onTap: onToggleReaction == null
              ? null
              : () => onToggleReaction!(ProductReactionType.like),
        ),
      if (showLikeDislike && showDislike)
        _ReactionButton(
          compact: compact,
          icon: activeReaction == ProductReactionType.dislike
              ? Icons.thumb_down
              : Icons.thumb_down_outlined,
          activeColor: const Color(0xFF6B7280),
          count: stats.dislikeCount,
          isActive: activeReaction == ProductReactionType.dislike,
          onTap: onToggleReaction == null
              ? null
              : () => onToggleReaction!(ProductReactionType.dislike),
        ),
      _ReactionButton(
        compact: compact,
        icon: activeReaction == ProductReactionType.love
            ? Icons.favorite
            : Icons.favorite_border,
        activeColor: const Color(0xFFDC2626),
        count: stats.loveCount,
        isActive: activeReaction == ProductReactionType.love,
        onTap: onToggleReaction == null
            ? null
            : () => onToggleReaction!(ProductReactionType.love),
      ),
      if (showCommentAction)
        _CommentActionButton(
          compact: compact,
          count: commentCount,
          onTap: onCommentTap,
        ),
      if (showShareAction)
        _ShareActionButton(
          compact: compact,
          count: stats.shareCount,
          onTap: onShareTap,
        ),
    ];
  }

  List<Widget> _intersperse(List<Widget> items, Widget separator) {
    if (items.isEmpty) {
      return items;
    }
    return <Widget>[
      for (var i = 0; i < items.length; i++) ...<Widget>[
        if (i > 0) separator,
        items[i],
      ],
    ];
  }
}

class _CommentActionButton extends StatelessWidget {
  const _CommentActionButton({
    required this.count,
    this.compact = false,
    this.onTap,
  });

  final int count;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 16.0 : 18.0;
    final horizontalPadding = compact ? 6.0 : 10.0;
    final verticalPadding = compact ? 2.0 : 6.0;

    return Semantics(
      button: true,
      label: 'แสดงความคิดเห็น $count',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.chat_bubble_outline,
                size: iconSize,
                color: const Color(0xFF2563EB),
              ),
              SizedBox(width: compact ? 3 : 4),
              Text(
                '$count',
                style: (compact
                        ? Theme.of(context).textTheme.labelSmall
                        : Theme.of(context).textTheme.bodySmall)
                    ?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareActionButton extends StatelessWidget {
  const _ShareActionButton({
    required this.count,
    this.compact = false,
    this.onTap,
  });

  final int count;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 16.0 : 18.0;
    final horizontalPadding = compact ? 6.0 : 10.0;
    final verticalPadding = compact ? 2.0 : 6.0;

    return Semantics(
      button: true,
      label: 'แชร์ $count',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.share_outlined,
                size: iconSize,
                color: const Color(0xFF059669),
              ),
              SizedBox(width: compact ? 3 : 4),
              Text(
                '$count',
                style: (compact
                        ? Theme.of(context).textTheme.labelSmall
                        : Theme.of(context).textTheme.bodySmall)
                    ?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF059669),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.activeColor,
    required this.count,
    required this.isActive,
    this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final Color activeColor;
  final int count;
  final bool isActive;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 16.0 : 18.0;
    final horizontalPadding = compact ? 6.0 : 10.0;
    final verticalPadding = compact ? 2.0 : 6.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: iconSize,
              color: isActive ? activeColor : const Color(0xFF6B7280),
            ),
            SizedBox(width: compact ? 3 : 4),
            Text(
              '$count',
              style: (compact
                      ? Theme.of(context).textTheme.labelSmall
                      : Theme.of(context).textTheme.bodySmall)
                  ?.copyWith(
                fontWeight: FontWeight.w800,
                color: isActive ? activeColor : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
