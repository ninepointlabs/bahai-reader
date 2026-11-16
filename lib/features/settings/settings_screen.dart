import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/settings/settings_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final gtk = gtkSettingsFile();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Appearance', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto)),
            ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
            ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
          ],
          selected: {state.settings.theme},
          onSelectionChanged: (s) => state.setTheme(s.first),
        ),
        const SizedBox(height: 16),
        Text('Text size: ${state.settings.textSize.round()}'),
        Slider(
          min: 15,
          max: 36,
          divisions: 21,
          value: state.settings.textSize,
          onChanged: state.setTextSize,
        ),
        const Divider(height: 32),
        Text('Language', style: theme.textTheme.titleMedium),
        Text('Libraries bundled with this build. Downloading more languages is not part of this experiment.',
            style: theme.textTheme.bodySmall),
        RadioGroup<int>(
          groupValue: state.settings.language,
          onChanged: (v) => v == null ? null : state.setLanguage(v),
          child: Column(children: [
            for (final l in state.languages) RadioListTile<int>(value: l.id, title: Text(l.label)),
          ]),
        ),
        const Divider(height: 32),
        Text('Your highlights and saved passages', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        SelectableText('Stored in ${state.store.file.path}', style: theme.textTheme.bodySmall),
        if (Platform.isLinux) ...[
          const SizedBox(height: 12),
          Text(
            'Highlights, notes, saved passages, collections and settings were copied from the GTK Bahá’í Reader '
            '(${gtk.path}) when this app first started. Importing again adds what is new there and fills settings not '
            'set here; nothing set here is replaced. That file is only read; it is never changed.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(state.settings.gtkImport != null ? 'Import from GTK app again' : 'Import from GTK app'),
              onPressed: gtk.existsSync()
                  ? () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final result = await state.importGtkAgain();
                        messenger.showSnackBar(SnackBar(content: Text(result.message ?? 'There is no GTK settings file.')));
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text('Could not import: $e')));
                      }
                    }
                  : null,
            ),
          ),
        ],
      ]),
    );
  }
}
