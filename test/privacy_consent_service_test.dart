import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:van2/data/legal_content.dart';
import 'package:van2/privacy_onboarding_screen.dart';
import 'package:van2/services/privacy_consent_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('needs consent when local policy version is missing', () async {
    final needs = await PrivacyConsentService.instance.needsConsentFlow(
      app: PrivacyAppKey.van2Customer,
      user: null,
    );
    expect(needs, isTrue);
  });

  test('local consent round-trip stores current policy version', () async {
    await PrivacyConsentService.instance.saveLocalConsent(
      pushOptIn: true,
      marketingOptIn: false,
    );

    final snapshot = await PrivacyConsentService.instance.loadLocalSnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.policyVersion, kPrivacyPolicyVersion);
    expect(snapshot.pushOptIn, isTrue);
    expect(snapshot.marketingOptIn, isFalse);
    expect(
      await PrivacyConsentService.instance.hasLocalConsentForCurrentPolicy(),
      isTrue,
    );
  });

  test('does not need consent again after local acceptance', () async {
    await PrivacyConsentService.instance.saveLocalConsent(
      pushOptIn: false,
      marketingOptIn: false,
    );

    final needs = await PrivacyConsentService.instance.needsConsentFlow(
      app: PrivacyAppKey.van2Customer,
      user: null,
    );
    expect(needs, isFalse);
  });

  testWidgets('onboarding requires terms before continue', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PrivacyOnboardingScreen(app: PrivacyAppKey.van2Customer),
      ),
    );

    expect(find.text('ดำเนินการต่อ'), findsOneWidget);
    final continueButton = find.widgetWithText(FilledButton, 'ดำเนินการต่อ');
    final button = tester.widget<FilledButton>(continueButton);
    expect(button.onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    final enabledButton = tester.widget<FilledButton>(continueButton);
    expect(enabledButton.onPressed, isNotNull);
  });

  test('legal documents use the current policy date label', () {
    expect(LegalContent.privacyPolicy.updatedAtLabel, '1 มิ.ย. 2026');
    expect(LegalContent.termsOfService.updatedAtLabel, '1 มิ.ย. 2026');
  });
}
