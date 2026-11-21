/// Markdown export of one run of a Study book, for a notes vault such as Obsidian. The format follows Dogear's
/// `export.py`: YAML front matter, the book notes, then one section per page with its bookmarks, highlights (quoted,
/// each note under it) and answers (with the printed question), in reading order.
///
/// An export is regenerated every time. A file is only ever overwritten when its front matter says this app wrote it
/// for the same book and run.
library;

import 'dart:io';

import 'study_store.dart';

final _unsafeName = RegExp(r'[\\/:*?"<>|\x00-\x1f]+');

String _yaml(String v) => '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', ' ')}"';

String _quote(String text) {
  final lines = text.trim().split('\n');
  return [for (final l in lines) '> $l'.trimRight()].join('\n');
}

String _answer(String text) => '**A:** ${[for (final l in text.trim().split('\n')) l.trimRight()].join('  \n')}  ';

/// Categories as Obsidian tags: "Ruhi Book 5" → ruhi-book-5 (Dogear's rule; numbers alone are not tags).
List<String> obsidianTags(Iterable<String> categories) {
  final out = <String>[];
  for (final name in categories) {
    final tag = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}_/-]+', unicode: true), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (tag.isNotEmpty && !RegExp(r'^\d+$').hasMatch(tag) && !out.contains(tag)) out.add(tag);
  }
  return out;
}

String _tags(Iterable<String> categories) => '[${['bahai-reader', 'study', ...obsidianTags(categories)].join(', ')}]';

/// "Page 3", or "Page 3 (iii)" when the PDF labels the page differently.
String pageHeading(int page, String label) =>
    label.isNotEmpty && label != '$page' ? 'Page $page ($label)' : 'Page $page';

/// `<book> — <run>.md`, made safe as a file name.
String exportFileName(StudyBook book, StudyRun run) {
  final base = '${book.name} — ${run.name}'
      .replaceAll(_unsafeName, ' ')
      .trim()
      .replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
  return '${base.isEmpty ? 'Study' : base}.md';
}

String renderMarkdown({
  required StudyBook book,
  required StudyRun run,
  required List<DocHighlight> highlights,
  required List<DocBookmark> bookmarks,
  required List<Answer> answers,
  required List<DocNote> notes,
  String Function(int page)? pageLabel,
  DateTime? exportedAt,
  List<String> categories = const [],
}) {
  final label = pageLabel ?? (_) => '';
  final filled = [
    for (final a in answers)
      if (a.text.trim().isNotEmpty) a,
  ];
  final stamp = (exportedAt ?? DateTime.now()).toIso8601String().split('.').first;
  final out = <String>[
    '---',
    'title: ${_yaml(book.name)}',
    'run: ${_yaml(run.name)}',
    'file: ${_yaml(book.doc.fileName)}',
    'sha256: ${book.doc.sha256}',
    'generator: bahai-reader',
    'exported: $stamp',
    'highlights: ${highlights.length}',
    'bookmarks: ${bookmarks.length}',
    'answers: ${filled.length}',
    'tags: ${_tags(categories)}',
    '---',
    '',
    '# ${book.name}',
    '',
    '*${run.name}. Exported from Bahá’í Reader; this file is made again on every export, so keep your own edits '
        'elsewhere.*',
    '',
  ];
  final kept = [
    for (final n in notes)
      if (n.text.trim().isNotEmpty) n.text.trim(),
  ];
  if (kept.isNotEmpty) {
    out.addAll(['## Notes', '']);
    for (final n in kept) {
      out.addAll([n, '']);
    }
  }
  final pages = {
    ...highlights.map((h) => h.page),
    ...bookmarks.map((b) => b.page),
    ...filled.map((a) => a.page),
  }.toList()..sort();
  for (final page in pages) {
    out.addAll(['## ${pageHeading(page, label(page))}', '']);
    final marks = bookmarks.where((b) => b.page == page).toList();
    for (final b in marks) {
      out.add('- **Bookmark:** ${b.name}');
    }
    if (marks.isNotEmpty) out.add('');
    // Highlights and answers interleaved top to bottom, as on the page.
    final items = <(double, double, Object)>[
      for (final h in highlights)
        if (h.page == page) (h.order.$2, h.order.$3, h),
      for (final a in filled)
        if (a.page == page) (a.place.y, a.place.x, a),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    String? lastContext;
    for (final (_, _, item) in items) {
      if (item is DocHighlight) {
        if (lastContext != null) out.add('');
        lastContext = null;
        out.add(_quote(item.quote.isEmpty ? '(no text)' : item.quote));
        out.add('> — p. $page · ${item.color}');
        out.add('');
        if (item.note?.trim() case final note? when note.isNotEmpty) out.addAll([note, '']);
        continue;
      }
      final a = item as Answer;
      // Blanks of one printed question share it: show it once.
      if (a.context.isNotEmpty && a.context != lastContext) {
        if (lastContext != null) out.add('');
        out.add('**Q:** ${a.context}  ');
      }
      lastContext = a.context;
      out.add(_answer(a.text));
    }
    if (lastContext != null) out.add('');
  }
  if (kept.isEmpty && pages.isEmpty) out.addAll(['*No highlights, notes, bookmarks or answers yet.*', '']);
  return '${out.join('\n').replaceAll(RegExp(r'\n+$'), '')}\n';
}

/// Whether [file] may be overwritten with this book and run's export: it doesn't exist, or this app wrote it for them.
bool _ours(File file, StudyBook book, StudyRun run) {
  if (!file.existsSync()) return true;
  String head;
  try {
    final raf = file.openSync();
    try {
      head = String.fromCharCodes(raf.readSync(4096));
    } finally {
      raf.closeSync();
    }
  } on FileSystemException {
    return false;
  }
  return head.contains('\ngenerator: bahai-reader\n') &&
      head.contains('\nsha256: ${book.doc.sha256}\n') &&
      head.contains('\nrun: ${_yaml(run.name)}\n');
}

/// Writes the export into [folder] and returns the file. A file of the same name that this app did not write for this
/// book and run is left alone; the export then gets the file's hash and run in its name.
Future<File> exportMarkdown(Directory folder, String markdown, StudyBook book, StudyRun run) async {
  await folder.create(recursive: true);
  var target = File('${folder.path}/${exportFileName(book, run)}');
  if (!_ours(target, book, run)) {
    final stem = target.path.substring(0, target.path.length - 3);
    target = File(
      '$stem (${book.doc.sha256.substring(0, book.doc.sha256.length < 8 ? book.doc.sha256.length : 8)}-${run.ordinal}).md',
    );
  }
  final tmp = File('${target.path}.tmp');
  await tmp.writeAsString(markdown, flush: true);
  await tmp.rename(target.path);
  return target;
}

/// `<book> — all runs.md`.
String allRunsFileName(StudyBook book) {
  final base = '${book.name} — all runs'.replaceAll(_unsafeName, ' ').trim().replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
  return '${base.isEmpty ? 'Study' : base}.md';
}

/// One run's marks, for [renderAllRunsMarkdown].
typedef RunMarks = ({StudyRun run, List<DocHighlight> highlights, List<Answer> answers, List<DocNote> notes});

/// Every run of a book in one file, to see how answers changed: each page's questions with every run's answer under
/// them (labelled with the run), then the highlights of every run, and each run's book notes.
String renderAllRunsMarkdown({
  required StudyBook book,
  required List<RunMarks> runs,
  DateTime? exportedAt,
  List<String> categories = const [],
}) {
  final stamp = (exportedAt ?? DateTime.now()).toIso8601String().split('.').first;
  final out = <String>[
    '---',
    'title: ${_yaml(book.name)}',
    'runs: [${runs.map((r) => _yaml(r.run.name)).join(', ')}]',
    'file: ${_yaml(book.doc.fileName)}',
    'sha256: ${book.doc.sha256}',
    'generator: bahai-reader',
    'exported: $stamp',
    'tags: ${_tags(categories)}',
    '---',
    '',
    '# ${book.name}',
    '',
    '*Every time through, side by side: ${runs.map((r) => r.run.name).join('; ')}. Exported from Bahá’í Reader; this '
        'file is made again on every export, so keep your own edits elsewhere.*',
    '',
  ];
  for (final r in runs) {
    final notes = [
      for (final n in r.notes)
        if (n.text.trim().isNotEmpty) n.text.trim(),
    ];
    if (notes.isEmpty) continue;
    out.addAll(['## Notes — ${r.run.name}', '']);
    for (final n in notes) {
      out.addAll([n, '']);
    }
  }
  // Questions: one entry per blank (its slot key), placed where it first appears.
  final groups = <String, List<(StudyRun, Answer)>>{};
  for (final r in runs) {
    for (final a in r.answers) {
      if (a.text.trim().isEmpty) continue;
      (groups[a.slotKey] ??= []).add((r.run, a));
    }
  }
  final highlights = [
    for (final r in runs)
      for (final h in r.highlights) (r.run, h),
  ];
  final pages = {...groups.values.map((g) => g.first.$2.page), ...highlights.map((h) => h.$2.page)}.toList()..sort();
  for (final page in pages) {
    out.addAll(['## ${pageHeading(page, '')}', '']);
    final qs =
        [
          for (final g in groups.values)
            if (g.first.$2.page == page) g,
        ]..sort((a, b) {
          final pa = a.first.$2.place, pb = b.first.$2.place;
          return pa.y != pb.y ? pa.y.compareTo(pb.y) : pa.x.compareTo(pb.x);
        });
    String? lastContext;
    for (final g in qs) {
      final context = g.map((e) => e.$2.context).firstWhere((c) => c.isNotEmpty, orElse: () => '');
      if (context != lastContext || context.isEmpty) {
        if (lastContext != null) out.add('');
        out.add(context.isEmpty ? '**Q:** (p. $page)  ' : '**Q:** $context  ');
      }
      lastContext = context;
      for (final (run, a) in g) {
        out.add('**A (${run.name}):** ${[for (final l in a.text.trim().split('\n')) l.trimRight()].join('  \n')}  ');
      }
    }
    if (qs.isNotEmpty) out.add('');
    final hs =
        [
          for (final h in highlights)
            if (h.$2.page == page) h,
        ]..sort(
          (a, b) => a.$2.order.$2 != b.$2.order.$2
              ? a.$2.order.$2.compareTo(b.$2.order.$2)
              : a.$2.order.$3.compareTo(b.$2.order.$3),
        );
    for (final (run, h) in hs) {
      out.add(_quote(h.quote.isEmpty ? '(no text)' : h.quote));
      out.add('> — p. $page · ${h.color} · ${run.name}');
      out.add('');
      if (h.note?.trim() case final note? when note.isNotEmpty) out.addAll([note, '']);
    }
  }
  if (pages.isEmpty) out.addAll(['*No highlights or answers yet.*', '']);
  return '${out.join('\n').replaceAll(RegExp(r'\n+$'), '')}\n';
}
