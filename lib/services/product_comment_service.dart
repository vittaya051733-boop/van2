import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/product_comment.dart';
import '../utils/upload_image_compressor.dart';

class ProductCommentService {
  ProductCommentService._();

  static const int maxImagesPerComment = 4;
  static const int defaultPageSize = 10;

  static CollectionReference<Map<String, dynamic>> get _comments =>
      FirebaseFirestore.instance.collection('product_comments');

  static Stream<List<ProductComment>> watchComments({
    required String productId,
    int limit = defaultPageSize,
  }) {
    final normalizedProductId = productId.trim();
    if (normalizedProductId.isEmpty) {
      return Stream<List<ProductComment>>.value(const <ProductComment>[]);
    }

    return _comments
        .where('productId', isEqualTo: normalizedProductId)
        .where('status', isEqualTo: 'visible')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ProductComment.fromDoc)
              .toList(growable: false),
        );
  }

  static Future<String> postComment({
    required String productId,
    required String shopId,
    required String text,
    List<File> pendingImages = const <File>[],
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('ต้องเข้าสู่ระบบก่อนแสดงความคิดเห็น');
    }

    final trimmedText = text.trim();
    if (trimmedText.isEmpty && pendingImages.isEmpty) {
      throw ArgumentError('กรุณาใส่ข้อความหรือแนบรูปภาพ');
    }

    final commentRef = _comments.doc();
    var imageUrls = const <String>[];
    if (pendingImages.isNotEmpty) {
      imageUrls = await _uploadCommentImages(
        customerId: user.uid,
        commentId: commentRef.id,
        files: pendingImages.take(maxImagesPerComment).toList(growable: false),
      );
      if (imageUrls.isEmpty) {
        throw StateError('อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่');
      }
    }

    await commentRef.set(<String, dynamic>{
      'productId': productId.trim(),
      'shopId': shopId.trim(),
      'authorId': user.uid,
      'authorName': _resolveAuthorName(user),
      if (user.photoURL != null && user.photoURL!.trim().isNotEmpty)
        'authorPhotoUrl': user.photoURL!.trim(),
      'text': trimmedText,
      'imageUrls': imageUrls,
      'status': 'visible',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return commentRef.id;
  }

  static Future<List<String>> _uploadCommentImages({
    required String customerId,
    required String commentId,
    required List<File> files,
  }) async {
    if (files.isEmpty) {
      return const <String>[];
    }

    final storage = FirebaseStorage.instance;
    final urls = <String>[];
    for (final source in files) {
      final compressed = await UploadImageCompressor.compressForUpload(source);
      final storagePath =
          'comment_uploads/$customerId/$commentId/${DateTime.now().millisecondsSinceEpoch}_${compressed.fileName}';
      final ref = storage.ref().child(storagePath);
      await ref.putFile(
        compressed.file,
        SettableMetadata(contentType: compressed.contentType),
      );
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  static String _resolveAuthorName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'ลูกค้า';
  }
}
