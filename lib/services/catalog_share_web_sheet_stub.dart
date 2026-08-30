import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/gallery_image_saver.dart';

Future<bool> tryWebNativeShare({
  required Uint8List imageBytes,
  required String message,
  required String title,
  String mimeType = 'image/jpeg',
  String fileName = 'vantalad-product.jpg',
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final extension = fileName.contains('.')
        ? fileName.split('.').last
        : (mimeType.contains('png') ? 'png' : 'jpg');
    final path =
        '${tempDir.path}/share_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await File(path).writeAsBytes(imageBytes, flush: true);

    final trimmedMessage = message.trim();
    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(path, mimeType: mimeType, name: fileName),
        ],
        fileNameOverrides: <String>[fileName],
        text: trimmedMessage.isEmpty ? null : trimmedMessage,
        subject: title,
      ),
    );
    return result.status == ShareResultStatus.success;
  } catch (_) {
    return false;
  }
}

Future<bool> tryWebNativeShareText({
  required String message,
  required String title,
}) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: title,
      ),
    );
    return result.status == ShareResultStatus.success;
  } catch (_) {
    return false;
  }
}

Future<void> downloadWebShareImage(
  Uint8List imageBytes, {
  String mimeType = 'image/jpeg',
  String fileName = 'vantalad-product.jpg',
}) async {
  if (!await GalleryImageSaver.ensurePermission()) {
    return;
  }
  final baseName = fileName.contains('.')
      ? fileName.substring(0, fileName.lastIndexOf('.'))
      : fileName;
  await GalleryImageSaver.savePngBytes(
    imageBytes,
    name: baseName,
  );
}

Future<void> copyWebShareText(String message) async {
  // Clipboard handled by callers on mobile when needed.
}

bool webCanNativeShareFiles() => false;
