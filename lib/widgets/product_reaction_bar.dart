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
    this.showCommentAction = true,
    this.onCommentTap,
  });

  final String productId;
  final String shopId;
  final bool showCommentAction;
  final VoidCallback? onCommentTap;

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
                );

            if (currentUserId == null) {
              return _ReactionRow(
                stats: stats,
                commentCount: commentCount,
                activeReaction: null,
                showCommentAction: showCommentAction,
                onCommentTap: onCommentTap,
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
                  showCommentAction: showCommentAction,
                  onCommentTap: onCommentTap,
                  onToggleReaction: (type) => _toggleReaction(context, type),
                );
              },
            );
          },
        );
      },
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
    this.showCommentAction = true,
    this.onCommentTap,
    this.onToggleReaction,
  });

  final ProductReactionStats stats;
  final int commentCount;
  final ProductReactionType? activeReaction;
  final bool showCommentAction;
  final VoidCallback? onCommentTap;
  final ValueChanged<ProductReactionType>? onToggleReaction;

  @override
  Widget build(BuildContext context) {
    if (onToggleReaction == null) {
      return Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (stats.likeCount > 0) Text('👍 ${stats.likeCount}'),
          if (stats.dislikeCount > 0) Text('👎 ${stats.dislikeCount}'),
          if (stats.loveCount > 0) Text('❤️ ${stats.loveCount}'),
          if (showCommentAction)
            _CommentActionButton(
              count: commentCount,
              onTap: onCommentTap,
            ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _ReactionButton(
          icon: activeReaction == ProductReactionType.like
              ? Icons.thumb_up
              : Icons.thumb_up_outlined,
          activeColor: const Color(0xFF2563EB),
          count: stats.likeCount,
          isActive: activeReaction == ProductReactionType.like,
          onTap: () => onToggleReaction!(ProductReactionType.like),
        ),
        _ReactionButton(
          icon: activeReaction == ProductReactionType.dislike
              ? Icons.thumb_down
              : Icons.thumb_down_outlined,
          activeColor: const Color(0xFF6B7280),
          count: stats.dislikeCount,
          isActive: activeReaction == ProductReactionType.dislike,
          onTap: () => onToggleReaction!(ProductReactionType.dislike),
        ),
        _ReactionButton(
          icon: activeReaction == ProductReactionType.love
              ? Icons.favorite
              : Icons.favorite_border,
          activeColor: const Color(0xFFDC2626),
          count: stats.loveCount,
          isActive: activeReaction == ProductReactionType.love,
          onTap: () => onToggleReaction!(ProductReactionType.love),
        ),
        if (showCommentAction)
          _CommentActionButton(
            count: commentCount,
            onTap: onCommentTap,
          ),
      ],
    );
  }
}

class _CommentActionButton extends StatelessWidget {
  const _CommentActionButton({
    required this.count,
    this.onTap,
  });

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: Color(0xFF2563EB),
            ),
            if (count > 0) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2563EB),
                    ),
              ),
            ],
          ],
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
    required this.onTap,
  });

  final IconData icon;
  final Color activeColor;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: isActive ? activeColor : const Color(0xFF6B7280),
            ),
            if (count > 0) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isActive ? activeColor : const Color(0xFF6B7280),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
