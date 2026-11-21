// Times through a book in the desktop window: a new run, an earlier one shown read-only (and unlocked), answers by
// question across runs, and comparing side by side.
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/core/study/page_data.dart';
import 'package:bahai_reader/core/study/rules.dart';
import 'package:bahai_reader/core/study/study_controller.dart';
import 'package:bahai_reader/core/study/study_store.dart';
import 'package:bahai_reader/features/study/study_reader.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'disk_bundle.dart';
import 'helpers/temp.dart';

void answer(StudyController study, PageData p, int i, String text) {
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
      ordinal: 0,
    ),
  );
  study.finishAnswer(text);
}

void main() {
  late Directory dir;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('br-pdfrx-').path;
    await pdfrxFlutterInitialize();
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('br-study-runs-'));
  tearDown(() => removeTemp(dir));

  testWidgets('a second time through: the first is kept, shown read-only, compared side by side', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(
      () => AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()),
        store: SettingsStore(File('${dir.path}/settings.json')),
      ),
    ))!;
    final study = s.study!;
    final bytes = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final (book, _) = (await tester.runAsync(() => study.importBytes(bytes, 'worksheet.pdf')))!;
    await tester.runAsync(() => study.open(book));
    final p1 = (await tester.runAsync(() => study.pageData(1)))!;
    answer(study, p1, 0, 'week');
    final first = study.run!;
    final second = study.startNewRun(name: 'Second, with the new group')!;
    expect(study.readOnly, isFalse);
    expect(study.answers, isEmpty, reason: 'a new time through starts empty');
    answer(study, p1, 0, 'Sunday');
    expect(study.store.run(first.id)!.locked, isTrue);
    await tester.runAsync(() => study.close());

    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Second, with the new group · 1 answer · 2 times through'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('worksheet').first);
      for (var i = 0; i < 20 && study.document == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await tester.pump();
    expect(study.run!.id, second.id, reason: 'opens on the current time through');
    expect(find.text('Second, with the new group'), findsWidgets, reason: 'the run menu and the title');

    // Every time's answers, by question.
    await tester.tap(find.text('Answers'));
    await tester.pump();
    await tester.tap(find.text('Every time'));
    await tester.pump();
    expect(find.text('1. The group meets every ___ to read and ___ together.'), findsOneWidget);
    expect(find.text('1st time, Nov 2026: week', findRichText: true), findsOneWidget);
    expect(find.text('Second, with the new group: Sunday', findRichText: true), findsOneWidget);

    // The earlier one: read-only, with Unlock and Back.
    study.viewRun(first);
    await tester.pump();
    expect(find.textContaining('an earlier time through'), findsOneWidget);
    expect(study.readOnly, isTrue);
    study.unlockRun();
    await tester.pump();
    expect(find.textContaining('is unlocked until you close the book'), findsOneWidget);
    expect(study.readOnly, isFalse);
    study.backToCurrent();
    await tester.pump();
    expect(find.textContaining('an earlier time through'), findsNothing);

    // Compare: a wide window shows the other run beside.
    study.setCompare(first);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('shown on the right'), findsOneWidget);
    expect(find.byType(StudyReader), findsNWidgets(2));
    expect(find.text('1st time, Nov 2026 · read-only'), findsOneWidget);
    study.setCompare(null);
    await tester.pump();
    await tester.pump();
    expect(find.byType(StudyReader), findsOneWidget);

    // Unmount first: the viewers' queued renders run on the test's fake time, then the document can close.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => study.close());
  });
}
