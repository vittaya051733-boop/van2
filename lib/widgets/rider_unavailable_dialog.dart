import 'package:flutter/material.dart';
import 'dart:async';

import '../order_roadmap_screen.dart';
import '../services/observability_service.dart';

/// Explains rider-matching gaps after checkout instead of a transient snackbar.
Future<void> showRiderUnavailableDialog(
  BuildContext context, {
  required List<String> shopNames,
  required List<String> orderIds,
  bool isTravelOrder = false,
}) async {
  final shops = shopNames
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
  final orders = orderIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);

  unawaited(
    ObservabilityService.instance.logEvent(
      'rider_unavailable_dialog',
      parameters: <String, Object?>{
        'shop_count': shops.length,
        'order_count': orders.length,
        'is_travel': isTravelOrder,
      },
    ),
  );

  if (!context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('ยังไม่พบไรเดอร์ในขณะนี้'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                isTravelOrder
                    ? 'ระบบสร้างคำขอเดินทางแล้ว แต่ยังไม่มีไรเดอร์รับผู้โดยสารออนไลน์ใกล้จุดรับ'
                    : 'ออเดอร์ของคุณถูกสร้างแล้ว แต่บางร้านยังหาไรเดอร์ไม่ได้ทันที',
              ),
              if (shops.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                const Text(
                  'ร้านที่ยังหาไรเดอร์ไม่ได้:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...shops.map(
                  (shop) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $shop'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'ระบบจะแจ้งเตือนเมื่อมีไรเดอร์รับงาน หรือคุณสามารถติดตามสถานะได้จากหน้าออเดอร์',
                style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ปิด'),
          ),
          if (orders.isNotEmpty)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => OrderRoadmapScreen(orderIds: orders),
                  ),
                );
              },
              child: const Text('ดูสถานะออเดอร์'),
            ),
        ],
      );
    },
  );
}
