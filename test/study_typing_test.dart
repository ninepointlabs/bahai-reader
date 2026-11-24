// Typing an answer: Space and plain letters go to the text, not to the page (they turned the page before).
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/features/study/study_reader.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  setUp(() => dir = Directory.systemTemp.createTempSync('br-typing-'));
  tearDown(() => removeTemp(dir));

  testWidgets('while an answer is typed, Space and j do not move the page; outside it, they still work', (
    tester,
  ) async {
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
    final bytes = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final (book, _) = (await tester.runAsync(() => study.importBytes(bytes, 'worksheet.pdf')))!;
    await tester.runAsync(() async {
      await study.open(book);
      await study.pageData(1);
    });
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final reader = tester.state<StudyReaderState>(find.byType(StudyReader));
    expect(reader.typing, isFalse);

    // Start typing in the search field (a text field in the reader, like the answer editor).
    reader.openSearch();
    await tester.pump();
    await tester.pump();
    expect(reader.typing, isTrue);
    final before = reader.pdf.value.clone();
    for (final k in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.digit1,
    ]) {
      await tester.sendKeyEvent(k);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(reader.pdf.value, before, reason: 'the page did not move');
    expect(study.bookmarkOn(1), isNull, reason: '"b" typed, not a bookmark');

    // Back on the page, the keys work again.
    reader.focus.requestFocus();
    await tester.pump();
    expect(reader.typing, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(study.bookmarkOn(study.page), isNotNull, reason: '"b" bookmarks the page');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => study.close());
  });
}
