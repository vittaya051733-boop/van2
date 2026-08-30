import 'package:flutter/material.dart';

import 'data/legal_content.dart';
import 'l10n/l10n.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(document.title(L10n.en)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            L10n.lastUpdatedWithDate(document.updatedAtLabel),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            document.body(L10n.en),
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
