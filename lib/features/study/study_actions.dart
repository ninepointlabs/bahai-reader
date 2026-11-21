import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/study/export.dart';
import '../../core/study/importer.dart';
import '../../core/study/study_controller.dart';

const _pdf = XTypeGroup(
  label: 'PDF',
  extensions: ['pdf'],
  mimeTypes: ['application/pdf'],
  uniformTypeIdentifiers: ['com.adobe.pdf'],
);

void _say(ScaffoldMessengerState say, String text) =>
    say.showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));

/// Picks a PDF, copies it into the app and opens it. The original is only read; nothing is uploaded.
Future<void> importStudyPdf(BuildContext context, StudyController study, {VoidCallback? opened}) async {
  final say = ScaffoldMessenger.of(context);
  final XFile? file;
  try {
    file = await openFile(acceptedTypeGroups: const [_pdf], confirmButtonText: 'Import');
  } on PlatformException catch (e) {
    _say(say, 'The file dialog could not be opened (${e.message ?? e.code}).');
    return;
  }
  if (file == null) return;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return;
  await importStudyBytes(context, study, bytes, file.name, opened: opened);
}

/// Adds a PDF's bytes to Study and opens the book.
Future<void> importStudyBytes(
  BuildContext context,
  StudyController study,
  Uint8List bytes,
  String name, {
  VoidCallback? opened,
}) async {
  final say = ScaffoldMessenger.of(context);
  try {
    final (book, isNew) = await study.importBytes(bytes, name);
    _say(
      say,
      isNew ? 'Imported “${book.name}”. It is kept on this device only.' : '“${book.name}” is already in Study.',
    );
    await study.open(book);
    opened?.call();
  } on ImportProblem catch (e) {
    _say(say, e.message);
  } on FileSystemException catch (e) {
    _say(say, 'The book could not be stored (${e.osError?.message ?? e.message}).');
  }
}

const _files = MethodChannel('bahai_reader/files');

/// Writes the open run's Markdown export where the person chooses (a save dialog; on Android, the system's "Save to").
Future<void> exportStudyRun(BuildContext context, StudyController study) async {
  final book = study.book, run = study.run;
  if (book == null || run == null) return;
  final say = ScaffoldMessenger.of(context);
  final markdown = renderMarkdown(
    book: book,
    run: run,
    highlights: study.highlights,
    bookmarks: study.bookmarks,
    answers: study.answers,
    notes: study.notes,
  );
  final name = exportFileName(book, run);
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final saved = await _files.invokeMethod<bool>('save', {'name': name, 'mime': 'text/markdown', 'text': markdown});
      if (saved == true) _say(say, 'Exported “$name”.');
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
    _say(say, 'Exported to $path');
  } on PlatformException catch (e) {
    _say(say, 'The export could not be saved (${e.message ?? e.code}).');
  } on FileSystemException catch (e) {
    _say(say, 'The export could not be saved (${e.osError?.message ?? e.message}).');
  }
}
