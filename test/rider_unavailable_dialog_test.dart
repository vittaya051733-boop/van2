import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:van2/widgets/rider_unavailable_dialog.dart';

void main() {
  testWidgets('rider unavailable dialog shows shop names and action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showRiderUnavailableDialog(
                    context,
                    shopNames: const <String>['ร้านทดสอบ'],
                    orderIds: const <String>['order-1'],
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่พบไรเดอร์ในขณะนี้'), findsOneWidget);
    expect(find.text('• ร้านทดสอบ'), findsOneWidget);
    expect(find.text('ดูสถานะออเดอร์'), findsOneWidget);
  });
}
