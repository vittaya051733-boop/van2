import 'package:cloud_firestore/cloud_firestore.dart';

class ProductComment {
  const ProductComment({
    required this.id,
    required this.productId,
    required this.shopId,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.imageUrls,
    required this.createdAt,
    required this.updatedAt,
    this.authorPhotoUrl,
  });

  final String id;
  final String productId;
  final String shopId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String text;
  final List<String> imageUrls;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ProductComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ProductComment(
      id: doc.id,
      productId: (data['productId'] as String?) ?? '',
      shopId: (data['shopId'] as String?) ?? '',
      authorId: (data['authorId'] as String?) ?? '',
      authorName: (data['authorName'] as String?) ?? 'ลูกค้า',
      authorPhotoUrl: (data['authorPhotoUrl'] as String?)?.trim(),
      text: (data['text'] as String?) ?? '',
      imageUrls: ((data['imageUrls'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .where((url) => url.trim().isNotEmpty)
          .toList(growable: false),
      createdAt: _readTimestamp(data['createdAt']),
      updatedAt: _readTimestamp(data['updatedAt']),
    );
  }

  static DateTime? _readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }
}
