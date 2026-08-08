import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/product_reaction.dart';

class ProductReactionService {
  ProductReactionService._();

  static CollectionReference<Map<String, dynamic>> get _stats =>
      FirebaseFirestore.instance.collection('product_reaction_stats');

  static Stream<ProductReactionStats> watchStats({
    required String productId,
  }) {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) {
      return Stream<ProductReactionStats>.value(ProductReactionStats.empty);
    }

    return _stats.doc(normalizedProductId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return ProductReactionStats(
          productId: normalizedProductId,
          shopId: '',
          likeCount: 0,
          dislikeCount: 0,
          loveCount: 0,
          shareCount: 0,
        );
      }
      return ProductReactionStats.fromDoc(snapshot);
    });
  }

  static Stream<ProductReactionType?> watchUserReaction({
    required String productId,
    required String userId,
  }) {
    if (productId.trim().isEmpty || userId.trim().isEmpty) {
      return Stream<ProductReactionType?>.value(null);
    }

    return _stats
        .doc(productId.trim())
        .collection('user_reactions')
        .doc(userId)
        .snapshots()
        .map(
          (snapshot) => ProductReactionTypeCodec.fromWireValue(
            snapshot.data()?['type'] as String?,
          ),
        );
  }

  static Future<void> toggleReaction({
    required String productId,
    required String shopId,
    required ProductReactionType type,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('ต้องเข้าสู่ระบบก่อนกดปฏิกิริยา');
    }

    final normalizedProductId = productId.trim();
    final normalizedShopId = shopId.trim();
    if (normalizedProductId.isEmpty) {
      throw ArgumentError('ไม่พบรหัสสินค้า');
    }

    final statsRef = _stats.doc(normalizedProductId);
    final reactionRef =
        statsRef.collection('user_reactions').doc(user.uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final statsSnap = await transaction.get(statsRef);
      final reactionSnap = await transaction.get(reactionRef);

      var likeCount = 0;
      var dislikeCount = 0;
      var loveCount = 0;

      if (statsSnap.exists) {
        likeCount = (statsSnap.data()?['likeCount'] as num?)?.toInt() ?? 0;
        dislikeCount =
            (statsSnap.data()?['dislikeCount'] as num?)?.toInt() ?? 0;
        loveCount = (statsSnap.data()?['loveCount'] as num?)?.toInt() ?? 0;
      }

      ProductReactionType? previous;
      if (reactionSnap.exists) {
        previous = ProductReactionTypeCodec.fromWireValue(
          reactionSnap.data()?['type'] as String?,
        );
      }

      if (previous == type) {
        switch (previous!) {
          case ProductReactionType.like:
            likeCount = likeCount > 0 ? likeCount - 1 : 0;
          case ProductReactionType.dislike:
            dislikeCount = dislikeCount > 0 ? dislikeCount - 1 : 0;
          case ProductReactionType.love:
            loveCount = loveCount > 0 ? loveCount - 1 : 0;
        }
        transaction.delete(reactionRef);
      } else {
        if (previous != null) {
          switch (previous) {
            case ProductReactionType.like:
              likeCount = likeCount > 0 ? likeCount - 1 : 0;
            case ProductReactionType.dislike:
              dislikeCount = dislikeCount > 0 ? dislikeCount - 1 : 0;
            case ProductReactionType.love:
              loveCount = loveCount > 0 ? loveCount - 1 : 0;
          }
        }
        switch (type) {
          case ProductReactionType.like:
            likeCount += 1;
          case ProductReactionType.dislike:
            dislikeCount += 1;
          case ProductReactionType.love:
            loveCount += 1;
        }
        transaction.set(reactionRef, <String, dynamic>{
          'type': type.wireValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(
        statsRef,
        <String, dynamic>{
          'productId': normalizedProductId,
          'shopId': normalizedShopId,
          'likeCount': likeCount,
          'dislikeCount': dislikeCount,
          'loveCount': loveCount,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> recordShare({
    required String productId,
    required String shopId,
  }) async {
    final normalizedProductId = productId.trim();
    final normalizedShopId = shopId.trim();
    if (normalizedProductId.isEmpty) {
      return;
    }

    final statsRef = _stats.doc(normalizedProductId);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final statsSnap = await transaction.get(statsRef);
      final shareCount = statsSnap.exists
          ? (statsSnap.data()?['shareCount'] as num?)?.toInt() ?? 0
          : 0;

      final payload = <String, dynamic>{
        'productId': normalizedProductId,
        'shopId': normalizedShopId,
        'shareCount': shareCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!statsSnap.exists) {
        payload['likeCount'] = 0;
        payload['dislikeCount'] = 0;
        payload['loveCount'] = 0;
      }

      transaction.set(
        statsRef,
        payload,
        SetOptions(merge: true),
      );
    });
  }
}
