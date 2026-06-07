import 'package:flutter/material.dart';

import 'data/help_center_content.dart';
import 'services/locale_service.dart';

class HelpArticleDetailScreen extends StatelessWidget {
  const HelpArticleDetailScreen({super.key, required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    final english = LocaleService.instance.isEnglish;
    return Scaffold(
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
          const SizedBox(height: 12),
          Text(
            article.body(english),
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
