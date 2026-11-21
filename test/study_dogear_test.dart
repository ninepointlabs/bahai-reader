// Bringing in Dogear's marks: the same file, and another edition of it (worksheet.pdf → worksheet-2.pdf).
import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/study/page_data.dart';
import 'package:bahai_reader/core/study/study_controller.dart';
import 'package:bahai_reader/core/study/study_store.dart';
import 'package:bahai_reader/core/userdata/userdata_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'helpers/temp.dart';

void main() {
  late Directory dir, dogear;
  late UserDataStore data;
  late StudyController study;
  late Map<String, Object?> annotation;
  final one = File('test/fixtures/worksheet.pdf').readAsBytesSync();
  final two = File('test/fixtures/worksheet-2.pdf').readAsBytesSync();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('br-pdfrx-').path;
    await pdfrxFlutterInitialize();
    // A Dogear annotation file for worksheet.pdf, as Dogear writes it (0-based pages, top-left points).
    final doc = await PdfDocument.openFile('test/fixtures/worksheet.pdf');
    final p1 = await PageData.load(doc.pages[0]);
    await doc.dispose();
    final at = p1.text.indexOf('talk about what it');
    final box = p1.boxesFor(at, at + 18).first;
    final q = p1.rules[0], r = p1.rules[1];
    annotation = {
      'dogear': 1,
      'sha256': sha256.convert(one).toString(),
      'file_name': 'Workbook_2.1.1_20210325.pdf',
      'title': '',
      'label': 'Book 1 (from Dogear)',
      'page_count': 2,
      'highlights': [
        {
          'id': 'h1',
          'page': 0,
          'rects': [
            [box.x, box.y, box.w, box.h],
          ],
          'text': 'talk about what it',
          'color': 'pink',
          'note': 'Key',
        },
      ],
      'bookmarks': [
        {'id': 'b1', 'page': 1, 'name': 'Section 2: Looking back', 'y': 0},
      ],
      'notes': [
        {'id': 'n1', 'text': 'Bring the workbook.'},
      ],
      'answers': [
        {
          'id': 'a1',
          'page': 0,
          'x': q.x,
          'y': q.y,
          'w': q.w,
          'pitch': 0,
          'lines': 1,
          'indent': 40,
          'size': 11,
          'text': 'week',
          'context': p1.contextAt(q.x + 5, q.y),
        },
        {
          'id': 'a2',
          'page': 0,
          'x': r.x,
          'y': r.y,
          'w': r.w,
          'pitch': 0,
          'lines': 1,
          'size': 11,
          'text': 'reflect',
          'context': p1.contextAt(r.x + 5, r.y),
        },
        {'id': 'a3', 'page': 1, 'x': 72, 'y': 700, 'w': 90, 'text': 'gone', 'context': '9. Not in any edition.'},
      ],
      'categories': ['Ruhi Book 1'],
    };
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('br-dogear-');
    dogear = Directory('${dir.path}/Dogear/.dogear/annotations')..createSync(recursive: true);
    File('${dogear.path}/${annotation['sha256']}.json').writeAsStringSync(jsonEncode(annotation));
    data = UserDataStore.open(File('${dir.path}/settings.json'));
    study = StudyController(StudyStore(data), Directory('${dir.path}/books'))
      ..dogearFolder = () => Directory('${dir.path}/Dogear');
  });
  tearDown(() async {
    await study.close(notify: false);
    data.close();
    removeTemp(dir);
  });

  test('the same file: marks keep their places and fill the empty first time through; Dogear is only read', () async {
    final before = File('${dogear.path}/${annotation['sha256']}.json').readAsStringSync();
    final (book, _) = await study.importBytes(one, 'Workbook_2.1.1_20210325.pdf');
    final d = study.dogearFor(book)!;
    expect(d.summary, '1 highlight, 3 answers, 1 bookmark and 1 note');
    final report = await study.bringInDogear(book, d);
    expect(
      (report.placed, report.unplaced, report.runName),
      (6, 0, '1st time, Nov 2026'.substring(0, 9) + report.runName.substring(9)),
    );
    final b = study.store.book(book.id)!;
    final run = study.store.currentRun(b);
    final h = study.store.highlights(run.id).single;
    expect((h.color, h.note, h.page), ('pink', 'Key', 1));
    expect(
      h.rects.single.x,
      closeTo(((annotation['highlights'] as List).single as Map)['rects'][0][0] as double, 0.01),
    );
    expect([for (final a in study.store.answers(run.id)) a.text]..sort(), ['gone', 'reflect', 'week']);
    final week = study.store.answers(run.id).firstWhere((a) => a.text == 'week');
    final reflect = study.store.answers(run.id).firstWhere((a) => a.text == 'reflect');
    expect(week.slotKey, isNot(reflect.slotKey), reason: 'the first and second blank of one question');
    expect((week.place.indent, reflect.place.indent), (40, 0), reason: "Dogear's indent is kept");
    expect(study.store.bookmarks(run.id).single.page, 2);
    expect(study.store.notes(run.id).single.text, 'Bring the workbook.');
    expect(b.name, 'Book 1 (from Dogear)');
    expect(study.store.categoriesOf(b).single.name, 'Ruhi Book 1');
    expect(study.dogearFor(b), isNull, reason: 'not offered again');
    expect(study.dogearFor(b, again: true), isNotNull, reason: 'but can be asked for');
    expect(File('${dogear.path}/${annotation['sha256']}.json').readAsStringSync(), before);
  });

  test('answers brought in by 1.1.0/1.1.1 without their indent get it back when the book opens', () async {
    final (book, _) = await study.importBytes(one, 'Workbook_2.1.1_20210325.pdf');
    await study.bringInDogear(book, study.dogearFor(book)!);
    final run = study.store.currentRun(study.store.book(book.id)!);
    final week = study.store.answers(run.id).firstWhere((a) => a.text == 'week');
    // As the earlier versions stored it.
    study.store.updateRecords([
      ('answer', week.id, {'indent': 0.0}),
    ]);
    expect(study.store.answers(run.id).firstWhere((a) => a.text == 'week').place.indent, 0);
    await study.open(study.store.book(book.id)!);
    final after = {for (final a in study.store.answers(run.id)) a.text: a};
    expect(after['week']!.place.indent, 40);
    expect(after['week']!.text, 'week');
    expect(after['reflect']!.place.indent, 0, reason: 'no indent in Dogear: untouched');
  });

  test(
    'another edition: found by their words and questions; a book with marks gets a "From Dogear" time through',
    () async {
      final (book, _) = await study.importBytes(two, 'Workbook_2.2.1_20210930.pdf');
      await study.open(book);
      final p = (await study.pageData(1))!;
      study.highlight(p, 0, 5, color: 'yellow');
      await study.close();
      final d = study.dogearFor(study.store.book(book.id)!)!;
      expect(d.fileName, 'Workbook_2.1.1_20210325.pdf');
      final report = await study.bringInDogear(study.store.book(book.id)!, d);
      expect((report.placed, report.unplaced, report.runName), (5, 1, 'From Dogear'));
      final b = study.store.book(book.id)!;
      final runs = study.store.runsOf(b);
      expect(
        [for (final r in runs) r.name],
        ['From Dogear', '1st time, Nov 2026'.substring(0, 9) + runs.last.name.substring(9)],
      );
      expect(study.store.currentRun(b).name, isNot('From Dogear'), reason: 'the current time through is unchanged');
      final from = runs.first;
      expect(from.locked, isTrue);
      final h = study.store.highlights(from.id).single;
      final page = (await () async {
        final doc = await PdfDocument.openFile(study.fileOf(b).path);
        final data = await PageData.load(doc.pages[h.page - 1], rules: false);
        await doc.dispose();
        return data;
      }());
      expect(page.text.substring(h.charStart!, h.charEnd!).replaceAll(RegExp(r'\s+'), ' '), 'talk about what it');
      expect(study.store.unplaced(b, from.id).answers.single.text, 'gone');
      expect(study.store.highlights(study.store.currentRun(b).id), hasLength(1), reason: 'nothing here changed');
    },
  );
}
