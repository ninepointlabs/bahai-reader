import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_state.dart';
import '../../core/userdata/userdata_store.dart';

const _files = MethodChannel('bahai_reader/files');
const _json = XTypeGroup(label: 'Notes backup', extensions: ['json'], mimeTypes: ['application/json']);

/// Settings → Back up or move your notes: export everything you made to one file, or merge such a file (from this
/// device or another) into this one. Nothing goes over the network; you carry the file yourself.
class NotesBackupSection extends StatelessWidget {
  const NotesBackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final ready = state.userData != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Back up or move your notes', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Export writes your highlights, notes, saved passages, collections, reading places, Said and Fasted records '
          'and everything in Study (not the PDFs) to one file. Import and merge reads such a file, from this device or '
          'another, and keeps whichever version of each was changed last; nothing is lost from either. The file goes '
          'only where you put it.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Export notes…'),
              onPressed: ready ? () => exportNotes(context, state) : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.merge_type, size: 18),
              label: const Text('Import and merge…'),
              onPressed: ready ? () => importNotes(context, state) : null,
            ),
          ],
        ),
      ],
    );
  }
}

String _day() => DateTime.now().toIso8601String().substring(0, 10);

Future<void> exportNotes(BuildContext context, AppState state) async {
  final say = ScaffoldMessenger.of(context);
  final bundle = state.exportNotes();
  if (bundle == null) return;
  final text = const JsonEncoder.withIndent(' ').convert(bundle);
  final name = 'Bahá’í Reader notes ${_day()}.json';
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final saved = await _files.invokeMethod<bool>('save', {'name': name, 'mime': 'application/json', 'text': text});
      if (saved == true) say.showSnackBar(SnackBar(content: Text('Exported “$name”.')));
      return;
    }
    final place = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [_json],
      confirmButtonText: 'Export',
    );
    if (place == null) return;
    var path = place.path;
    if (!path.toLowerCase().endsWith('.json')) path = '$path.json';
    final tmp = File('$path.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(path);
    say.showSnackBar(SnackBar(content: Text('Exported to $path')));
  } on PlatformException catch (e) {
    say.showSnackBar(SnackBar(content: Text('The notes could not be saved (${e.message ?? e.code}).')));
  } on FileSystemException catch (e) {
    say.showSnackBar(SnackBar(content: Text('The notes could not be saved (${e.osError?.message ?? e.message}).')));
  }
}

Future<void> importNotes(BuildContext context, AppState state) async {
  final say = ScaffoldMessenger.of(context);
  final XFile? file;
  try {
    file = await openFile(acceptedTypeGroups: const [_json], confirmButtonText: 'Merge');
  } on PlatformException catch (e) {
    say.showSnackBar(SnackBar(content: Text('The file dialog could not be opened (${e.message ?? e.code}).')));
    return;
  }
  if (file == null) return;
  final String message;
  try {
    final data = jsonDecode(await file.readAsString());
    if (data is! Map) throw UserDataProblem('this is not a Bahá’í Reader notes backup');
    final r = await state.mergeNotes(data.cast<String, Object?>());
    message = r.changed == 0
        ? 'Nothing new in “${file.name}”: this device already has everything in it.'
        : 'Merged “${file.name}”: ${r.added} added, ${r.updated} updated, ${r.deletedElsewhere} removed as they were '
              'there.${_booksHint(state)}';
  } on FormatException {
    say.showSnackBar(const SnackBar(content: Text('That file could not be read: it is not a notes backup.')));
    return;
  } on UserDataProblem catch (e) {
    say.showSnackBar(SnackBar(content: Text('That file was not merged: $e.')));
    return;
  }
  say.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 10), showCloseIcon: true));
}

/// Study books whose marks arrived but whose PDF is not on this device yet.
String _booksHint(AppState state) {
  final study = state.study;
  if (study == null) return '';
  final missing = [
    for (final b in study.library)
      if (!study.fileOf(b).existsSync()) b.name,
  ];
  if (missing.isEmpty) return '';
  return ' To see the marks in ${missing.length == 1 ? '“${missing.single}”' : '${missing.length} Study books'}, '
      'import your copy of the PDF here too.';
}
