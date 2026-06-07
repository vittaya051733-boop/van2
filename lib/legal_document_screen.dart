import 'package:flutter/material.dart';

import 'data/legal_content.dart';
import 'localization/settings_copy.dart';
import 'services/locale_service.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final english = LocaleService.instance.isEnglish;
    return Scaffold(
      appBar: AppBar(
        title: Text(document.title(english)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            '${SettingsCopy.lastUpdated}: ${document.updatedAtLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            document.body(english),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.55,
              color: const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}
