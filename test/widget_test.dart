import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:van2/main.dart';

void main() {
  testWidgets('shows splash logo on startup', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('แว๊นตลาด'), findsOneWidget);
    expect(find.text('Delivery starts here'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
