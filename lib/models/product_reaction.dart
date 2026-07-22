import 'package:cloud_firestore/cloud_firestore.dart';

enum ProductReactionType { like, dislike, love }

extension ProductReactionTypeCodec on ProductReactionType {
  String get wireValue {
    switch (this) {
      case ProductReactionType.like:
        return 'like';
      case ProductReactionType.dislike:
        return 'dislike';
      case ProductReactionType.love:
        return 'love';
    }
  }

  static ProductReactionType? fromWireValue(String? raw) {
    switch (raw) {
      case 'like':
        return ProductReactionType.like;
      case 'dislike':
        return ProductReactionType.dislike;
      case 'love':
        return ProductReactionType.love;
      default:
        return null;
    }
  }
}

class ProductReactionStats {
  const ProductReactionStats({
    required this.productId,
    required this.shopId,
    required this.likeCount,
    required this.dislikeCount,
    required this.loveCount,
  });

  final String productId;
  final String shopId;
  final int likeCount;
  final int dislikeCount;
  final int loveCount;

  factory ProductReactionStats.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ProductReactionStats(
      productId: (data['productId'] as String?) ?? doc.id,
      shopId: (data['shopId'] as String?) ?? '',
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      dislikeCount: (data['dislikeCount'] as num?)?.toInt() ?? 0,
      loveCount: (data['loveCount'] as num?)?.toInt() ?? 0,
    );
  }

  static const ProductReactionStats empty = ProductReactionStats(
    productId: '',
    shopId: '',
    likeCount: 0,
    dislikeCount: 0,
    loveCount: 0,
  );
}
