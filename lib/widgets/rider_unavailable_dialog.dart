import 'package:flutter/material.dart';
import 'dart:async';

import '../l10n/l10n.dart';
import '../order_roadmap_screen.dart';
import '../services/locale_service.dart';
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
      return ListenableBuilder(
        listenable: LocaleService.instance,
        builder: (context, _) {
          return AlertDialog(
            title: Text(L10n.noRiderDialogTitle),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    isTravelOrder
                        ? L10n.noRiderTravelBody
                        : L10n.noRiderDeliveryBody,
                  ),
                  if (shops.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      L10n.shopsWithoutRider,
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                  Text(
                    L10n.noRiderNotifyHint,
                    style: const TextStyle(color: Color(0xFF6B7280), height: 1.4),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(L10n.close),
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
                  child: Text(L10n.viewOrderStatus),
                ),
            ],
          );
        },
      );
    },
  );
}
