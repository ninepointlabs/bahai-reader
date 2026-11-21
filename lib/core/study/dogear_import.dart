/// Bringing in marks made in Dogear (Nine Point Labs' PDF study reader, Linux) for a book imported into Study.
///
/// Dogear keeps one JSON file per PDF in `<library>/.dogear/annotations/<sha256>.json` (schema `"dogear": 1`; its
/// README, "Storage"). They are only read here, never changed. Positions are PDF points from the page's top-left, as
/// here; Dogear's pages are 0-based. For the same file, marks keep their places; for another edition of it, they are
/// found the way a move to another edition finds them, and what is not found is listed to place.
library;

import 'dart:convert';
import 'dart:io';

import 'editions.dart';
import 'page_data.dart';
import 'study_store.dart';

/// One Dogear document's marks.
class DogearDoc {
  DogearDoc(this.json)
    : sha256 = json['sha256'] as String? ?? '',
      fileName = json['file_name'] as String? ?? '',
      title = json['title'] as String? ?? '',
      label = json['label'] as String? ?? '',
      pageCount = json['page_count'] is int ? json['page_count'] as int : 0,
      pdfId = json['pdf_id'] as String?;
  final Map<String, Object?> json;
  final String sha256, fileName, title, label;
  final int pageCount;
  final String? pdfId;

  List<Map<String, Object?>> _list(String key) => [
    for (final x in json[key] is List ? json[key] as List : const [])
      if (x is Map) x.cast<String, Object?>(),
  ];

  List<Map<String, Object?>> get highlights => _list('highlights');
  List<Map<String, Object?>> get bookmarks => _list('bookmarks');
  List<Map<String, Object?>> get notes => _list('notes');
  List<Map<String, Object?>> get answers => [
    for (final a in _list('answers'))
      if ((a['text'] as String? ?? '').trim().isNotEmpty) a,
  ];
  List<String> get categories => [
    for (final c in json['categories'] is List ? json['categories'] as List : const [])
      if (c is String && c.trim().isNotEmpty) c,
  ];

  int get markCount => highlights.length + bookmarks.length + notes.length + answers.length;

  FileFacts get facts =>
      FileFacts(sha256: sha256, fileName: fileName, title: title, pageCount: pageCount, pdfDocId: pdfId);

  /// "11 highlights, 100 answers and 2 bookmarks".
  String get summary {
    String n(int v, String one) => '$v $one${v == 1 ? '' : 's'}';
    final parts = [
      if (highlights.isNotEmpty) n(highlights.length, 'highlight'),
      if (answers.isNotEmpty) n(answers.length, 'answer'),
      if (bookmarks.isNotEmpty) n(bookmarks.length, 'bookmark'),
      if (notes.isNotEmpty) n(notes.length, 'note'),
    ];
    if (parts.length < 2) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }
}

/// Dogear's library folder, as Dogear works it out: `$DOGEAR_LIBRARY_DIR`, else `library_dir` in
/// `$XDG_CONFIG_HOME/dogear/settings.json`, else `Dogear` in the documents folder (`XDG_DOCUMENTS_DIR`).
Directory? dogearLibrary({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  if (env['DOGEAR_LIBRARY_DIR'] case final d? when d.isNotEmpty) return Directory(d);
  final home = env['HOME'] ?? '';
  if (home.isEmpty) return null;
  final config = (env['XDG_CONFIG_HOME']?.isNotEmpty ?? false) ? env['XDG_CONFIG_HOME']! : '$home/.config';
  try {
    final s = jsonDecode(File('$config/dogear/settings.json').readAsStringSync());
    if (s is Map && s['library_dir'] is String && (s['library_dir'] as String).trim().isNotEmpty) {
      final d = (s['library_dir'] as String).trim();
      return Directory(d.startsWith('~/') ? '$home${d.substring(1)}' : d);
    }
  } on Object {
    // no settings: the default
  }
  var documents = '$home/Documents';
  try {
    for (final line in File('$config/user-dirs.dirs').readAsLinesSync()) {
      if (line.startsWith('XDG_DOCUMENTS_DIR=')) {
        documents = line.split('=').skip(1).join('=').trim().replaceAll('"', '').replaceAll(r'$HOME', home);
      }
    }
  } on FileSystemException {
    // the default
  }
  return Directory('$documents/Dogear');
}

/// Dogear's documents with marks (PDFs only), read from [library]. A damaged file is skipped.
List<DogearDoc> readDogear(Directory library) {
  final dir = Directory('${library.path}/.dogear/annotations');
  if (!dir.existsSync()) return const [];
  final out = <DogearDoc>[];
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    try {
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map || j['dogear'] != 1) continue;
      final d = DogearDoc(j.cast<String, Object?>());
      if (d.sha256.isEmpty || !d.fileName.toLowerCase().endsWith('.pdf') || d.markCount == 0) continue;
      out.add(d);
    } on Object {
      continue;
    }
  }
  return out;
}

/// Dogear's marks for [book]: the same file, else another copy or edition of it (most marked first).
DogearDoc? findDogear(List<DogearDoc> docs, StudyBook book) {
  final exact = docs.where((d) => d.sha256 == book.doc.sha256).firstOrNull;
  if (exact != null) return exact;
  final facts = StudyStore.facts(book.doc);
  final copies = [
    for (final d in docs)
      if (isCopyOf(facts, d.facts)) d,
  ]..sort((a, b) => b.markCount.compareTo(a.markCount));
  return copies.firstOrNull;
}

class DogearReport {
  int placed = 0, unplaced = 0;
  String runName = '';
}

/// Brings [d]'s marks into [book]: into its current time through if that has no marks yet, else into a time through of
/// their own, "From Dogear", listed before the others and finished. [pages] are the book's pages' text; [withRules] reads
/// a page with its answer lines.
Future<DogearReport> importDogear(
  StudyStore store,
  StudyBook book,
  DogearDoc d, {
  required List<PageData> pages,
  required List<(String, int)> outline,
  required Future<PageData> Function(int page) withRules,
}) async {
  final report = DogearReport();
  final exact = d.sha256 == book.doc.sha256;
  final current = store.currentRun(book);
  final StudyRun run;
  if (store.counts(current.id) == (highlights: 0, notes: 0, answers: 0, bookmarks: 0)) {
    run = current;
  } else {
    run = store.addRun(book, name: 'From Dogear', ordinal: 0, locked: true);
  }
  report.runName = run.name;
  final count = pages.length;
  int clamp(int p) => p.clamp(1, count < 1 ? 1 : count);
  final lost = 'dogear:${d.sha256}';
  final ruled = <int, PageData>{};
  Future<List<PageData>> ruledPages(Iterable<int> ns) async => [
    for (final n in ns)
      if (n >= 1 && n <= count) ruled[n] ??= await withRules(n),
  ];
  double numOf(Object? v) => v is num ? v.toDouble() : 0;
  int page0(Object? v) => (v is int ? v : 0) + 1;

  final records = <(String, Map<String, Object?>)>[];
  for (final h in d.highlights) {
    final quote = (h['text'] as String? ?? '').trim();
    final hint = page0(h['page']);
    final color = studyColors.contains(h['color']) ? h['color'] as String : 'yellow';
    final note = (h['note'] as String? ?? '').trim();
    final rects = [
      for (final r in h['rects'] is List ? h['rects'] as List : const [])
        if (r is List && r.length == 4) [for (final v in r) numOf(v)],
    ];
    final found = quote.isEmpty ? null : findQuote(exact ? [pages[clamp(hint) - 1]] : pages, quote, hintPage: hint);
    final base = {'run_id': run.id, 'color': color, 'note': note.isEmpty ? null : note, 'quote': quote};
    if (found != null) {
      final (pg, s, e) = found;
      final p = pages[pg - 1];
      records.add((
        'doc_highlight',
        {
          ...base,
          'doc_id': book.docId,
          'page': pg,
          // The same file: Dogear's own boxes; another edition: the boxes of the words where they are now.
          'rects': jsonEncode(exact && rects.isNotEmpty ? rects : [for (final b in p.boxesFor(s, e)) b.toJson()]),
          'char_start': s,
          'char_end': e,
          'prefix': p.text.substring((s - 32).clamp(0, s), s),
          'suffix': p.text.substring(e, (e + 32).clamp(e, p.text.length)),
        },
      ));
      report.placed++;
    } else if (exact && rects.isNotEmpty) {
      records.add(('doc_highlight', {...base, 'doc_id': book.docId, 'page': hint, 'rects': jsonEncode(rects)}));
      report.placed++;
    } else {
      records.add(('doc_highlight', {...base, 'doc_id': lost, 'page': hint, 'rects': jsonEncode(rects)}));
      report.unplaced++;
    }
  }

  // Answers: which blank of its question each is, counted on its page in reading order.
  final answers = [...d.answers]
    ..sort((a, b) {
      final pa = page0(a['page']), pb = page0(b['page']);
      if (pa != pb) return pa.compareTo(pb);
      final ya = numOf(a['y']), yb = numOf(b['y']);
      return ya != yb ? ya.compareTo(yb) : numOf(a['x']).compareTo(numOf(b['x']));
    });
  final seen = <String, int>{};
  for (final a in answers) {
    final hint = page0(a['page']);
    final context = (a['context'] as String? ?? '').trim();
    final ordinal = seen.update('$hint:$context', (n) => n + 1, ifAbsent: () => 0);
    final text = (a['text'] as String).trim();
    AnswerPlace? place;
    var at = hint;
    if (exact) {
      place = AnswerPlace(
        page: clamp(hint),
        kind: 'line',
        x: numOf(a['x']),
        y: numOf(a['y']),
        w: numOf(a['w']),
        pitch: numOf(a['pitch']),
        lines: a['lines'] is int ? a['lines'] as int : 1,
        size: numOf(a['size']) > 0 ? numOf(a['size']) : 11,
      );
    } else if (context.isNotEmpty) {
      var found = findSlot(
        await ruledPages([for (var x = -2; x <= 2; x++) hint + x]),
        context,
        ordinal: -1, // Dogear counts one per answer, this app one per ruled line: the nearest instead
        hintPage: hint,
        hintY: numOf(a['y']),
      );
      found ??= findSlot(
        ruled.values.where((p) => (p.number - hint).abs() <= 2).toList(),
        context,
        hintPage: hint,
        hintY: numOf(a['y']),
        loose: true,
      );
      found ??= findSlot(
        await ruledPages([for (var n = 1; n <= count; n++) n]),
        context,
        ordinal: ordinal,
        hintPage: hint,
      );
      if (found != null) {
        final (pg, i) = found;
        final slot = slotAt(ruled[pg]!, i);
        at = pg;
        place = AnswerPlace(
          page: pg,
          kind: 'line',
          x: slot.x,
          y: slot.y,
          w: slot.w,
          pitch: slot.pitch,
          lines: slot.lines,
          indent: slot.indent,
          size: numOf(a['size']) > 0 ? numOf(a['size']) : slot.size,
        );
      }
    }
    final docId = place == null ? lost : book.docId;
    final p =
        place ??
        AnswerPlace(
          page: hint,
          kind: 'line',
          x: numOf(a['x']),
          y: numOf(a['y']),
          w: numOf(a['w']),
          size: numOf(a['size']),
        );
    records.add((
      'answer',
      {
        'run_id': run.id,
        'doc_id': docId,
        'page': at,
        'kind': 'line',
        'x': p.x,
        'y': p.y,
        'w': p.w,
        'h': 0,
        'pitch': p.pitch,
        'lines': p.lines,
        'indent': p.indent,
        'size': p.size,
        'context': context,
        'slot_key': slotKey(context, ordinal, fallback: p.key(docId)),
        'text': text,
      },
    ));
    place == null ? report.unplaced++ : report.placed++;
  }

  for (final b in d.bookmarks) {
    final name = (b['name'] as String? ?? '').trim();
    records.add((
      'doc_bookmark',
      {
        'run_id': run.id,
        'doc_id': book.docId,
        'page': exact ? clamp(page0(b['page'])) : (pageNamed(outline, name) ?? clamp(page0(b['page']))),
        'y': numOf(b['y']),
        'name': name,
      },
    ));
    report.placed++;
  }
  for (final n in d.notes) {
    final text = (n['text'] as String? ?? '').trim();
    if (text.isEmpty) continue;
    records.add(('doc_note', {'book_id': book.id, 'run_id': run.id, 'text': text}));
    report.placed++;
  }
  store.addRecords(records);
  if (d.categories.isNotEmpty) {
    store.setCategories(store.book(book.id)!, {
      ...store.categoriesOf(book),
      for (final c in d.categories) store.category(c),
    });
  }
  if (book.label.isEmpty && d.label.trim().isNotEmpty) store.rename(store.book(book.id)!, d.label);
  store.markDogearDone(d.sha256, book.id);
  return report;
}
