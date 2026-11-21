// Renders Study off screen for checking by eye (and later the website): a workbook with marks, on the desktop.
//   flutter test scripts/screenshots/study_shots_test.dart --update-goldens
// writes PNGs to scripts/screenshots/out/. Not part of the test suite; needs the fonts in desktop_shots_test.dart.
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/core/study/rules.dart';
import 'package:bahai_reader/core/study/study_controller.dart';
import 'package:bahai_reader/core/study/study_store.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../test/disk_bundle.dart';
import 'desktop_shots_test.dart' show loadFonts;

void main() {
  late Directory dir;
  setUpAll(() async {
    await loadFonts();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('br-pdfrx-').path;
    await pdfrxFlutterInitialize();
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('br-study-shots'));

  Future<void> wait(WidgetTester tester, [int ms = 600]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  testWidgets('study reader with marks', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(
      () => AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()),
        store: SettingsStore(File('${dir.path}/settings.json')),
      ),
    ))!;
    await tester.runAsync(() => s.setTheme('light'));
    final study = s.study!;
    final bytes = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final (book, _) = (await tester.runAsync(() => study.importBytes(bytes, 'worksheet.pdf')))!;
    await tester.runAsync(() => study.open(book));
    final p1 = (await tester.runAsync(() => study.pageData(1)))!;
    final at = p1.text.indexOf('study group');
    study.highlight(p1, at, at + 'study group'.length, color: 'yellow', note: 'Who comes?');
    final at2 = p1.text.indexOf('talk about what it');
    study.highlight(p1, at2, at2 + 'talk about what it'.length, color: 'green');
    study.toggleBookmark(1);
    void answer(int i, String text) {
      final r = p1.rules[i];
      final slot = slotFrom(p1.rules, i, p1.fontSize);
      study.startAnswer(AnswerEdit(
        place: AnswerPlace(page: 1, kind: 'line', x: slot.x, y: slot.y, w: slot.w, pitch: slot.pitch,
            lines: slot.lines, indent: slot.indent, size: slot.size),
        context: p1.contextAt(r.x + 5, r.y),
        ordinal: i == 1 ? 1 : 0,
      ));
      study.finishAnswer(text);
    }

    answer(0, 'week');
    answer(1, 'reflect');
    answer(2, 'We talk about what the passage means and how it applies to our lives, then write our answers.');
    await tester.runAsync(() => study.close());

    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(BahaiReaderApp), matchesGoldenFile('out/study-01-library.png'));
    await tester.runAsync(() async {
      await tester.tap(find.text('worksheet').first);
      for (var i = 0; i < 20 && study.document == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    for (var i = 0; i < 8; i++) {
      await wait(tester, 300);
    }
    await tester.tap(find.text('Answers'));
    await wait(tester);
    await expectLater(find.byType(BahaiReaderApp), matchesGoldenFile('out/study-02-reader.png'));

    // A second time through, with different answers, compared side by side.
    final first = study.run!;
    study.startNewRun();
    answer(0, 'Sunday');
    answer(2, 'We read, talk it over, and then each of us writes what we understood in our own words.');
    study.setCompare(first);
    for (var i = 0; i < 6; i++) {
      await wait(tester, 300);
    }
    await expectLater(find.byType(BahaiReaderApp), matchesGoldenFile('out/study-03-compare.png'));
    tester.view.physicalSize = const Size(1100, 900);
    for (var i = 0; i < 4; i++) {
      await wait(tester, 300);
    }
    await expectLater(find.byType(BahaiReaderApp), matchesGoldenFile('out/study-03b-compare-narrow.png'));
    tester.view.physicalSize = const Size(1600, 1000);
    await wait(tester, 300);
    study.setCompare(null);
    await tester.tap(find.text('Every time'));
    for (var i = 0; i < 4; i++) {
      await wait(tester, 300);
    }
    await expectLater(find.byType(BahaiReaderApp), matchesGoldenFile('out/study-04-history.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => study.close());
  });
}
