import 'package:flutter/material.dart';

import 'data/legal_content.dart';
import 'legal_document_screen.dart';
import 'l10n/l10n.dart';

class PrivacyOnboardingResult {
  const PrivacyOnboardingResult({
    required this.acceptedTerms,
    required this.pushOptIn,
    required this.marketingOptIn,
  });

  final bool acceptedTerms;
  final bool pushOptIn;
  final bool marketingOptIn;
}

class PrivacyOnboardingScreen extends StatefulWidget {
  const PrivacyOnboardingScreen({
    super.key,
    required this.app,
    this.canDismiss = false,
  });

  final String app;
  final bool canDismiss;

  @override
  State<PrivacyOnboardingScreen> createState() =>
      _PrivacyOnboardingScreenState();
}

class _PrivacyOnboardingScreenState extends State<PrivacyOnboardingScreen> {
  bool _acceptedTerms = false;
  bool _pushOptIn = false;
  bool _marketingOptIn = false;

  void _openDocument(LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
  }

  void _continue() {
    if (!_acceptedTerms) {
      return;
    }
    Navigator.of(context).pop(
      PrivacyOnboardingResult(
        acceptedTerms: true,
        pushOptIn: _pushOptIn,
        marketingOptIn: _marketingOptIn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(L10n.privacyOnboardingTitle),
        automaticallyImplyLeading: widget.canDismiss,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  Text(
                    L10n.privacyOnboardingIntro,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _LinkCard(
                    icon: Icons.policy_outlined,
                    title: L10n.privacyPolicy,
                    subtitle: L10n.lastUpdatedWithDate(
                      LegalContent.privacyPolicy.updatedAtLabel,
                    ),
                    onTap: () => _openDocument(LegalContent.privacyPolicy),
                  ),
                  const SizedBox(height: 10),
                  _LinkCard(
                    icon: Icons.description_outlined,
                    title: L10n.termsOfService,
                    subtitle: L10n.lastUpdatedWithDate(
                      LegalContent.termsOfService.updatedAtLabel,
                    ),
                    onTap: () => _openDocument(LegalContent.termsOfService),
                  ),
                  const SizedBox(height: 10),
                  _LinkCard(
                    icon: Icons.inventory_2_outlined,
                    title: L10n.dataWeCollect,
                    subtitle: L10n.lastUpdatedWithDate(
                      LegalContent.dataSummary.updatedAtLabel,
                    ),
                    onTap: () => _openDocument(LegalContent.dataSummary),
                  ),
                  const SizedBox(height: 20),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _acceptedTerms,
                    onChanged: (value) {
                      setState(() => _acceptedTerms = value == true);
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      L10n.privacyAcceptRequired,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pushOptIn,
                    onChanged: (value) => setState(() => _pushOptIn = value),
                    title: Text(L10n.privacyOrderNotificationsOptional),
                    subtitle: Text(L10n.privacyOrderNotificationsOptionalSubtitle),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _marketingOptIn,
                    onChanged: (value) =>
                        setState(() => _marketingOptIn = value),
                    title: Text(L10n.privacyPromotionsOptional),
                    subtitle: Text(L10n.privacyMarketingOptionalSubtitle),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _acceptedTerms ? _continue : null,
                  child: Text(L10n.continueAction),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFF57C00)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
