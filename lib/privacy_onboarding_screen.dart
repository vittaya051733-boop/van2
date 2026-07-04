import 'package:flutter/material.dart';

import 'data/legal_content.dart';
import 'legal_document_screen.dart';
import 'localization/settings_copy.dart';
import 'services/locale_service.dart';

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
    final english = LocaleService.instance.isEnglish;
    final title = english
        ? 'Privacy and terms'
        : 'ความเป็นส่วนตัวและข้อกำหนด';
    final intro = english
        ? 'Please review how VANTALAD uses your data before continuing.'
        : 'โปรดอ่านการใช้ข้อมูลส่วนบุคคลของ VANTALAD ก่อนใช้งานต่อ';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
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
                    intro,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _LinkCard(
                    icon: Icons.policy_outlined,
                    title: SettingsCopy.privacyPolicy,
                    subtitle:
                        '${SettingsCopy.lastUpdated}: ${LegalContent.privacyPolicy.updatedAtLabel}',
                    onTap: () => _openDocument(LegalContent.privacyPolicy),
                  ),
                  const SizedBox(height: 10),
                  _LinkCard(
                    icon: Icons.description_outlined,
                    title: SettingsCopy.termsOfService,
                    subtitle:
                        '${SettingsCopy.lastUpdated}: ${LegalContent.termsOfService.updatedAtLabel}',
                    onTap: () => _openDocument(LegalContent.termsOfService),
                  ),
                  const SizedBox(height: 10),
                  _LinkCard(
                    icon: Icons.inventory_2_outlined,
                    title: SettingsCopy.dataWeCollect,
                    subtitle:
                        '${SettingsCopy.lastUpdated}: ${LegalContent.dataSummary.updatedAtLabel}',
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
                    title: Text.rich(
                      TextSpan(
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(
                            text: english
                                ? 'I accept the Terms of Service and Privacy Policy (required)'
                                : 'ยอมรับข้อกำหนดการใช้งานและนโยบายความเป็นส่วนตัว (จำเป็น)',
                          ),
                        ],
                      ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pushOptIn,
                    onChanged: (value) => setState(() => _pushOptIn = value),
                    title: Text(
                      english
                          ? 'Order status notifications'
                          : 'รับการแจ้งเตือนสถานะออเดอร์',
                    ),
                    subtitle: Text(
                      english
                          ? 'Optional — you can change this later in Settings'
                          : 'ไม่บังคับ — เปลี่ยนได้ภายหลังในตั้งค่า',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _marketingOptIn,
                    onChanged: (value) =>
                        setState(() => _marketingOptIn = value),
                    title: Text(
                      english
                          ? 'Promotions and special offers'
                          : 'รับข่าวโปรโมชันและสิทธิพิเศษ',
                    ),
                    subtitle: Text(
                      english
                          ? 'Optional marketing messages'
                          : 'ข้อความการตลาด (ไม่บังคับ)',
                    ),
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
                  child: Text(english ? 'Continue' : 'ดำเนินการต่อ'),
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
