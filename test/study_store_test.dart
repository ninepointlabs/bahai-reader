import 'dart:io';
import 'dart:typed_data';

import 'package:bahai_reader/core/study/export.dart';
import 'package:bahai_reader/core/study/importer.dart';
import 'package:bahai_reader/core/study/page_data.dart';
import 'package:bahai_reader/core/study/study_search.dart';
import 'package:bahai_reader/core/study/study_store.dart';
import 'package:bahai_reader/core/userdata/ids.dart';
import 'package:bahai_reader/core/userdata/userdata_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'helpers/temp.dart';

/// A page with one line of text per entry, 10 pt characters 6 pt wide, lines 20 pt apart from y = 100.
PageData page(List<String> lines, {int number = 1}) {
  final text = lines.join('\n');
  final chars = <Box>[];
  var row = 0, col = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') {
      chars.add(const Box(0, 0, 0, 0));
      row++;
      col = 0;
      continue;
    }
    chars.add(Box(72.0 + col * 6, 100.0 + row * 20, 6, 10));
    col++;
  }
  return PageData.build(number: number, width: 612, height: 792, text: text, chars: chars);
}

void main() {
  late Directory dir;
  late UserDataStore data;
  late StudyStore study;
  final now = DateTime(2026, 11, 20, 18);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('br-study-');
    data = UserDataStore.open(File('${dir.path}/settings.json'));
    study = StudyStore(data, now: () => now);
  });
  tearDown(() {
    data.close();
    removeTemp(dir);
  });

  StudyBook addBook([String sha = 'aa11']) =>
      study.addBook(sha256: sha, fileName: 'Workbook_2.2.1.pdf', byteSize: 1000, pageCount: 2).$1;

  test('a new book has its first run; the same file again is the same book, and a removed one comes back', () {
    final (b, isNew) = study.addBook(sha256: 'aa11', fileName: 'Workbook_2.2.1.pdf', byteSize: 1000, pageCount: 2);
    expect(isNew, isTrue);
    expect(b.name, 'Workbook_2.2.1', reason: 'no label or title: the file name');
    expect(b.id, uuidV5('book:aa11'), reason: 'the same id on every device');
    final run = study.currentRun(b);
    expect((run.ordinal, run.name, run.locked), (1, '1st time, Nov 2026', false));
    expect(study.addBook(sha256: 'aa11', fileName: 'other.pdf', byteSize: 1000, pageCount: 2).$2, isFalse);
    study.rename(b, '  Book 1  ');
    expect(study.book(b.id)!.name, 'Book 1');
    study.remove(study.book(b.id)!);
    expect(study.books, isEmpty);
    expect(study.removed.single.id, b.id);
    final (back, again) = study.addBook(sha256: 'aa11', fileName: 'x.pdf', byteSize: 1000, pageCount: 2);
    expect((again, back.removedAt, back.name), (false, null, 'Book 1'));
    expect(ordinalWord(2), '2nd');
    expect(ordinalWord(13), '13th');
    expect(ordinalWord(22), '22nd');
  });

  test(
    'highlights: words and their boxes; an overlapping one replaces; colour and note change; removal is a tombstone',
    () {
      final b = addBook();
      final run = study.currentRun(b).id;
      final p = page(['The group meets every week', 'to read and talk together.']);
      final h = study.addHighlight(run, b.docId, p, 4, 18, color: 'green', note: '  First  ')!;
      expect((h.quote, h.note, h.color, h.page), ('group meets ev', 'First', 'green', 1));
      expect(h.rects.single, const Box(96, 100, 84, 10));
      expect(h.prefix, 'The ');
      // Across a line break: one box per line.
      final two = study.addHighlight(run, b.docId, p, 22, 33, color: 'blue')!;
      expect(two.rects, hasLength(2));
      // Overlaps the first: replaces it.
      study.addHighlight(run, b.docId, p, 10, 14, color: 'pink');
      expect([for (final x in study.highlights(run)) x.color], ['pink', 'blue']);
      final pink = study.highlights(run).first;
      study.updateHighlight(pink, color: 'purple', note: 'Why?');
      expect((study.highlights(run).first.color, study.highlights(run).first.note), ('purple', 'Why?'));
      study.updateHighlight(study.highlights(run).first, clearNote: true);
      expect(study.highlights(run).first.note, isNull);
      study.removeHighlight(study.highlights(run).first);
      expect(study.highlights(run), hasLength(1));
      expect(data.syncInfo('doc_highlight', pink.id)!['deleted_at'], isNotNull);
      expect(study.addHighlight(run, b.docId, p, 3, 4, color: 'yellow'), isNull, reason: 'only a space');
    },
  );

  test('answers: one per place and run; empty text removes it; the same question has the same key anywhere', () {
    final b = addBook();
    final run = study.currentRun(b).id;
    const line = AnswerPlace(page: 1, kind: 'line', x: 100, y: 200, w: 150);
    final a = study.putAnswer(run, b.docId, line, 'week', context: '1. Meets every ___ to ___.', ordinal: 0)!;
    final again = study.putAnswer(run, b.docId, line, 'Sunday', context: '1. Meets every ___ to ___.', ordinal: 0)!;
    expect(again.id, a.id);
    expect(study.answers(run).single.text, 'Sunday');
    // The same question in another edition, somewhere else on the page.
    final key = slotKey('1.  Meets EVERY ___ to ___!', 0, fallback: 'x');
    expect(key, a.slotKey);
    expect(slotKey('1. Meets every ___ to ___.', 1, fallback: 'x'), isNot(a.slotKey), reason: 'its second blank');
    study.resizeAnswer(study.answers(run).single, 30);
    expect(study.answers(run).single.place.size, 24);
    study.putAnswer(run, b.docId, line, '   ');
    expect(study.answers(run), isEmpty);
    // A box placed by hand.
    const box = AnswerPlace(page: 2, kind: 'box', x: 80, y: 300, w: 200, h: 60);
    final boxed = study.putAnswer(run, b.docId, box, 'A thought')!;
    expect(boxed.slotKey, startsWith('at:'), reason: 'no printed question near it');
    study.moveAnswerBox(boxed, x: 90, y: 310, w: 180, h: 80);
    expect((study.answers(run).single.place.x, study.answers(run).single.id), (90.0, boxed.id));
  });

  test('bookmarks, book notes and the place reached', () {
    final b = addBook();
    final run = study.currentRun(b).id;
    final bm = study.addBookmark(run, b.docId, 2, ' Section 2 ');
    expect(study.bookmarkOn(run, b.docId, 2)!.name, 'Section 2');
    study.renameBookmark(bm, 'Looking back');
    expect(study.bookmarks(run).single.name, 'Looking back');
    study.removeBookmark(bm);
    expect(study.bookmarks(run), isEmpty);
    final n = study.addNote(b, run, 'Bring the workbook')!;
    expect(study.addNote(b, run, '  '), isNull);
    study.updateNote(n, 'Bring the workbook and a pen');
    expect(study.notes(run).single.text, 'Bring the workbook and a pen');
    study.updateNote(study.notes(run).single, '');
    expect(study.notes(run), isEmpty);
    expect(study.view(run), isNull);
    study.saveView(run, b.docId, const DocView(page: 2, offset: 0.3333, zoom: 1.256));
    expect((study.view(run)!.page, study.view(run)!.offset, study.view(run)!.zoom), (2, 0.333, 1.26));
    expect(study.counts(run), (highlights: 0, notes: 0, answers: 0, bookmarks: 0));
  });

  test('a locked run cannot be changed, but its place is still remembered', () {
    final b = addBook();
    final run = study.currentRun(b);
    final p = page(['Some words here']);
    study.addHighlight(run.id, b.docId, p, 0, 4, color: 'yellow');
    data.put('study_run', run.id, {...data.record('study_run', run.id)!, 'locked': 1});
    expect(() => study.addHighlight(run.id, b.docId, p, 5, 10, color: 'yellow'), throwsA(isA<RunLocked>()));
    expect(() => study.removeHighlight(study.highlights(run.id).single), throwsA(isA<RunLocked>()));
    expect(
      () => study.putAnswer(run.id, b.docId, const AnswerPlace(page: 1, kind: 'box', x: 0, y: 0, w: 9), 'x'),
      throwsA(isA<RunLocked>()),
    );
    expect(() => study.addNote(b, run.id, 'x'), throwsA(isA<RunLocked>()));
    expect(() => study.addBookmark(run.id, b.docId, 1, 'x'), throwsA(isA<RunLocked>()));
    study.saveView(run.id, b.docId, const DocView(page: 1));
    expect(study.highlights(run.id), hasLength(1));
  });

  test('deleting a removed book for good takes its marks and gives back its file', () {
    final b = addBook();
    final run = study.currentRun(b).id;
    study.addHighlight(run, b.docId, page(['Some words']), 0, 4, color: 'yellow');
    study.addNote(b, run, 'note');
    study.remove(b);
    expect(study.deleteForever(study.book(b.id)!), 'aa11');
    expect([study.books, study.removed, study.highlights(run), study.notes(run)], everyElement(isEmpty));
    expect(data.records('study_run'), isEmpty);
  });

  test('a schema-1 store is upgraded: magenta highlights become pink', () {
    data.close();
    final db = sqlite3.open('${dir.path}/userdata.sqlite');
    db.execute(
      "INSERT INTO passage_highlight (id, created_at, updated_at, hlc, device_id, passage_id, start, \"end\", words, "
      "color, sort) VALUES ('h1', 1, 1, '0-0-d', 'd', 'hidden:2', 0, 3, 'O S', 'magenta', 1)",
    );
    db.execute(
      "INSERT INTO user_pref (id, created_at, updated_at, hlc, device_id, key, value) "
      "VALUES ('p1', 1, 1, '0-0-d', 'd', 'highlight_color', '\"magenta\"')",
    );
    db.execute('PRAGMA user_version = 1');
    db.close();
    data = UserDataStore.open(File('${dir.path}/settings.json'));
    final json = data.toJson();
    expect(((json['highlights'] as List).single as Map)['color'], 'pink');
    expect(json['highlight_color'], 'pink');
    expect(data.syncInfo('passage_highlight', 'h1')!['updated_at'], greaterThan(1));
    final v = sqlite3.open('${dir.path}/userdata.sqlite');
    expect(v.select('PRAGMA user_version').first.values.first, userDataSchema);
    v.close();
  });

  group('runs', () {
    test('a new time through starts empty, finishes and locks the last one, and leaves it as it was', () {
      final b = addBook();
      final first = study.currentRun(b);
      final p = page(['The group meets every week']);
      study.addHighlight(first.id, b.docId, p, 0, 9, color: 'green');
      const line = AnswerPlace(page: 1, kind: 'line', x: 100, y: 200, w: 150);
      study.putAnswer(first.id, b.docId, line, 'week', context: '1. Meets every ___.');
      study.addNote(b, first.id, 'First notes');
      study.addBookmark(first.id, b.docId, 1, 'Start');

      final second = study.startRun(study.book(b.id)!);
      expect((second.ordinal, second.name, second.locked), (2, '2nd time, Nov 2026', false));
      expect(study.currentRun(study.book(b.id)!).id, second.id);
      final done = study.run(first.id)!;
      expect((done.locked, done.finishedAt), (true, now.millisecondsSinceEpoch));
      expect(study.counts(second.id), (highlights: 0, notes: 0, answers: 0, bookmarks: 0), reason: 'starts empty');
      expect(study.counts(first.id), (highlights: 1, notes: 1, answers: 1, bookmarks: 1), reason: 'never overwritten');
      expect(() => study.addNote(b, first.id, 'late'), throwsA(isA<RunLocked>()));

      // Unlocked for this session only.
      study.unlocked.add(first.id);
      study.addNote(b, first.id, 'An afterthought');
      expect(study.run(first.id)!.locked, isTrue, reason: 'still locked in the store');
      study.unlocked.clear();
      expect(() => study.addNote(b, first.id, 'x'), throwsA(isA<RunLocked>()));

      study.renameRun(study.run(first.id)!, '  Autumn circle  ');
      expect(study.run(first.id)!.name, 'Autumn circle', reason: 'naming a locked run changes no marks');
      final third = study.startRun(study.book(b.id)!, name: 'Tutor training');
      expect((third.ordinal, third.name), (3, 'Tutor training'));
      expect(study.run(second.id)!.locked, isTrue);
      expect([for (final r in study.runsOf(study.book(b.id)!)) r.ordinal], [1, 2, 3]);
    });

    test('one question\'s answers across runs, oldest first, and all questions in reading order', () {
      final b = addBook();
      final first = study.currentRun(b);
      const q1 = AnswerPlace(page: 1, kind: 'line', x: 100, y: 200, w: 150);
      const q2 = AnswerPlace(page: 1, kind: 'line', x: 100, y: 120, w: 150);
      study.putAnswer(first.id, b.docId, q1, 'week', context: '1. Meets every ___.');
      study.putAnswer(first.id, b.docId, q2, 'reading', context: '0. What do we do?');
      final second = study.startRun(study.book(b.id)!);
      final a2 = study.putAnswer(second.id, b.docId, q1, 'Sunday', context: '1. Meets every ___.')!;
      final h = study.history(study.book(b.id)!, a2.slotKey);
      expect([for (final (r, a) in h) '${r.ordinal}:${a.text}'], ['1:week', '2:Sunday']);
      final qs = study.questions(study.book(b.id)!);
      expect([for (final q in qs) q.context], ['0. What do we do?', '1. Meets every ___.'], reason: 'top to bottom');
      expect(
        [for (final (r, a) in qs.last.answers) '${r.name}: ${a.text}'],
        ['1st time, Nov 2026: week', '2nd time, Nov 2026: Sunday'],
      );
      final md = renderAllRunsMarkdown(
        book: study.book(b.id)!,
        runs: [
          for (final r in study.runsOf(study.book(b.id)!))
            (run: r, highlights: study.highlights(r.id), answers: study.answers(r.id), notes: study.notes(r.id)),
        ],
        exportedAt: DateTime(2026, 11, 20, 19),
      );
      expect(
        md,
        contains(
          '**Q:** 1. Meets every ___.  \n**A (1st time, Nov 2026):** week  \n**A (2nd time, Nov 2026):** Sunday  \n',
        ),
      );
      expect(md.indexOf('0. What do we do?'), lessThan(md.indexOf('1. Meets every')));
      expect(allRunsFileName(study.book(b.id)!), 'Workbook_2.2.1 — all runs.md');

      // An earlier run can be deleted with its marks; the current one cannot.
      expect(() => study.deleteRun(study.book(b.id)!, second), throwsStateError);
      study.deleteRun(study.book(b.id)!, first);
      expect(study.runsOf(study.book(b.id)!).map((r) => r.ordinal), [2]);
      expect(study.answers(first.id), isEmpty);
    });
  });

  group('library', () {
    test('categories: one per name, a book in several, rename merges, delete keeps the books', () {
      final a = addBook('aa11'), b = addBook('bb22');
      final one = study.category('  Book   1 ');
      expect(one.name, 'Book 1');
      expect(study.category('book 1').id, one.id, reason: 'any case: the same category');
      expect(one.id, uuidV5('category:book 1'), reason: 'two devices make the same one');
      final tutor = study.category('Tutor training');
      study.setCategories(a, [one, tutor]);
      study.setCategories(b, [tutor]);
      expect([for (final c in study.categoriesOf(a)) c.name], ['Book 1', 'Tutor training']);
      study.setCategories(a, [one]);
      expect([for (final c in study.categoriesOf(a)) c.name], ['Book 1']);
      // Renaming onto another category's name merges the two.
      study.renameCategory(one, 'tutor TRAINING');
      expect([for (final c in study.categories) c.name], ['Tutor training']);
      expect([for (final c in study.categoriesOf(a)) c.name], ['Tutor training']);
      study.renameCategory(study.categories.single, 'Ruhi Book 5');
      expect(study.categoriesOf(b).single.name, 'Ruhi Book 5');
      study.deleteCategory(study.categories.single);
      expect([study.categories, study.categoriesOf(a)], everyElement(isEmpty));
      expect(study.books, hasLength(2));
      expect(obsidianTags(['Ruhi Book 5', ' Tutor training! ', '2026', 'ruhi book 5']), [
        'ruhi-book-5',
        'tutor-training',
      ]);
    });

    test('sorting by recent, title, most marked and added; search ignores accents', () {
      var t = DateTime(2026, 11, 20, 18);
      study = StudyStore(data, now: () => t);
      final a = study.addBook(sha256: 'aa11', fileName: 'Zeta.pdf', byteSize: 1, pageCount: 1).$1;
      t = t.add(const Duration(minutes: 1));
      final b = study.addBook(sha256: 'bb22', fileName: 'Alpha.pdf', byteSize: 1, pageCount: 1).$1;
      data.clock = () => DateTime(2026, 11, 21).millisecondsSinceEpoch;
      study.saveView(study.currentRun(a).id, a.docId, const DocView(page: 1));
      study.addNote(a, study.currentRun(a).id, 'Bahá’u’lláh’s words on service');
      List<String> names(StudySort s) => [for (final x in sortBooks(study, study.books, s)) x.name];
      expect(names(StudySort.recent), ['Zeta', 'Alpha'], reason: 'Zeta was read since Alpha was added');
      expect(names(StudySort.title), ['Alpha', 'Zeta']);
      expect(names(StudySort.marked), ['Zeta', 'Alpha']);
      expect(names(StudySort.added), ['Alpha', 'Zeta']);
      final p = page(['The group meets every week']);
      study.addHighlight(study.currentRun(b).id, b.docId, p, 4, 9, color: 'blue', note: 'Who?');
      String fold(String s) => s.toLowerCase().replaceAll('á', 'a').replaceAll(RegExp("[’']"), '');
      final hits = searchMarks(study, 'bahaullahs', fold: fold);
      expect([for (final h in hits) (h.book.name, h.kind)], [('Zeta', 'note')]);
      expect([for (final h in searchMarks(study, 'WHO', fold: fold)) h.text], ['group']);
      expect(searchMarks(study, '', fold: fold), isEmpty);
      expect(searchMarks(study, '', all: true), hasLength(2));
    });
  });

  group('import', () {
    test('a PDF is copied once into books/ by its hash; anything else is refused', () async {
      final books = Directory('${dir.path}/books');
      final src = File('test/fixtures/worksheet.pdf');
      final before = src.statSync().modified;
      final a = await importPdfFile(src, books);
      expect(a.copy.path, '${books.path}/${a.sha256}.pdf');
      expect(a.copy.readAsBytesSync(), src.readAsBytesSync());
      expect(a.fileName, 'worksheet.pdf');
      expect(a.sha256, hasLength(64));
      final b = await importPdfFile(src, books);
      expect(b.sha256, a.sha256);
      expect(books.listSync(), hasLength(1));
      expect(src.statSync().modified, before, reason: 'the original is only read');
      await expectLater(
        importPdfBytes(Uint8List.fromList('hello'.codeUnits), 'notes.txt', books),
        throwsA(isA<ImportProblem>().having((e) => e.message, 'message', contains('not a PDF'))),
      );
      expect(pdfDocIdOf(Uint8List.fromList('trailer << /ID [<ab12> <cd34>] >>'.codeUnits)), 'AB12');
    });
  });

  group('export', () {
    test('notes first, then each page with its bookmarks, highlights and answers in reading order', () async {
      final b = addBook();
      final run = study.currentRun(b);
      final p = page(['The group meets every week', 'to read and talk together.']);
      study.addNote(b, run.id, 'Bring the workbook.');
      study.addHighlight(run.id, b.docId, p, 4, 9, color: 'green', note: 'Key point');
      study.addBookmark(run.id, b.docId, 1, 'Section 1');
      study.putAnswer(
        run.id,
        b.docId,
        const AnswerPlace(page: 1, kind: 'line', x: 72, y: 300, w: 100),
        'week',
        context: '1. Meets every ___ to read and ___.',
      );
      study.putAnswer(
        run.id,
        b.docId,
        const AnswerPlace(page: 1, kind: 'line', x: 250, y: 300, w: 100),
        'talk',
        context: '1. Meets every ___ to read and ___.',
        ordinal: 1,
      );
      final md = renderMarkdown(
        book: study.book(b.id)!,
        run: run,
        highlights: study.highlights(run.id),
        bookmarks: study.bookmarks(run.id),
        answers: study.answers(run.id),
        notes: study.notes(run.id),
        pageLabel: (n) => n == 1 ? 'i' : '',
        exportedAt: DateTime(2026, 11, 20, 18, 30),
      );
      // Line ends with two spaces (Markdown line breaks) are shown as | here.
      expect(md.replaceAll('  \n', '|\n'), '''---
title: "Workbook_2.2.1"
run: "1st time, Nov 2026"
file: "Workbook_2.2.1.pdf"
sha256: aa11
generator: bahai-reader
exported: 2026-11-20T18:30:00
highlights: 1
bookmarks: 1
answers: 2
tags: [bahai-reader, study]
---

# Workbook_2.2.1

*1st time, Nov 2026. Exported from Bahá’í Reader; this file is made again on every export, so keep your own edits elsewhere.*

## Notes

Bring the workbook.

## Page 1 (i)

- **Bookmark:** Section 1

> group
> — p. 1 · green

Key point

**Q:** 1. Meets every ___ to read and ___.|
**A:** week|
**A:** talk|
''');
      final folder = Directory('${dir.path}/Notes');
      final first = await exportMarkdown(folder, md, study.book(b.id)!, run);
      expect(first.path, endsWith('Workbook_2.2.1 — 1st time, Nov 2026.md'));
      final second = await exportMarkdown(folder, md, study.book(b.id)!, run);
      expect(second.path, first.path, reason: 'its own export is replaced');
      first.writeAsStringSync('My own notes');
      final third = await exportMarkdown(folder, md, study.book(b.id)!, run);
      expect(third.path, isNot(first.path), reason: 'a file it did not write is never overwritten');
      expect(first.readAsStringSync(), 'My own notes');
    });
  });
}
