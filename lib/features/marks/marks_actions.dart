import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_state.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../../core/marks/highlight.dart';
import '../../core/marks/marks_export.dart';

const _files = MethodChannel('bahai_reader/files');

/// Writes [records] (highlights of the writings and prayers, with their notes) to a Markdown file the person chooses.
Future<void> exportHighlights(BuildContext context, AppState state, List<Highlight> records) async {
  final say = ScaffoldMessenger.of(context);
  final items = <HighlightPlace>[
    for (final r in records)
      if (state.passageOf(r.id) case final p)
        (
          highlight: r,
          passage: p,
          group: p == null ? 'Not in this language’s library' : (bookOf(p) ?? 'Prayers'),
          place: p == null ? r.id : placeOf(p),
        ),
  ];
  final markdown = renderHighlightsMarkdown(items);
  const name = 'Bahá’í Reader highlights.md';
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final saved = await _files.invokeMethod<bool>('save', {'name': name, 'mime': 'text/markdown', 'text': markdown});
      if (saved == true) say.showSnackBar(const SnackBar(content: Text('Exported “$name”.')));
      return;
    }
    final place = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Markdown', extensions: ['md']),
      ],
      confirmButtonText: 'Export',
    );
    if (place == null) return;
    var path = place.path;
    if (!path.toLowerCase().endsWith('.md')) path = '$path.md';
    final tmp = File('$path.tmp');
    await tmp.writeAsString(markdown, flush: true);
    await tmp.rename(path);
    say.showSnackBar(SnackBar(content: Text('Exported to $path')));
  } on PlatformException catch (e) {
    say.showSnackBar(SnackBar(content: Text('The export could not be saved (${e.message ?? e.code}).')));
  } on FileSystemException catch (e) {
    say.showSnackBar(SnackBar(content: Text('The export could not be saved (${e.osError?.message ?? e.message}).')));
  }
}
