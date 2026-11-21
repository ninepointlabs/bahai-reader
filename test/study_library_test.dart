// Study's library (categories, sorting, search in marks) and Saved → Highlights & notes across the app.
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/labels.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/marks/marks_export.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/features/study/study_library_view.dart';
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
  setUp(() => dir = Directory.systemTemp.createTempSync('br-study-lib-'));
  tearDown(() => removeTemp(dir));

  Future<AppState> state(WidgetTester tester) async => (await tester.runAsync(
    () => AppState.create(
      repository: LibraryRepository(bundle: DiskBundle()),
      store: SettingsStore(File('${dir.path}/settings.json')),
    ),
  ))!;

  testWidgets('categories filter the library; search finds words in highlights and answers', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = await state(tester);
    final study = s.study!;
    final bytes = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final (book, _) = (await tester.runAsync(() => study.importBytes(bytes, 'worksheet.pdf')))!;
    await tester.runAsync(() => study.open(book));
    final p1 = (await tester.runAsync(() => study.pageData(1)))!;
    final at = p1.text.indexOf('study group');
    study.highlight(p1, at, at + 'study group'.length, color: 'green', note: 'Who comes on Sundays?');
    await tester.runAsync(() => study.close());
    study.setCategories(book, [study.addCategory('Book 1')]);

    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget, reason: 'the sort');
    expect(find.widgetWithText(ChoiceChip, 'Book 1'), findsOneWidget);
    expect(find.textContaining('#Book 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Uncategorized'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(StudyLibraryView), matching: find.text('worksheet')), findsNothing);
    expect(find.text('No books in this category.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search your books, highlights, notes and answers'),
      'sundays',
    );
    await tester.pumpAndSettle();
    expect(find.text('Found in your marks (1)'), findsOneWidget);
    expect(find.text('study group'), findsOneWidget);

    // Saved → Highlights & notes, Study.
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Highlights & notes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study').last);
    await tester.pumpAndSettle();
    expect(find.text('study group'), findsOneWidget);
    expect(find.textContaining('worksheet · 1st time, Nov 2026 · p. 1'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('study group'));
      for (var i = 0; i < 20 && study.document == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await tester.pump();
    expect(study.book?.id, book.id, reason: 'opened at the mark');
    expect(find.text('Contents'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => study.close());
  });

  testWidgets('the writings\' highlights export to Markdown with their citations and notes', (tester) async {
    final s = await state(tester);
    final p = s.library!.byId['hidden:2']!;
    await tester.runAsync(() => s.addHighlight(p, 0, 9, color: 'green', note: 'Read every morning'));
    final h = s.highlights.single;
    final md = renderHighlightsMarkdown([
      (highlight: h, passage: p, group: 'The Hidden Words', place: placeOf(p)),
    ], exportedAt: DateTime(2026, 11, 20, 20));
    expect(
      md,
      startsWith('---\ntitle: "Highlights and notes"\ngenerator: bahai-reader\nexported: 2026-11-20T20:00:00'),
    );
    expect(md, contains('## The Hidden Words\n\n> ${h.words.trim()}'));
    expect(md, contains('> — ${p.citation}'), reason: 'quoted with its citation');
    expect(md, contains('\nRead every morning\n'));
  });
}
