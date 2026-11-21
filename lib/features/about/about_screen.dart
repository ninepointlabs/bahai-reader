import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/about.dart';
import '../../core/app/app_state.dart';
import '../../core/library/citations.dart';

/// About Bahá’í Reader, as the GTK app's About window: what it is, who made it, the license, where the texts come from
/// and on what terms, support, privacy and what it is built with. Nothing is fetched.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  static const site = 'https://bahaireader.org';

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

/// Version details to paste into a support email (GTK `details()`).
String versionDetails() =>
    '$appName $appVersion\nFlutter, Dart ${Platform.version.split(' ').first}\n'
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, ${Platform.environment['XDG_CURRENT_DESKTOP'] ?? 'unknown desktop'}';

/// What is kept where, and the only times the network is used (GTK `privacy()`).
String privacy(AppState state) {
  final home = Platform.environment['HOME'] ?? '';
  String short(String p) => home.isNotEmpty && p.startsWith(home) ? '~${p.substring(home.length)}' : p;
  final own = state.repository.folders.own?.path;
  return 'No accounts, no telemetry, no analytics. English is bundled, so starting, reading, searching and switching to a '
      'downloaded language never use the network. The app connects only when you choose Download & use, Update '
      'downloaded content or Check available languages: it then asks bahaiprayers.net over HTTPS for that language’s '
      'texts or the language list. The request carries only the collection and the language number; like any web '
      'request, the site sees your IP address.${own == null ? '' : ' Downloads are saved in ${short(own)}.'} Settings, '
      'highlights, notes and saved passages stay in ${short(state.store.file.parent.path)} and are never sent anywhere. '
      'Books imported into Study are copied to ${short(state.studyBooksFolder().path)}, read only on this device and never '
      'uploaded or shared. A location you enter (or, on a '
      'phone, ask it to find) is only used on this device to work out the sun’s times, and is never sent anywhere. '
      'Reminders are worked out and sent on this device, and your “Said today” and “Fasted today” records stay here too; '
      'you can turn them off or clear them in Location & reminders.';
}

class _AboutScreenState extends State<AboutScreen> {
  bool license = false;

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('Copied $what'), duration: const Duration(seconds: 2)));
  }

  Future<void> _email() async {
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query:
          'subject=${Uri.encodeComponent('$appName $appVersion')}&body=${Uri.encodeComponent('\n\n--\n${versionDetails()}')}',
    );
    // The desktop's mail app; nothing is sent until you send it there.
    if (Platform.isLinux) {
      try {
        await Process.start('xdg-open', [uri.toString()], mode: ProcessStartMode.detached);
        return;
      } on ProcessException {
        // fall through
      }
    }
    _copy(supportEmail, 'the address');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7));
    Widget row(String name, Widget value) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(name, style: dim)),
          const SizedBox(width: 12),
          Expanded(child: value),
        ],
      ),
    );
    Widget text(String t) => SelectableText(t);
    return Scaffold(
      appBar: AppBar(title: const Text('About Bahá’í Reader')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appName, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  const Text(tagline),
                  Text('Version $appVersion', style: dim),
                  const SizedBox(height: 20),
                  row('Made by', text(organization)),
                  row('Created', text(created)),
                  row(
                    'License',
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('$licenseName, $copyright'),
                        TextButton(
                          onPressed: () => setState(() => license = !license),
                          child: Text(license ? 'Hide' : 'Read it'),
                        ),
                      ],
                    ),
                  ),
                  row(
                    'Texts',
                    text(
                      'From BahaiPrayers.net, which permits their use in apps (https://bahaiprayers.net/Developer). The texts '
                      'and translations are not covered by the MIT license, and no ownership is claimed (DATA-NOTICE.md). Not an '
                      'official publication of a Bahá’í institution.',
                    ),
                  ),
                  row(
                    'bahai.org',
                    text(
                      'In English, the official text from the Bahá’í Reference Library, bahai.org, wherever it has the passage: '
                      'the books and most prayers, messages of the Universal House of Justice and works of Shoghi Effendi. '
                      '$bahaiOrgNotice. Used under the terms at https://www.bahai.org/legal; not covered by the MIT license '
                      '(DATA-NOTICE.md). No permission beyond those published terms has been sought or obtained. This app is '
                      'free and is not sold.',
                    ),
                  ),
                  row(
                    'Places',
                    text(
                      'City data © GeoNames (geonames.org), trimmed, under the Creative Commons Attribution 4.0 license '
                      '(creativecommons.org/licenses/by/4.0).',
                    ),
                  ),
                  row(
                    'Calendar',
                    text(
                      'Badí‘ dates from the Bahá’í World Centre and the Universal House of Justice. Sun times use the '
                      'public-domain NOAA solar calculation.',
                    ),
                  ),
                  row(
                    'Support',
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const SelectableText(supportEmail),
                        TextButton(onPressed: _email, child: const Text('Email')),
                        TextButton(onPressed: () => _copy(supportEmail, 'the address'), child: const Text('Copy')),
                      ],
                    ),
                  ),
                  row(
                    'Study',
                    text(
                      'Opens PDFs you import yourself, such as your own copies of Ruhi Institute books. The app includes '
                      'no Ruhi Institute material and is not affiliated with or endorsed by the Ruhi Institute.',
                    ),
                  ),
                  row('Privacy', text(privacy(state))),
                  row('Built with', text('Flutter, Dart ${Platform.version.split(' ').first}')),
                  row(
                    'Open source',
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('PDFium, SQLite and the Dart packages the app is built from'),
                        TextButton(
                          onPressed: () => showLicensePage(
                            context: context,
                            applicationName: appName,
                            applicationVersion: appVersion,
                          ),
                          child: const Text('Their licenses'),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => _copy(versionDetails(), 'version details'),
                      child: const Text('Copy version details'),
                    ),
                  ),
                  if (license) ...[
                    const SizedBox(height: 16),
                    FutureBuilder<List<String>>(
                      future: Future.wait([rootBundle.loadString('LICENSE'), rootBundle.loadString('DATA-NOTICE.md')]),
                      builder: (context, snap) => snap.hasData
                          ? SelectableText(snap.data!.join('\n\n'), style: theme.textTheme.bodySmall)
                          : const LinearProgressIndicator(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
