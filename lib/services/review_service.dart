import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../utils/upload_image_compressor.dart';

class ReviewService {
  ReviewService._();

  static const int maxImagesPerReview = 4;

  static Future<List<String>> uploadReviewImages({
    required String customerId,
    required String reviewId,
    required List<File> files,
  }) async {
    if (files.isEmpty) {
      return <String>[];
    }

    final storage = FirebaseStorage.instance;
    final urls = <String>[];
    for (final source in files) {
      final compressed = await UploadImageCompressor.compressForUpload(source);
      final storagePath =
          'review_uploads/$customerId/$reviewId/${DateTime.now().millisecondsSinceEpoch}_${compressed.fileName}';
      final ref = storage.ref().child(storagePath);
      await ref.putFile(
        compressed.file,
        SettableMetadata(contentType: compressed.contentType),
      );
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }
}
