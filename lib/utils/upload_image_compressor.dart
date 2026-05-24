import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// บีบอัดรูปก่อนอัปโหลดแชท — ลดขนาดและความคมชัด
class CompressedUploadImage {
  const CompressedUploadImage({
    required this.file,
    required this.fileName,
    required this.contentType,
  });

  final File file;
  final String fileName;
  final String contentType;
}

class UploadImageCompressor {
  UploadImageCompressor._();

  static const int maxDimension = 1280;
  static const int quality = 68;

  static Future<CompressedUploadImage> compressForUpload(File sourceFile) async {
    final baseName = _basenameWithoutExtension(sourceFile.path);
    final sanitizedBase = baseName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final targetPath =
        '${Directory.systemTemp.path}/upload_${DateTime.now().microsecondsSinceEpoch}_$sanitizedBase.jpg';

    try {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        sourceFile.path,
        targetPath,
        format: CompressFormat.jpeg,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        keepExif: false,
      );
      if (compressed != null) {
        final output = File(compressed.path);
        if (await output.exists() && await output.length() > 0) {
          return CompressedUploadImage(
            file: output,
            fileName: '$sanitizedBase.jpg',
            contentType: 'image/jpeg',
          );
        }
      }
    } catch (error, stack) {
      debugPrint('UploadImageCompressor file failed: $error');
      debugPrint('$stack');
    }

    try {
      final sourceBytes = await sourceFile.readAsBytes();
      final compressedBytes = await FlutterImageCompress.compressWithList(
        sourceBytes,
        format: CompressFormat.jpeg,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        keepExif: false,
      );
      if (compressedBytes.isNotEmpty) {
        final output = File(targetPath);
        await output.writeAsBytes(compressedBytes, flush: true);
        return CompressedUploadImage(
          file: output,
          fileName: '$sanitizedBase.jpg',
          contentType: 'image/jpeg',
        );
      }
    } catch (error, stack) {
      debugPrint('UploadImageCompressor bytes failed: $error');
      debugPrint('$stack');
    }

    return CompressedUploadImage(
      file: sourceFile,
      fileName: _basename(sourceFile.path),
      contentType: _guessMimeType(sourceFile.path),
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  static String _basenameWithoutExtension(String path) {
    final base = _basename(path);
    final dot = base.lastIndexOf('.');
    if (dot <= 0) {
      return base;
    }
    return base.substring(0, dot);
  }

  static String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
