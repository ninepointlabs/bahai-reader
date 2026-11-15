import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/library/citations.dart';

/// What this is, where the texts come from, and on what terms. Links are shown as text; the app opens nothing.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const realApp = 'https://github.com/ninepointlabs/bahai-reader';
  static const site = 'https://bahaireader.org';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            SelectableText(body),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('About & attribution')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bahá’í Reader — Flutter experiment', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              const SelectableText(
                'An experimental Flutter port, made to see how it turns out. It is not a replacement for Bahá’í Reader. '
                'The real app: $realApp · $site',
              ),
              const SizedBox(height: 24),
              section('Texts',
                  'From BahaiPrayers.net, which permits their use in apps (https://bahaiprayers.net/Developer). Snapshots '
                  'downloaded 13 September 2026. The texts and translations are not covered by the MIT license, and no '
                  'ownership is claimed. Not an official publication of a Bahá’í institution.'),
              section('bahai.org',
                  'In English, the official text from the Bahá’í Reference Library, bahai.org, wherever it has the passage: '
                  'the books and most prayers, messages of the Universal House of Justice and works of Shoghi Effendi. '
                  '$bahaiOrgNotice. Each passage names its author. Used under the terms at https://www.bahai.org/legal '
                  '(last updated 5 September 2022); not covered by the MIT license. No permission beyond those published '
                  'terms has been sought or obtained. This app is free and is not sold.'),
              section('Privacy',
                  'Everything stays on this device. No analytics, no telemetry, and no network connections. '
                  'Highlights, notes and saved passages are kept in this app’s own settings file.'),
              Text('Full notices', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              FutureBuilder<List<String>>(
                future: Future.wait([rootBundle.loadString('DATA-NOTICE.md'), rootBundle.loadString('LICENSE')]),
                builder: (context, snap) => snap.hasData
                    ? SelectableText(snap.data!.join('\n\n'), style: theme.textTheme.bodySmall)
                    : const LinearProgressIndicator(),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
