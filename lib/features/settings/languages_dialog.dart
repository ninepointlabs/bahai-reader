import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/library/packs.dart';

/// Languages & offline libraries, as the GTK app's window: every language BahaiPrayers.net offers, the ones on this
/// computer first; what each offers; "Use this language" or "Download & use"; "Update downloaded content"; "Check
/// available languages". The network is used only by those buttons.
class LanguagesDialog extends StatefulWidget {
  const LanguagesDialog({super.key});

  @override
  State<LanguagesDialog> createState() => _LanguagesDialogState();
}

/// Downloading needs the network, which the phone builds do not ask for.
bool get canDownload => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

class _LanguagesDialogState extends State<LanguagesDialog> {
  Map<String, List<Map<String, dynamic>>>? catalog;
  late int selected = AppScope.read(context).settings.language;
  String progress = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await AppScope.read(context).catalog();
    if (mounted) setState(() => catalog = c);
  }

  List<Map<String, dynamic>> _rows(AppState state) {
    final rows = [...?catalog?['prayers']];
    String english(Map r) => '${r['English'] ?? r['Name']}'.toLowerCase();
    rows.sort((a, b) {
      final x = (!state.offline(a['Id'] as int), a['Id'] != 1, english(a));
      final y = (!state.offline(b['Id'] as int), b['Id'] != 1, english(b));
      if (x.$1 != y.$1) return x.$1 ? 1 : -1;
      if (x.$2 != y.$2) return x.$2 ? 1 : -1;
      return x.$3.compareTo(y.$3);
    });
    return rows;
  }

  /// The language's own name and its English name (the catalog's trailing full stop dropped, as elsewhere).
  String _name(Map r) {
    final name = '${r['Name']}'.replaceAll(RegExp(r'\.$'), ''), english = '${r['English'] ?? name}';
    return name == english ? name : '$name — $english';
  }

  Future<void> _use(AppState state, {required bool force}) async {
    final id = selected;
    if (!force && state.offline(id)) {
      await state.setLanguage(id);
      setState(() => progress = 'Ready to read offline.');
      return;
    }
    setState(() => progress = 'Starting download…');
    try {
      await state.download(id, progress: (m) => mounted ? setState(() => progress = m) : null);
      await state.setLanguage(id);
      if (mounted) setState(() => progress = 'Downloaded and ready to read offline.');
    } on DownloadProblem catch (e) {
      if (mounted) setState(() => progress = 'Download failed. Existing offline content is unchanged.\n${e.message}');
    }
  }

  Future<void> _check(AppState state) async {
    setState(() => progress = 'Checking available languages…');
    try {
      await state.checkLanguages();
      await _load();
      if (mounted) setState(() => progress = 'Language list updated.');
    } on DownloadProblem catch (e) {
      if (mounted) {
        setState(
          () => progress = 'Could not update the language list. The saved list is still available.\n${e.message}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final c = catalog;
    final busy = state.downloading;
    if (c == null) return const Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator());
    final rows = _rows(state);
    final available = state.offline(selected);
    final offered = [
      for (final key in feeds.keys)
        if ((c[key] ?? const []).any((r) => r['Id'] == selected)) sectionNames[key]!,
    ];
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) setState(() => progress = 'Please wait for the download to finish.');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Languages & offline libraries')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              canDownload
                  ? 'English is included. Download another language once to read it offline. Your choice is remembered.'
                  : 'English is included, with the languages on this device. Your choice is remembered.',
            ),
            const SizedBox(height: 14),
            DropdownMenu<int>(
              key: ValueKey('languages-${rows.length}-${state.languages.length}'),
              initialSelection: selected,
              enabled: !busy,
              enableFilter: true,
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Language'),
              menuHeight: 360,
              onSelected: (id) => id == null ? null : setState(() => selected = id),
              dropdownMenuEntries: [
                // The field shows the name; the list also says which are on this device.
                for (final r in rows)
                  DropdownMenuEntry(
                    value: r['Id'] as int,
                    label: _name(r),
                    labelWidget: Text(state.offline(r['Id'] as int) ? '${_name(r)} · Offline' : _name(r)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FutureBuilder(
              // A pack downloaded before a collection was offered: say what an update would add (GTK does the same).
              future: available && selected != 1 ? state.repository.pack(selected) : Future.value(null),
              builder: (context, snap) {
                final stored = snap.data?.$1;
                final missing = stored == null
                    ? const <String>[]
                    : [
                        for (final key in feeds.keys)
                          if (!stored.containsKey(key) && (c[key] ?? const []).any((r) => r['Id'] == selected))
                            sectionNames[key]!,
                      ];
                final status =
                    '${available ? 'Available offline' : 'Download needed'}'
                    '${missing.isEmpty ? '' : ' — update to add: ${missing.join(', ')}'}';
                return Text('$status\n\nContent offered in this language:\n${offered.join('\n')}');
              },
            ),
            const SizedBox(height: 14),
            if (progress.isNotEmpty) ...[Text(progress, style: theme.textTheme.bodyMedium), const SizedBox(height: 14)],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: busy || (!available && !canDownload) || selected == state.settings.language && available
                      ? null
                      : () => _use(state, force: false),
                  child: Text(available ? 'Use this language' : 'Download & use'),
                ),
                if (canDownload) ...[
                  OutlinedButton(
                    onPressed: busy || !available || selected == 1 ? null : () => _use(state, force: true),
                    child: const Text('Update downloaded content'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => _check(state),
                    child: const Text('Check available languages'),
                  ),
                ],
              ],
            ),
            if (!canDownload) ...[
              const SizedBox(height: 14),
              Text(
                'Downloading languages is not available in this build; it has no network access.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (selected == 1) ...[
              const SizedBox(height: 14),
              Text(
                'English is bundled with the app, with bahai.org’s official texts, and is updated with the app.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens Languages & offline libraries as a dialog over the window.
Future<void> showLanguages(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
      child: const LanguagesDialog(),
    ),
  ),
);
