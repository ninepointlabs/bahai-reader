// Moving a book to another edition: test/fixtures/worksheet.pdf → worksheet-2.pdf (a paragraph added at the top).
import 'dart:io';

import 'package:bahai_reader/core/study/page_data.dart';
import 'package:bahai_reader/core/study/rules.dart';
import 'package:bahai_reader/core/study/study_controller.dart';
import 'package:bahai_reader/core/study/study_store.dart';
import 'package:bahai_reader/core/userdata/userdata_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'helpers/temp.dart';

void answerOn(StudyController study, PageData p, int i, String text, int ordinal) {
  final r = p.rules[i];
  final slot = slotFrom(p.rules, i, p.fontSize);
  study.startAnswer(
    AnswerEdit(
      place: AnswerPlace(
        page: p.number,
        kind: 'line',
        x: slot.x,
        y: slot.y,
        w: slot.w,
        pitch: slot.pitch,
        lines: slot.lines,
        indent: slot.indent,
        size: slot.size,
      ),
      context: p.contextAt(r.x + 5, r.y),
      ordinal: ordinal,
    ),
  );
  study.finishAnswer(text);
}

void main() {
  late Directory dir;
  late UserDataStore data;
  late StudyController study;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('br-pdfrx-').path;
    await pdfrxFlutterInitialize();
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('br-carry-');
    data = UserDataStore.open(File('${dir.path}/settings.json'));
    study = StudyController(StudyStore(data), Directory('${dir.path}/books'));
  });
  tearDown(() async {
    await study.close(notify: false);
    data.close();
    removeTemp(dir);
  });

  test('every run\'s marks move to the new edition; what is not found waits to be placed', () async {
    final one = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final two = File('test/fixtures/worksheet-2.pdf').readAsBytesSync();
    final (book, _) = await study.importBytes(one, 'Workbook_2.1.1_20210325.pdf');
    await study.open(book);
    final p1 = (await study.pageData(1))!, p2 = (await study.pageData(2))!;
    final at = p1.text.indexOf('talk about what it');
    final h = study.highlight(p1, at, at + 'talk about what it'.length, color: 'green', note: 'Key')!;
    answerOn(study, p1, 0, 'week', 0);
    answerOn(study, p1, 1, 'reflect', 1);
    answerOn(study, p1, 2, 'We read and talk.', 0);
    study.toggleBookmark(2); // named "Section 2: Looking back"
    // An answer whose question this edition doesn't have: it will wait to be placed.
    study.store.putAnswer(
      study.run!.id,
      book.docId,
      const AnswerPlace(page: 2, kind: 'line', x: 72, y: 700, w: 100),
      'orphan',
      context: '9. A question the new edition left out.',
    );
    final first = study.run!;
    study.startNewRun();
    answerOn(study, p2, 0, 'patience and joy', 0);
    final oldQ1 = study.store.answers(first.id).firstWhere((a) => a.text == 'week');
    await study.close();

    final check = await study.prepare(two, 'Workbook_2.2.1_20210930.pdf');
    expect(check.same, isNull);
    expect(check.other?.id, book.id, reason: 'recognized by its name apart from versions and dates');
    final plan = await study.moveToEdition(book, check);
    expect((plan.highlights, plan.answers, plan.bookmarks), (1, 4, 1));
    expect((plan.lostHighlights, plan.lostAnswers), (0, 1));

    final moved = study.store.book(book.id)!;
    expect(moved.doc.sha256, check.file.sha256);
    expect(moved.doc.fileName, 'Workbook_2.2.1_20210930.pdf');
    await study.open(moved);
    study.viewRun(study.store.run(first.id)!);
    final hl = study.highlights.single;
    expect(hl.id, h.id, reason: 'the same mark, moved');
    expect(hl.note, 'Key');
    expect(hl.rects.first.y, greaterThan(h.rects.first.y + 20), reason: 'it moved down with the text');
    final newP1 = (await study.pageData(hl.page))!;
    expect(newP1.text.substring(hl.charStart!, hl.charEnd!).replaceAll(RegExp(r'\s+'), ' '), 'talk about what it');
    final q1 = study.answers.firstWhere((a) => a.text == 'week');
    expect(q1.id, oldQ1.id);
    expect(q1.slotKey, oldQ1.slotKey, reason: 'the same question in any edition');
    expect(q1.place.y, isNot(oldQ1.place.y));
    expect(newP1.contextAt(q1.place.x + 5, q1.place.y), oldQ1.context, reason: 'on the same question’s line');
    expect(
      study.answers.firstWhere((a) => a.text == 'reflect').place.x,
      greaterThan(q1.place.x),
      reason: 'second blank',
    );
    expect(study.bookmarks.single.name, 'Section 2: Looking back');
    expect(study.outline.firstWhere((e) => e.title == 'Section 2: Looking back').page, study.bookmarks.single.page);

    // The orphan is listed, not drawn; placing it puts it on a line with this edition's question.
    final u = study.unplaced;
    expect([for (final a in u.answers) a.text], ['orphan']);
    expect(study.answers.where((a) => a.text == 'orphan'), isEmpty);
    study.unlockRun();
    study.startPlacing(u.answers.single);
    final p = (await study.pageData(2))!;
    final slot = slotFrom(p.rules, p.rules.length - 1, p.fontSize);
    study.place(
      AnswerPlace(page: 2, kind: 'line', x: slot.x, y: slot.y, w: slot.w),
      context: 'placed by hand',
    );
    expect(study.unplaced.answers, isEmpty);
    expect(study.answers.where((a) => a.text == 'orphan').single.page, 2);

    // The second time through moved too.
    study.backToCurrent();
    expect(study.answers.single.text, 'patience and joy');
    expect(study.answers.single.docId, moved.docId);
    // Importing the old edition again offers the move back; "not the same book" stops that.
    final again = await study.prepare(one, 'Workbook_2.1.1_20210325.pdf');
    expect(again.other?.id, book.id);
    final (separate, _) = study.add(again, notSameAs: again.other);
    expect(separate.id, isNot(book.id));
    expect((await study.prepare(one, 'Workbook_2.1.1_20210325.pdf')).same?.id, separate.id);
  });
}
