import 'package:flutter/material.dart';

import 'data/help_center_content.dart';
import 'l10n/l10n.dart';
import 'pricing_config_service.dart';
import 'services/locale_service.dart';

class HelpArticleDetailScreen extends StatelessWidget {
  const HelpArticleDetailScreen({super.key, required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PricingConfigService.instance,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: LocaleService.instance,
          builder: (context, _) {
            final english = LocaleService.instance.isEnglish;
            final body = HelpCenterContent.resolveBody(article, english);

            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                title: Text(
                  article.title(english),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  Text(
                    article.title(english),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (article.id == 'delivery_fee' ||
                      article.id == 'nationwide_shipping') ...<Widget>[
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.sync_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            L10n.helpRatesRealtimeSync,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.55,
                      color: const Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
