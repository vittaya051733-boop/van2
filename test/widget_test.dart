import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:van2/main.dart' show SplashScreen;

void main() {
  testWidgets('shows splash logo on startup', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(),
      ),
    );

    expect(find.text('ตลาดโนนสูง ออนไลน์ เดลิเวอรี่'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
