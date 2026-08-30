// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:flutter/services.dart';

Future<bool> tryWebNativeShareText({
  required String message,

  required String title,
}) async {
  try {
    await html.window.navigator.share(<String, Object>{
      'title': title,

      'text': message,
    });

    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> tryWebNativeShare({
  required Uint8List imageBytes,

  required String message,

  required String title,

  String mimeType = 'image/jpeg',

  String fileName = 'vantalad-product.jpg',
}) async {
  try {
    final blob = html.Blob(<Uint8List>[imageBytes], mimeType);

    final file = html.File(
      <html.Blob>[blob],

      fileName,

      <String, String>{'type': mimeType},
    );

    final payload = <String, Object>{
      'title': title,

      'files': <html.File>[file],
    };

    if (message.trim().isNotEmpty) {
      payload['text'] = message;
    }

    await html.window.navigator.share(payload);

    return true;
  } catch (_) {
    return false;
  }
}

bool webCanNativeShareFiles() {
  final ua = html.window.navigator.userAgent.toLowerCase();

  return ua.contains('android') ||
      ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('mobile');
}

Future<void> downloadWebShareImage(
  Uint8List imageBytes, {

  String mimeType = 'image/jpeg',

  String fileName = 'vantalad-product.jpg',
}) async {
  final blob = html.Blob(<Uint8List>[imageBytes], mimeType);

  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';

  html.document.body?.append(anchor);

  anchor.click();

  anchor.remove();

  html.Url.revokeObjectUrl(url);
}

Future<void> copyWebShareText(String message) async {
  await Clipboard.setData(ClipboardData(text: message));
}
