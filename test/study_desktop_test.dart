// Study in the desktop window: the sidebar row, the empty library, a book imported and opened, its panels.
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

import 'disk_bundle.dart';
import 'helpers/temp.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('br-pdfrx-').path;
    await pdfrxFlutterInitialize();
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('br-study-desktop-'));
  tearDown(() => removeTemp(dir));

  Future<AppState> state() => AppState.create(
    repository: LibraryRepository(bundle: DiskBundle()),
    store: SettingsStore(File('${dir.path}/settings.json')),
  );

  void wide(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('Study: the sidebar row, the empty library, an imported book opened with its panels', (tester) async {
    wide(tester);
    final s = (await tester.runAsync(state))!;
    final study = s.study!;
    expect(study.books.path, '${dir.path}/books', reason: 'beside the settings when there is no data folder');
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    expect(find.text('Study'), findsOneWidget, reason: 'a sidebar row between Writings and Saved');
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Import your own copies of Ruhi Institute books'), findsOneWidget);
    expect(find.textContaining('never uploaded'), findsOneWidget);
    expect(find.textContaining('not affiliated with or endorsed by the Ruhi Institute'), findsOneWidget);

    // Importing (the file dialog is the system's; the bytes go the same way).
    final bytes = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final (book, isNew) = (await tester.runAsync(() => study.importBytes(bytes, 'worksheet.pdf')))!;
    expect(isNew, isTrue);
    expect(book.doc.pageCount, 2);
    expect(File('${dir.path}/books/${book.doc.sha256}.pdf').existsSync(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('worksheet'), findsWidgets, reason: 'the library lists it by file name');
    expect(find.textContaining('1st time,'), findsWidgets);

    // Marks through the controller (what the page's gestures call). Page data is read before the viewer is on
    // screen: under the test's fake time the viewer's queued renders would hold PDFium's queue.
    await tester.runAsync(() => study.open(book));
    final page1 = (await tester.runAsync(() => study.pageData(1)))!;
    final at = page1.text.indexOf('study group');
    study.highlight(page1, at, at + 'study group'.length, color: 'green');
    study.toggleBookmark(1);
    final rule = page1.rules.first;
    final slot = slotFrom(page1.rules, 0, page1.fontSize);
    study.startAnswer(
      AnswerEdit(
        place: AnswerPlace(
          page: 1,
          kind: 'line',
          x: slot.x,
          y: slot.y,
          w: slot.w,
          pitch: slot.pitch,
          lines: slot.lines,
          indent: slot.indent,
          size: slot.size,
        ),
        context: page1.contextAt(rule.x + 5, rule.y),
        ordinal: 0,
      ),
    );
    study.finishAnswer('week');
    await tester.runAsync(() => study.close());
    await tester.pumpAndSettle();
    expect(find.textContaining('1 highlight · 1 answer · 1 bookmark'), findsOneWidget, reason: 'the library row');

    // Opening reads the PDF for real: let that run outside the test's fake time.
    await tester.runAsync(() async {
      await tester.tap(find.text('worksheet').first);
      for (var i = 0; i < 20 && study.document == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('Contents'), findsOneWidget, reason: 'the book’s panels in the sidebar');
    expect(find.text('Section 1: Reading together'), findsOneWidget, reason: 'the PDF’s own contents');
    expect(find.byTooltip('Export this run to Markdown (Ctrl+E)'), findsOneWidget);
    expect(find.byTooltip('Remove the page’s bookmark (Ctrl+D)'), findsOneWidget, reason: 'page 1 is bookmarked');
    await tester.tap(find.text('Highlights'));
    await tester.pump();
    expect(find.text('study group'), findsOneWidget);
    await tester.tap(find.text('Bookmarks'));
    await tester.pump();
    expect(find.text('Section 1: Reading together'), findsOneWidget, reason: 'named after its contents entry');
    await tester.tap(find.text('Answers'));
    await tester.pump();
    expect(find.text('1. The group meets every ___ to read and ___ together.'), findsOneWidget);
    expect(find.text('week'), findsOneWidget);
    expect(study.store.counts(study.run!.id), (highlights: 1, notes: 0, answers: 1, bookmarks: 1));
    await tester.runAsync(() => study.close());
    // Let the viewer's own timers (page previews, the place to remember) run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
