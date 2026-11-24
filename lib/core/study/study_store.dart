/// The Study section's data: imported books, their runs ("times through") and every mark made in a run, kept as
/// records in the user-data store (`userdata.sqlite`, tables in `lib/core/userdata/userdata_store.dart`).
///
/// * A book is one imported file, identified by the SHA-256 of its bytes; the app keeps its own copy in `books/`.
/// * A run owns all marks made in it: highlights and their notes, bookmarks, answers, book notes and the place reached.
///   A new run starts empty; a finished run is locked, and the store refuses to change a locked run's marks.
/// * Ids that two devices would make for the same thing are the same (the book of a file, its first run, the answer on
///   one line in one run), so a later sync merges instead of duplicating.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../userdata/ids.dart';
import '../userdata/userdata_store.dart';
import 'editions.dart';
import 'page_data.dart';

/// Thrown when a change would alter a locked (finished) run.
class RunLocked implements Exception {
  RunLocked(this.run);
  final StudyRun run;
  @override
  String toString() => '“${run.name}” is finished and locked; unlock it to change it.';
}

class DocFile {
  DocFile(this.data)
    : id = data['id'] as String,
      sha256 = data['sha256'] as String,
      fileName = data['file_name'] as String? ?? '',
      title = data['title'] as String? ?? '',
      pageCount = data['page_count'] as int? ?? 0,
      byteSize = data['byte_size'] as int? ?? 0,
      pdfDocId = data['pdf_doc_id'] as String?;
  final Map<String, Object?> data;
  final String id, sha256, fileName, title;
  final int pageCount, byteSize;
  final String? pdfDocId;

  /// The file name without its extension.
  String get stem {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }
}

class StudyCategory {
  const StudyCategory(this.id, this.name);
  final String id, name;
}

class StudyBook {
  StudyBook(Map<String, Object?> r, this.doc)
    : id = r['id'] as String,
      label = r['label'] as String? ?? '',
      docId = r['doc_id'] as String,
      currentRunId = r['current_run_id'] as String?,
      sort = r['sort'] as int? ?? 0,
      removedAt = r['removed_at'] as int?;
  final String id, label, docId;
  final String? currentRunId;
  final int sort;
  final int? removedAt;
  final DocFile doc;

  /// What to call the book: your name for it, else the PDF's title, else its file name.
  String get name => label.trim().isNotEmpty
      ? label.trim()
      : doc.title.trim().isNotEmpty
      ? doc.title.trim()
      : doc.stem;
}

class StudyRun {
  StudyRun(Map<String, Object?> r)
    : id = r['id'] as String,
      bookId = r['book_id'] as String,
      ordinal = r['ordinal'] as int,
      name = r['name'] as String,
      startedAt = r['started_at'] as int?,
      finishedAt = r['finished_at'] as int?,
      locked = r['locked'] == 1;
  final String id, bookId, name;
  final int ordinal;
  final int? startedAt, finishedAt;
  final bool locked;
}

class DocHighlight {
  DocHighlight(Map<String, Object?> r)
    : id = r['id'] as String,
      runId = r['run_id'] as String,
      docId = r['doc_id'] as String,
      page = r['page'] as int,
      rects = [for (final b in (jsonDecode(r['rects'] as String? ?? '[]') as List)) ?Box.fromJson(b)],
      charStart = r['char_start'] as int?,
      charEnd = r['char_end'] as int?,
      quote = r['quote'] as String? ?? '',
      prefix = r['prefix'] as String? ?? '',
      suffix = r['suffix'] as String? ?? '',
      color = r['color'] as String? ?? 'yellow',
      note = r['note'] as String?,
      createdAt = r['created_at'] as int? ?? 0;
  final String id, runId, docId, quote, prefix, suffix, color;
  final int page, createdAt;
  final List<Box> rects;
  final int? charStart, charEnd;
  final String? note;

  /// Reading order on its page: top, then left.
  (int, double, double) get order {
    if (rects.isEmpty) return (page, 0, 0);
    final top = rects.map((r) => r.y).reduce((a, b) => a < b ? a : b);
    final left = rects.where((r) => r.y == top).map((r) => r.x).reduce((a, b) => a < b ? a : b);
    return (page, top, left);
  }
}

class DocBookmark {
  DocBookmark(Map<String, Object?> r)
    : id = r['id'] as String,
      runId = r['run_id'] as String,
      docId = r['doc_id'] as String,
      page = r['page'] as int,
      y = (r['y'] as num?)?.toDouble() ?? 0,
      name = r['name'] as String? ?? '';
  final String id, runId, docId, name;
  final int page;
  final double y;
}

class DocNote {
  DocNote(Map<String, Object?> r)
    : id = r['id'] as String,
      bookId = r['book_id'] as String,
      runId = r['run_id'] as String,
      text = r['text'] as String? ?? '',
      createdAt = r['created_at'] as int? ?? 0;
  final String id, bookId, runId, text;
  final int createdAt;
}

/// Where an answer is written: a detected line (with ruled lines below it) or a box placed by hand, in points.
class AnswerPlace {
  const AnswerPlace({
    required this.page,
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    this.h = 0,
    this.pitch = 0,
    this.lines = 1,
    this.indent = 0,
    this.size = 11,
  });
  final int page;

  /// `line` (on a detected answer line; [y] is the first line) or `box` (placed by hand; [y] is its top, [h] its
  /// height).
  final String kind;
  final double x, y, w, h, pitch, indent, size;
  final int lines;

  /// The same place in every run of a file (and from every device).
  String key(String docId) => '$docId:$page:$kind:${x.toStringAsFixed(1)}:${y.toStringAsFixed(1)}';
}

class Answer {
  Answer(Map<String, Object?> r)
    : id = r['id'] as String,
      runId = r['run_id'] as String,
      docId = r['doc_id'] as String,
      place = AnswerPlace(
        page: r['page'] as int,
        kind: r['kind'] as String? ?? 'line',
        x: (r['x'] as num?)?.toDouble() ?? 0,
        y: (r['y'] as num?)?.toDouble() ?? 0,
        w: (r['w'] as num?)?.toDouble() ?? 0,
        h: (r['h'] as num?)?.toDouble() ?? 0,
        pitch: (r['pitch'] as num?)?.toDouble() ?? 0,
        lines: r['lines'] as int? ?? 1,
        indent: (r['indent'] as num?)?.toDouble() ?? 0,
        size: (r['size'] as num?)?.toDouble() ?? 11,
      ),
      context = r['context'] as String? ?? '',
      slotKey = r['slot_key'] as String? ?? '',
      text = r['text'] as String? ?? '',
      createdAt = r['created_at'] as int? ?? 0;
  final String id, runId, docId, context, slotKey, text;
  final int createdAt;
  final AnswerPlace place;
  int get page => place.page;
}

class DocView {
  const DocView({required this.page, this.offset = 0, this.zoom = 1});
  final int page;
  final double offset, zoom;
}

/// The colours a Study highlight can have (the app's five).
const studyColors = ['yellow', 'green', 'blue', 'pink', 'purple'];

/// Characters kept in one note or answer.
const studyTextLimit = 20000;

/// "1st", "2nd", "3rd", "4th"…
String ordinalWord(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A run's default name: "1st time, Nov 2026".
String runName(int ordinal, DateTime when) => '${ordinalWord(ordinal)} time, ${_months[when.month - 1]} ${when.year}';

/// An edition-independent key for one blank of one printed question: the question's text folded to letters and
/// digits, plus which of its blanks this is. Empty context (no text near the line): tied to this file's page and place.
String slotKey(String context, int ordinal, {required String fallback}) {
  final folded = context.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
  if (folded.isEmpty) return 'at:$fallback';
  return 'q:${uuidV5('slot:$folded')}#$ordinal';
}

class StudyStore {
  StudyStore(this.data, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final UserDataStore data;
  final DateTime Function() _now;

  int get _ms => _now().millisecondsSinceEpoch;

  // ----- books -----

  DocFile? doc(String id) => switch (data.record('doc_file', id)) {
    final r? => DocFile(r),
    null => null,
  };

  StudyBook? book(String id) {
    final r = data.record('study_book', id);
    if (r == null) return null;
    final d = doc(r['doc_id'] as String);
    return d == null ? null : StudyBook(r, d);
  }

  List<StudyBook> _books() => [
    for (final r in data.records('study_book'))
      if (doc(r['doc_id'] as String) case final d?) StudyBook(r, d),
  ];

  /// The library, in its own order (newest import first).
  List<StudyBook> get books => [
    for (final b in _books())
      if (b.removedAt == null) b,
  ]..sort((a, b) => b.sort.compareTo(a.sort));

  /// Books taken out of the library, which can be put back.
  List<StudyBook> get removed => [
    for (final b in _books())
      if (b.removedAt != null) b,
  ]..sort((a, b) => b.removedAt!.compareTo(a.removedAt!));

  /// The book for an imported file, made (with its first run) if there is none; a removed one comes back. Returns the
  /// book and whether it was new.
  (StudyBook, bool) addBook({
    required String sha256,
    required String fileName,
    required int byteSize,
    required int pageCount,
    String title = '',
    String? pdfDocId,
  }) {
    final docId = 'sha256:$sha256';
    // A book on this file already (restored if it was removed).
    final onFile = _books().where((b) => b.docId == docId).firstOrNull;
    if (onFile != null) {
      if (onFile.removedAt != null) restore(onFile);
      return (book(onFile.id)!, false);
    }
    // The id two devices give the same file; taken when the book first made from it moved to another edition.
    var bookId = uuidV5('book:$sha256');
    if (data.record('study_book', bookId) != null) bookId = uuidV7(_now());
    data.batch(() {
      data.put('doc_file', docId, {
        'sha256': sha256,
        'file_name': fileName,
        'title': title,
        'page_count': pageCount,
        'byte_size': byteSize,
        'pdf_doc_id': pdfDocId,
      });
      final runId = uuidV5('run:$bookId:1');
      final now = _now();
      data.put('study_run', runId, {
        'book_id': bookId,
        'ordinal': 1,
        'name': runName(1, now),
        'started_at': now.millisecondsSinceEpoch,
        'locked': 0,
      });
      data.put('study_book', bookId, {
        'label': '',
        'doc_id': docId,
        'current_run_id': runId,
        'sort': now.millisecondsSinceEpoch,
      });
    });
    return (book(bookId)!, true);
  }

  void _putBook(StudyBook b, {String? label, int? removedAt, bool clearRemoved = false, String? currentRunId}) =>
      data.put('study_book', b.id, {
        'label': label ?? b.label,
        'doc_id': b.docId,
        'current_run_id': currentRunId ?? b.currentRunId,
        'sort': b.sort,
        'removed_at': clearRemoved ? null : (removedAt ?? b.removedAt),
      });

  /// Your own name for a book; empty goes back to the PDF's title or file name.
  void rename(StudyBook b, String label) => _putBook(b, label: label.trim());

  /// Takes a book out of the library; its file and marks are kept until it is deleted for good.
  void remove(StudyBook b) => _putBook(b, removedAt: _ms);

  void restore(StudyBook b) => _putBook(b, clearRemoved: true);

  /// Deletes a removed book and everything made in it. Returns the file's SHA-256 if no other book uses it, so the
  /// caller can delete the app's copy.
  String? deleteForever(StudyBook b) {
    final runIds = {for (final r in runsOf(b)) r.id};
    String? orphan;
    data.batch(() {
      for (final t in ['doc_highlight', 'doc_bookmark', 'answer', 'doc_view']) {
        for (final r in data.records(t)) {
          if (runIds.contains(r['run_id'])) data.remove(t, r['id'] as String);
        }
      }
      for (final r in data.records('doc_note')) {
        if (r['book_id'] == b.id) data.remove('doc_note', r['id'] as String);
      }
      for (final id in runIds) {
        data.remove('study_run', id);
      }
      data.remove('study_book', b.id);
      if (!_books().any((x) => x.docId == b.docId)) {
        data.remove('doc_file', b.docId);
        orphan = b.doc.sha256;
      }
    });
    return orphan;
  }

  // ----- categories (schema 3) -----

  /// The categories, by name.
  List<StudyCategory> get categories =>
      [for (final r in data.records('study_category')) StudyCategory(r['id'] as String, r['name'] as String)]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// The category of that name (any case), made if there is none. Two devices making the same name make one.
  StudyCategory category(String name) {
    final clean = name.trim().split(RegExp(r'\s+')).join(' ');
    final existing = categories.where((c) => c.name.toLowerCase() == clean.toLowerCase()).firstOrNull;
    if (existing != null) return existing;
    final id = uuidV5('category:${clean.toLowerCase()}');
    data.put('study_category', id, {'name': clean});
    return StudyCategory(id, clean);
  }

  List<StudyCategory> categoriesOf(StudyBook b) {
    final ids = {
      for (final r in data.records('book_category'))
        if (r['book_id'] == b.id) r['category_id'],
    };
    return [
      for (final c in categories)
        if (ids.contains(c.id)) c,
    ];
  }

  /// Files a book in exactly these categories.
  void setCategories(StudyBook b, Iterable<StudyCategory> want) {
    final ids = {for (final c in want) c.id};
    data.batch(() {
      for (final r in data.records('book_category')) {
        if (r['book_id'] == b.id && !ids.contains(r['category_id'])) data.remove('book_category', r['id'] as String);
      }
      for (final id in ids) {
        data.put('book_category', uuidV5('book_category:${b.id}:$id'), {'book_id': b.id, 'category_id': id});
      }
    });
  }

  /// Renames a category; onto another category's name, the two are merged.
  void renameCategory(StudyCategory c, String name) {
    final clean = name.trim().split(RegExp(r'\s+')).join(' ');
    if (clean.isEmpty || clean == c.name) return;
    final other = categories.where((x) => x.id != c.id && x.name.toLowerCase() == clean.toLowerCase()).firstOrNull;
    data.batch(() {
      if (other == null) {
        data.put('study_category', c.id, {'name': clean});
        return;
      }
      for (final r in data.records('book_category')) {
        if (r['category_id'] != c.id) continue;
        final bookId = r['book_id'] as String;
        data.remove('book_category', r['id'] as String);
        data.put('book_category', uuidV5('book_category:$bookId:${other.id}'), {
          'book_id': bookId,
          'category_id': other.id,
        });
      }
      data.remove('study_category', c.id);
    });
  }

  /// Deletes a category; its books stay in the library.
  void deleteCategory(StudyCategory c) => data.batch(() {
    for (final r in data.records('book_category')) {
      if (r['category_id'] == c.id) data.remove('book_category', r['id'] as String);
    }
    data.remove('study_category', c.id);
  });

  /// When the book was last read (its place was last remembered), or when it was added.
  int lastRead(StudyBook b) {
    final runs = {for (final r in runsOf(b)) r.id};
    var at = b.sort;
    for (final r in data.records('doc_view')) {
      if (runs.contains(r['run_id'])) at = math.max(at, r['updated_at'] as int? ?? 0);
    }
    return at;
  }

  /// Every mark made in the book, in all its runs.
  int markCount(StudyBook b) {
    final runs = {for (final r in runsOf(b)) r.id};
    var n = 0;
    for (final t in ['doc_highlight', 'answer', 'doc_bookmark', 'doc_note']) {
      for (final r in data.records(t)) {
        if (runs.contains(r['run_id'])) n++;
      }
    }
    return n;
  }

  // ----- other editions (schema 4) -----

  /// What is known about a book's file, for recognizing other copies of it.
  static FileFacts facts(DocFile d) =>
      FileFacts(sha256: d.sha256, fileName: d.fileName, title: d.title, pageCount: d.pageCount, pdfDocId: d.pdfDocId);

  bool declined(String sha256, String bookId) =>
      data.record('study_decline', uuidV5('decline:$sha256:$bookId')) != null;

  /// "Not the same book": [sha256] is not offered [bookId]'s marks again.
  void decline(String sha256, String bookId) =>
      data.put('study_decline', uuidV5('decline:$sha256:$bookId'), {'sha256': sha256, 'book_id': bookId});

  /// A book with marks that [file] looks like another copy or edition of (most marked first), unless declined.
  StudyBook? otherEditionOf(FileFacts file) {
    final found = [
      for (final b in books)
        if (!declined(file.sha256, b.id) && isCopyOf(file, facts(b.doc)) && markCount(b) > 0) b,
    ]..sort((a, b) => markCount(b).compareTo(markCount(a)));
    return found.firstOrNull;
  }

  /// Moves a book to another edition: [newDoc] becomes its file, and each mark in [updates] (table, id, new values)
  /// is put where it was found in the new edition. Marks not in [updates] keep their old file and are listed as not
  /// placed yet. Finished runs' marks move too: this is the app keeping them with their book, not a change to them.
  void moveToEdition(StudyBook b, Map<String, Object?> newDoc, List<(String, String, Map<String, Object?>)> updates) {
    final docId = 'sha256:${newDoc['sha256']}';
    data.batch(() {
      data.put('doc_file', docId, newDoc);
      for (final (table, id, values) in updates) {
        final old = data.record(table, id);
        if (old != null) data.put(table, id, {...old, ...values, 'doc_id': docId});
      }
      final current = book(b.id) ?? b;
      data.put('study_book', b.id, {
        'label': current.label,
        'doc_id': docId,
        'current_run_id': current.currentRunId,
        'sort': current.sort,
        'removed_at': current.removedAt,
      });
    });
  }

  /// Marks of a run that are not on the book's file (carried from another edition and not found there yet).
  ({List<DocHighlight> highlights, List<Answer> answers, List<DocBookmark> bookmarks}) unplaced(
    StudyBook b,
    String runId,
  ) => (
    highlights: [
      for (final h in highlights(runId))
        if (h.docId != b.docId) h,
    ],
    answers: [
      for (final a in answers(runId))
        if (a.docId != b.docId) a,
    ],
    bookmarks: [
      for (final m in bookmarks(runId))
        if (m.docId != b.docId) m,
    ],
  );

  /// A run made from marks brought in from elsewhere (Dogear): not the current one; [ordinal] 0 lists it first.
  StudyRun addRun(StudyBook b, {required String name, int ordinal = 0, bool locked = true}) {
    final now = _now();
    final id = uuidV7(now);
    data.put('study_run', id, {
      'book_id': b.id,
      'ordinal': ordinal,
      'name': name,
      'started_at': now.millisecondsSinceEpoch,
      'finished_at': locked ? now.millisecondsSinceEpoch : null,
      'locked': locked ? 1 : 0,
    });
    return run(id)!;
  }

  /// Writes marks brought in from elsewhere, each with a new id, in one transaction (the run may be locked: this is
  /// the app filling it, not a change to it).
  void addRecords(List<(String, Map<String, Object?>)> records) => data.batch(() {
    for (final (table, values) in records) {
      data.put(table, uuidV7(_now()), values);
    }
  });

  /// Changes fields of existing records (the app correcting them, not a change by the person: locked runs too).
  void updateRecords(List<(String, String, Map<String, Object?>)> updates) => data.batch(() {
    for (final (table, id, values) in updates) {
      final old = data.record(table, id);
      if (old != null) data.put(table, id, {...old, ...values});
    }
  });

  bool dogearDone(String dogearSha, String bookId) => declined('dogear:$dogearSha', bookId);
  void markDogearDone(String dogearSha, String bookId) => decline('dogear:$dogearSha', bookId);

  /// Puts an unplaced mark aside for good (the person will mark it again themselves).
  void dropUnplaced(String table, String id) => data.remove(table, id);

  // ----- runs -----

  List<StudyRun> runsOf(StudyBook b) => [
    for (final r in data.records('study_run'))
      if (r['book_id'] == b.id) StudyRun(r),
  ]..sort((a, b) => a.ordinal.compareTo(b.ordinal));

  StudyRun? run(String id) => switch (data.record('study_run', id)) {
    final r? => StudyRun(r),
    null => null,
  };

  /// The run being worked on: the book's current run (or its latest).
  StudyRun currentRun(StudyBook b) {
    final id = b.currentRunId;
    final r = id == null ? null : run(id);
    return r ?? runsOf(b).last;
  }

  /// Finished runs unlocked for this session (until the book is closed). They stay locked in the store.
  final Set<String> unlocked = {};

  /// Whether a run's marks can be changed now: it is not finished, or it was unlocked for this session.
  bool editable(StudyRun r) => !r.locked || unlocked.contains(r.id);

  StudyRun _open(String runId) {
    final r = run(runId);
    if (r == null) throw StateError('no such run');
    if (!editable(r)) throw RunLocked(r);
    return r;
  }

  /// Starts another time through the book: a new, empty run named [name] (default "2nd time, Nov 2026"). The run that
  /// was current is finished and locked; nothing in it changes. Returns the new run.
  StudyRun startRun(StudyBook b, {String? name}) {
    final runs = runsOf(b);
    final ordinal = (runs.isEmpty ? 0 : runs.map((r) => r.ordinal).reduce((a, c) => a > c ? a : c)) + 1;
    final now = _now();
    final id = uuidV7(now);
    data.batch(() {
      for (final r in runs) {
        if (!r.locked || r.finishedAt == null) {
          data.put('study_run', r.id, {
            ...data.record('study_run', r.id)!,
            'finished_at': r.finishedAt ?? now.millisecondsSinceEpoch,
            'locked': 1,
          });
        }
      }
      final clean = name?.trim();
      data.put('study_run', id, {
        'book_id': b.id,
        'ordinal': ordinal,
        'name': clean == null || clean.isEmpty ? runName(ordinal, now) : clean,
        'started_at': now.millisecondsSinceEpoch,
        'locked': 0,
      });
      _putBook(book(b.id) ?? b, currentRunId: id);
    });
    unlocked.removeWhere((x) => runs.any((r) => r.id == x));
    return run(id)!;
  }

  /// A run's name ("2nd time, Nov 2026" → "Autumn study circle"). Allowed on a locked run: it changes no marks.
  void renameRun(StudyRun r, String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    data.put('study_run', r.id, {...data.record('study_run', r.id)!, 'name': clean});
  }

  /// Deletes a run that is not the book's current one, with everything made in it.
  void deleteRun(StudyBook b, StudyRun r) {
    if (currentRun(b).id == r.id) throw StateError('the current run cannot be deleted');
    data.batch(() {
      for (final t in ['doc_highlight', 'doc_bookmark', 'answer', 'doc_view', 'doc_note']) {
        for (final x in data.records(t)) {
          if (x['run_id'] == r.id) data.remove(t, x['id'] as String);
        }
      }
      data.remove('study_run', r.id);
    });
    unlocked.remove(r.id);
  }

  /// Every run's answer to the same printed question blank (by [slotKey]), oldest run first.
  List<(StudyRun, Answer)> history(StudyBook b, String slotKey) {
    final runs = {for (final r in runsOf(b)) r.id: r};
    final out = <(StudyRun, Answer)>[
      for (final x in data.records('answer'))
        if (x['slot_key'] == slotKey && runs.containsKey(x['run_id'])) (runs[x['run_id']]!, Answer(x)),
    ]..sort((a, c) => a.$1.ordinal.compareTo(c.$1.ordinal));
    return out;
  }

  /// All runs' answers of a book, grouped by question blank in reading order (page, then place), for comparing how
  /// each answer changed. Each group: the question, its first place, and the answers by run (oldest first).
  List<({String slotKey, String context, int page, double y, double x, List<(StudyRun, Answer)> answers})> questions(
    StudyBook b,
  ) {
    final runs = {for (final r in runsOf(b)) r.id: r};
    final groups = <String, List<(StudyRun, Answer)>>{};
    for (final x in data.records('answer')) {
      final r = runs[x['run_id']];
      if (r == null) continue;
      final a = Answer(x);
      (groups[a.slotKey] ??= []).add((r, a));
    }
    final out = [
      for (final MapEntry(key: key, value: list) in groups.entries)
        (
          slotKey: key,
          context: list.map((e) => e.$2.context).firstWhere((c) => c.isNotEmpty, orElse: () => ''),
          page: list.first.$2.page,
          y: list.first.$2.place.y,
          x: list.first.$2.place.x,
          answers: list..sort((a, c) => a.$1.ordinal.compareTo(c.$1.ordinal)),
        ),
    ];
    out.sort(
      (a, c) => a.page != c.page ? a.page.compareTo(c.page) : (a.y != c.y ? a.y.compareTo(c.y) : a.x.compareTo(c.x)),
    );
    return out;
  }

  // ----- highlights -----

  List<DocHighlight> highlights(String runId) => [
    for (final r in data.records('doc_highlight'))
      if (r['run_id'] == runId) DocHighlight(r),
  ]..sort((a, b) => _cmp(a.order, b.order));

  static int _cmp((int, double, double) a, (int, double, double) b) =>
      a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3));

  /// Highlights characters [start]..[end] of [page]: the words, a little text either side (to find them again in
  /// another edition) and their boxes. Highlights of this run on the same page that overlap it are replaced (one
  /// colour per word), as in the rest of the app.
  DocHighlight? addHighlight(
    String runId,
    String docId,
    PageData page,
    int start,
    int end, {
    required String color,
    String? note,
  }) {
    _open(runId);
    start = start.clamp(0, page.text.length);
    end = end.clamp(0, page.text.length);
    if (start > end) (start, end) = (end, start);
    while (start < end && page.text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && page.text[end - 1].trim().isEmpty) {
      end--;
    }
    if (start >= end) return null;
    final boxes = page.boxesFor(start, end);
    if (boxes.isEmpty) return null;
    final id = uuidV7(_now());
    data.batch(() {
      for (final h in highlights(runId)) {
        if (h.docId == docId &&
            h.page == page.number &&
            h.charStart != null &&
            h.charEnd != null &&
            h.charStart! < end &&
            start < h.charEnd!) {
          data.remove('doc_highlight', h.id);
        }
      }
      data.put('doc_highlight', id, {
        'run_id': runId,
        'doc_id': docId,
        'page': page.number,
        'rects': jsonEncode([for (final b in boxes) b.toJson()]),
        'char_start': start,
        'char_end': end,
        'quote': page.text.substring(start, end),
        'prefix': page.text.substring((start - 32).clamp(0, start), start),
        'suffix': page.text.substring(end, (end + 32).clamp(end, page.text.length)),
        'color': studyColors.contains(color) ? color : studyColors.first,
        'note': _clean(note),
      });
    });
    return DocHighlight(data.record('doc_highlight', id)!);
  }

  void updateHighlight(DocHighlight h, {String? color, String? note, bool clearNote = false}) {
    _open(h.runId);
    final r = Map<String, Object?>.of(data.record('doc_highlight', h.id) ?? const {});
    if (r.isEmpty) return;
    if (color != null && studyColors.contains(color)) r['color'] = color;
    if (clearNote) {
      r['note'] = null;
    } else if (note != null) {
      r['note'] = _clean(note);
    }
    data.put('doc_highlight', h.id, r);
  }

  void removeHighlight(DocHighlight h) {
    _open(h.runId);
    data.remove('doc_highlight', h.id);
  }

  // ----- bookmarks -----

  List<DocBookmark> bookmarks(String runId) => [
    for (final r in data.records('doc_bookmark'))
      if (r['run_id'] == runId) DocBookmark(r),
  ]..sort((a, b) => a.page != b.page ? a.page.compareTo(b.page) : a.y.compareTo(b.y));

  DocBookmark? bookmarkOn(String runId, String docId, int page) =>
      bookmarks(runId).where((b) => b.docId == docId && b.page == page).firstOrNull;

  DocBookmark addBookmark(String runId, String docId, int page, String name, {double y = 0}) {
    _open(runId);
    final id = uuidV7(_now());
    data.put('doc_bookmark', id, {'run_id': runId, 'doc_id': docId, 'page': page, 'y': y, 'name': name.trim()});
    return DocBookmark(data.record('doc_bookmark', id)!);
  }

  void renameBookmark(DocBookmark b, String name) {
    _open(b.runId);
    final r = Map.of(data.record('doc_bookmark', b.id)!);
    r['name'] = name.trim();
    data.put('doc_bookmark', b.id, r);
  }

  void removeBookmark(DocBookmark b) {
    _open(b.runId);
    data.remove('doc_bookmark', b.id);
  }

  // ----- answers -----

  List<Answer> answers(String runId) =>
      [
        for (final r in data.records('answer'))
          if (r['run_id'] == runId) Answer(r),
      ]..sort(
        (a, b) => a.page != b.page
            ? a.page.compareTo(b.page)
            : (a.place.y != b.place.y ? a.place.y.compareTo(b.place.y) : a.place.x.compareTo(b.place.x)),
      );

  /// Writes the answer at [place] in this run; empty text removes it. [context] is the printed question and [ordinal]
  /// which of its blanks this is (for comparing answers across runs and editions).
  Answer? putAnswer(
    String runId,
    String docId,
    AnswerPlace place,
    String text, {
    String context = '',
    int ordinal = 0,
  }) {
    _open(runId);
    // The record already at this place (one moved here from another edition keeps the id it was made with).
    final key = place.key(docId);
    final existing = answers(runId).where((a) => a.docId == docId && a.place.key(docId) == key).firstOrNull;
    final id = existing?.id ?? uuidV5('answer:$runId:$key');
    final clean = text.length > studyTextLimit ? text.substring(0, studyTextLimit) : text;
    if (clean.trim().isEmpty) {
      data.remove('answer', id);
      return null;
    }
    data.put('answer', id, {
      'run_id': runId,
      'doc_id': docId,
      'page': place.page,
      'kind': place.kind,
      'x': place.x,
      'y': place.y,
      'w': place.w,
      'h': place.h,
      'pitch': place.pitch,
      'lines': place.lines,
      'indent': place.indent,
      'size': place.size,
      'context': context,
      'slot_key': slotKey(context, ordinal, fallback: place.key(docId)),
      'text': clean,
    });
    return Answer(data.record('answer', id)!);
  }

  /// A new size for an answer's text (Ctrl+= / Ctrl+-), within 6–24 pt.
  void resizeAnswer(Answer a, double size) {
    _open(a.runId);
    final r = Map.of(data.record('answer', a.id)!);
    r['size'] = (size.clamp(6, 24) * 10).round() / 10;
    data.put('answer', a.id, r);
  }

  /// Moves or resizes an answer box placed by hand (lines don't move).
  void moveAnswerBox(Answer a, {required double x, required double y, required double w, required double h}) {
    _open(a.runId);
    if (a.place.kind != 'box') return;
    final r = Map.of(data.record('answer', a.id)!);
    r.addAll({'x': x, 'y': y, 'w': w, 'h': h});
    // The id stays the one it was made with, so moving a box keeps its history.
    data.put('answer', a.id, r);
  }

  // ----- book notes -----

  List<DocNote> notes(String runId) => [
    for (final r in data.records('doc_note'))
      if (r['run_id'] == runId) DocNote(r),
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  DocNote? addNote(StudyBook b, String runId, String text) {
    _open(runId);
    final clean = _clean(text);
    if (clean == null) return null;
    final id = uuidV7(_now());
    data.put('doc_note', id, {'book_id': b.id, 'run_id': runId, 'text': clean});
    return DocNote(data.record('doc_note', id)!);
  }

  /// Changes a note's text; empty removes it.
  void updateNote(DocNote n, String text) {
    _open(n.runId);
    final clean = _clean(text);
    if (clean == null) {
      data.remove('doc_note', n.id);
      return;
    }
    data.put('doc_note', n.id, {'book_id': n.bookId, 'run_id': n.runId, 'text': clean});
  }

  void removeNote(DocNote n) {
    _open(n.runId);
    data.remove('doc_note', n.id);
  }

  // ----- where reading stopped -----

  static String viewId(String runId) => uuidV5('view:$runId');

  DocView? view(String runId) {
    final r = data.record('doc_view', viewId(runId));
    if (r == null) return null;
    return DocView(
      page: r['page'] as int? ?? 1,
      offset: (r['offset'] as num?)?.toDouble() ?? 0,
      zoom: (r['zoom'] as num?)?.toDouble() ?? 1,
    );
  }

  /// Remembers the page (1-based), how far down it ([offset], 0–1) and the zoom. Kept even for a locked run: reading
  /// an old run is not changing it.
  void saveView(String runId, String docId, DocView v) => data.put('doc_view', uuidV5('view:$runId'), {
    'run_id': runId,
    'doc_id': docId,
    'page': v.page,
    'offset': (v.offset * 1000).round() / 1000,
    'zoom': (v.zoom * 100).round() / 100,
  });

  /// Counts for the library row.
  ({int highlights, int notes, int answers, int bookmarks}) counts(String runId) => (
    highlights: highlights(runId).length,
    notes: highlights(runId).where((h) => h.note != null).length + notes(runId).length,
    answers: answers(runId).length,
    bookmarks: bookmarks(runId).length,
  );

  static String? _clean(String? text) {
    final t = text?.trim();
    if (t == null || t.isEmpty) return null;
    return t.length > studyTextLimit ? t.substring(0, studyTextLimit) : t;
  }
}
