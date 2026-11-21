import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/study/export.dart';
import '../../core/study/importer.dart';
import '../../core/study/study_controller.dart';
import '../../core/study/study_store.dart';

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

/// Adds a PDF's bytes to Study and opens the book. If it looks like another edition of a book you have marked, asks
/// whether to move that book (and all its marks) to it.
Future<void> importStudyBytes(
  BuildContext context,
  StudyController study,
  Uint8List bytes,
  String name, {
  VoidCallback? opened,
}) async {
  final say = ScaffoldMessenger.of(context);
  try {
    final check = await study.prepare(bytes, name);
    StudyBook book;
    if (check.same != null) {
      book = check.same!;
      study.add(check); // puts a removed copy back
      _say(say, '“${book.name}” is already in Study.');
    } else if (check.other != null && context.mounted) {
      final other = check.other!;
      final choice = await _askEdition(context, other, check, study.store.markCount(other));
      if (choice == null) return;
      if (choice == _Edition.move && context.mounted) {
        final plan = await _withProgress(context, (progress) => study.moveToEdition(other, check, progress: progress));
        book = study.store.book(other.id)!;
        if (plan != null) {
          _say(
            say,
            plan.unplaced == 0
                ? 'All ${_marks(plan.placed)} of “${book.name}” were found in this edition.'
                : '${_marks(plan.placed)} found in this edition; ${plan.unplaced} could not be, and '
                      '${plan.unplaced == 1 ? 'is' : 'are'} listed under “Not placed yet” in the book.',
          );
        }
      } else {
        book = study.add(check, notSameAs: choice == _Edition.different ? other : null).$1;
        _say(say, 'Imported “${book.name}”. It is kept on this device only.');
      }
    } else {
      book = study.add(check).$1;
      _say(say, 'Imported “${book.name}”. It is kept on this device only.');
    }
    await study.open(book);
    opened?.call();
    if (context.mounted) await offerDogear(context, study, book);
  } on ImportProblem catch (e) {
    _say(say, e.message);
  } on FileSystemException catch (e) {
    _say(say, 'The book could not be stored (${e.osError?.message ?? e.message}).');
  }
}

String _marks(int n) => '$n mark${n == 1 ? '' : 's'}';

enum _Edition { move, separate, different }

Future<_Edition?> _askEdition(BuildContext context, StudyBook other, ImportCheck check, int marks) =>
    showDialog<_Edition>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Another edition of a book you have marked?'),
        content: SizedBox(
          width: 480,
          child: Text(
            '“${check.file.fileName}” looks like another copy or edition of “${other.name}”, which has $marks '
            'mark${marks == 1 ? '' : 's'}.\n\nMoving the book to this edition looks for every highlight, answer and '
            'bookmark (from every time through) in it and puts it there. Anything that cannot be found is kept and '
            'listed so you can place it yourself. The old edition’s copy is kept.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, _Edition.different), child: const Text('Not the same book')),
          TextButton(onPressed: () => Navigator.pop(d, _Edition.separate), child: const Text('Keep it separate')),
          FilledButton(onPressed: () => Navigator.pop(d, _Edition.move), child: const Text('Move my marks')),
        ],
      ),
    );

/// Runs [task] behind a dialog that shows its progress; null if it failed (the failure is shown).
Future<T?> _withProgress<T>(BuildContext context, Future<T> Function(void Function(String)) task) async {
  final message = ValueNotifier('Working…');
  final nav = Navigator.of(context);
  final say = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (d) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder(valueListenable: message, builder: (_, m, _) => Text(m)),
          ),
        ],
      ),
    ),
  );
  try {
    return await task((m) => message.value = m);
  } catch (e) {
    _say(say, 'That did not work ($e). Nothing was changed.');
    return null;
  } finally {
    nav.pop();
    message.dispose();
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
    categories: [for (final c in study.categoriesOf(book)) c.name],
  );
  await _saveMarkdown(say, exportFileName(book, run), markdown);
}

/// Writes every time through the book into one Markdown file (each question with every run's answer under it).
Future<void> exportAllRuns(BuildContext context, StudyController study) async {
  final book = study.book;
  if (book == null) return;
  final say = ScaffoldMessenger.of(context);
  final markdown = renderAllRunsMarkdown(
    book: book,
    runs: [
      for (final r in study.runs)
        (
          run: r,
          highlights: study.store.highlights(r.id),
          answers: study.store.answers(r.id),
          notes: study.store.notes(r.id),
        ),
    ],
    categories: [for (final c in study.categoriesOf(book)) c.name],
  );
  await _saveMarkdown(say, allRunsFileName(book), markdown);
}

Future<void> _saveMarkdown(ScaffoldMessengerState say, String name, String markdown) async {
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

/// Linux: if Dogear has marks for this book (the same file or another edition), offers to bring them in. [asked]: from
/// the menu, offered even if they were brought in or skipped before.
Future<void> offerDogear(BuildContext context, StudyController study, StudyBook book, {bool asked = false}) async {
  final d = study.dogearFor(book, again: asked);
  if (d == null) {
    if (asked) _say(ScaffoldMessenger.of(context), 'Dogear has no marks for this book.');
    return;
  }
  final say = ScaffoldMessenger.of(context);
  final empty =
      study.store.counts(study.store.currentRun(book).id) == (highlights: 0, notes: 0, answers: 0, bookmarks: 0);
  final same = d.sha256 == book.doc.sha256;
  final choice = await showDialog<String>(
    context: context,
    builder: (dlg) => AlertDialog(
      title: const Text('Bring in your Dogear marks?'),
      content: SizedBox(
        width: 480,
        child: Text(
          'Dogear has ${d.summary} for ${same ? 'this book' : 'another edition of it (“${d.fileName}”)'}.\n\n'
          '${empty ? 'They become this first time through.' : 'They come in as a time through of their own, “From Dogear”, listed before the others; nothing here is changed.'}'
          '${same ? '' : ' Marks that cannot be found in this edition are listed so you can place them.'} '
          'Dogear’s own files are only read.',
        ),
      ),
      actions: [
        if (!asked) TextButton(onPressed: () => Navigator.pop(dlg, 'never'), child: const Text('Don’t ask again')),
        TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(dlg, 'yes'), child: const Text('Bring them in')),
      ],
    ),
  );
  if (choice == 'never') return study.skipDogear(book, d);
  if (choice != 'yes' || !context.mounted) return;
  final report = await _withProgress(context, (progress) {
    progress('Bringing in Dogear’s marks…');
    return study.bringInDogear(book, d);
  });
  if (report == null) return;
  _say(
    say,
    report.unplaced == 0
        ? 'Brought in ${report.placed} marks from Dogear into “${report.runName}”.'
        : 'Brought in ${report.placed} marks from Dogear into “${report.runName}”; ${report.unplaced} could not be '
              'found in this edition and are listed under “Not placed yet”.',
  );
}
