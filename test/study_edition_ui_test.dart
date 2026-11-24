// Importing a new edition in the desktop window: the question, moving the marks, and what could not be placed.
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/core/study/study_store.dart';
import 'package:bahai_reader/features/study/study_actions.dart';
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
  setUp(() => dir = Directory.systemTemp.createTempSync('br-edition-ui-'));
  tearDown(() => removeTemp(dir));

  testWidgets('a new edition: asked, marks moved, the unfound one listed', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(
      () => AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()),
        store: SettingsStore(File('${dir.path}/settings.json')),
      ),
    ))!;
    final study = s.study!..dogearFolder = () => null;
    final one = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final two = File('test/fixtures/worksheet-2.pdf').readAsBytesSync();
    final (book, _) = (await tester.runAsync(() => study.importBytes(one, 'Workbook_2.1.1.pdf')))!;
    await tester.runAsync(() => study.open(book));
    final p1 = (await tester.runAsync(() => study.pageData(1)))!;
    final at = p1.text.indexOf('study group');
    study.highlight(p1, at, at + 11, color: 'green');
    study.store.putAnswer(
      study.run!.id,
      book.docId,
      const AnswerPlace(page: 1, kind: 'line', x: 72, y: 700, w: 100),
      'an answer to a question the new edition dropped',
      context: '9. Gone.',
    );
    await tester.runAsync(() => study.close());

    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(StudyLibraryView));
    late Future<void> importing;
    await tester.runAsync(() async {
      importing = importStudyBytes(context, study, two, 'Workbook_2.2.1.pdf');
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    expect(find.text('Another edition of a book you have marked?'), findsOneWidget);
    expect(find.textContaining('looks like another copy or edition of “Workbook_2.1.1”'), findsOneWidget);
    await tester.tap(find.text('Move my marks'));
    await tester.runAsync(() async {
      await importing;
    });
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('1 mark found in this edition; 1 could not be'), findsOneWidget);
    expect(study.book?.doc.fileName, 'Workbook_2.2.1.pdf');
    expect(study.highlights.single.quote, 'study group');
    expect(study.unplaced.answers.single.text, 'an answer to a question the new edition dropped');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => study.close());
  });
}
