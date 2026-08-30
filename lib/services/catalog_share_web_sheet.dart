import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'catalog_share_web_sheet_stub.dart'
    if (dart.library.html) 'catalog_share_web_sheet_web.dart'
    as catalog_share_actions;

/// Product share preview + actions (web, Android, iOS).
Future<void> showProductShareSheet({
  required BuildContext context,
  required Uint8List imageBytes,
  required String message,
  required String title,
  String mimeType = 'image/png',
  String fileName = 'vantalad-product.png',
}) async {
  if (!context.mounted) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'แชร์สินค้า',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.fitWidth,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ภาพนี้รวมรูปและรายละเอียดแล้ว พร้อมแนบลิงก์คลิกได้ใต้ภาพ',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final shared = await catalog_share_actions.tryWebNativeShare(
                    imageBytes: imageBytes,
                    message: message,
                    title: title,
                    mimeType: mimeType,
                    fileName: fileName,
                  );
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          shared
                              ? 'เปิดเมนูแชร์ภาพพร้อมรายละเอียดแล้ว'
                              : 'แชร์อัตโนมัติไม่ได้ — ลองบันทึกรูปแล้วแนบเอง',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('แชร์ภาพพร้อมรายละเอียด'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  await catalog_share_actions.downloadWebShareImage(
                    imageBytes,
                    mimeType: mimeType,
                    fileName: fileName,
                  );
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text('บันทึกภาพแชร์แล้ว'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.download_outlined),
                label: const Text('บันทึกภาพแชร์'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

@Deprecated('Use showProductShareSheet')
Future<void> showWebProductShareSheet({
  required BuildContext context,
  required Uint8List imageBytes,
  required String message,
  required String title,
  String mimeType = 'image/jpeg',
  String fileName = 'vantalad-product.jpg',
}) =>
    showProductShareSheet(
      context: context,
      imageBytes: imageBytes,
      message: message,
      title: title,
      mimeType: mimeType,
      fileName: fileName,
    );
