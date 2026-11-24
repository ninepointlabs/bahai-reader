import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/settings/android_backup.dart';
import '../../core/settings/settings_store.dart';
import 'languages_dialog.dart';
import 'folder_sync_section.dart';
import 'notes_backup.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final gtk = gtkSettingsFile();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          Slider(min: 15, max: 36, divisions: 21, value: state.settings.textSize, onChanged: state.setTextSize),
          const Divider(height: 32),
          Text('Language', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Reading ${state.language.label}.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.translate),
              label: const Text('Languages & offline libraries…'),
              onPressed: () => showLanguages(context),
            ),
          ),
          const Divider(height: 32),
          Text('Your highlights, notes and saved passages', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(
            'Stored on this device in ${state.store.file.parent.path} (userdata.sqlite and settings.json).',
            style: theme.textTheme.bodySmall,
          ),
          if (Platform.isAndroid) _AndroidBackupSwitch(files: state.store.file.parent),
          const SizedBox(height: 16),
          const NotesBackupSection(),
          const SizedBox(height: 16),
          const FolderSyncSection(),
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
                          messenger.showSnackBar(
                            SnackBar(content: Text(result.message ?? 'There is no GTK settings file.')),
                          );
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(content: Text('Could not import: $e')));
                        }
                      }
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Android: whether notes and settings may go into Android's own backup (the person's Google account). Books imported
/// into Study never do.
class _AndroidBackupSwitch extends StatefulWidget {
  const _AndroidBackupSwitch({required this.files});

  /// The folder the settings are in now (`files/` or `files/nobackup/`).
  final Directory files;

  @override
  State<_AndroidBackupSwitch> createState() => _AndroidBackupSwitchState();
}

class _AndroidBackupSwitchState extends State<_AndroidBackupSwitch> {
  Directory get files =>
      widget.files.uri.pathSegments.where((s) => s.isNotEmpty).last == noBackupFolder ? widget.files.parent : widget.files;
  late bool include = notesInBackup(files);

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Include notes in Android backup'),
    subtitle: const Text(
      'Android may copy your highlights, notes, answers and settings to your Google account’s backup, so a new phone '
      'gets them back. Books you import are never included. A change takes effect the next time the app starts.',
    ),
    value: include,
    onChanged: (v) async {
      await chooseNotesInBackup(files, v);
      if (mounted) setState(() => include = v);
    },
  );
}
