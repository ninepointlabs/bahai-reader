// Study on a phone: the fourth tab of the bottom bar, the library, and a book opened full screen with its panels.
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
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
  setUp(() => dir = Directory.systemTemp.createTempSync('br-study-phone-'));
  tearDown(() => removeTemp(dir));

  testWidgets('the bottom bar has Today, Writings, Prayers and Study; a book opens full screen', (tester) async {
    tester.view
      ..physicalSize = const Size(420, 860)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(
      () => AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()),
        store: SettingsStore(File('${dir.path}/settings.json')),
      ),
    ))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: false));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Today', 'Writings', 'Prayers', 'Study']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget, reason: label);
    }
    await tester.tap(find.widgetWithText(NavigationDestination, 'Writings'));
    await tester.pumpAndSettle();
    expect(find.text('Bahá’u’lláh'), findsOneWidget, reason: 'the writings under their authors, as before');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Study'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Import your own copies of Ruhi Institute books'), findsOneWidget);

    final study = s.study!;
    final bytes = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    await tester.runAsync(() => study.importBytes(bytes, 'worksheet.pdf'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('worksheet'));
      for (var i = 0; i < 20 && study.document == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('1st time,'), findsWidgets, reason: 'the run under the title');
    await tester.tap(find.byTooltip('Contents, highlights, bookmarks, answers and notes'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Section 2: Looking back'), findsOneWidget, reason: 'the contents in a sheet');
    await tester.tap(find.text('Section 2: Looking back'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Section 2: Looking back'), findsNothing, reason: 'the sheet closes after a jump');

    // Leaving the book closes it.
    await tester.runAsync(() async {
      await tester.pageBack();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 400));
    expect(study.book, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
