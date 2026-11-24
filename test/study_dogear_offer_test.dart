// After an import that opens the book (the library screen goes away), Dogear's marks are still offered.
import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/features/desktop/sidebar.dart';
import 'package:bahai_reader/features/study/study_actions.dart';
import 'package:bahai_reader/features/study/study_library_view.dart';
import 'package:bahai_reader/main.dart';
import 'package:crypto/crypto.dart';
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
  setUp(() => dir = Directory.systemTemp.createTempSync('br-offer-'));
  tearDown(() => removeTemp(dir));

  testWidgets('the offer comes after the book has opened', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bytes = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final annotations = Directory('${dir.path}/Dogear/.dogear/annotations')..createSync(recursive: true);
    final sha = sha256.convert(bytes).toString();
    File('${annotations.path}/$sha.json').writeAsStringSync(
      jsonEncode({
        'dogear': 1,
        'sha256': sha,
        'file_name': 'worksheet.pdf',
        'page_count': 2,
        'highlights': [
          {'id': 'h', 'page': 0, 'rects': [], 'text': 'study group', 'color': 'yellow'},
        ],
      }),
    );
    final s = (await tester.runAsync(
      () => AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()),
        store: SettingsStore(File('${dir.path}/settings.json')),
      ),
    ))!;
    final study = s.study!..dogearFolder = () => Directory('${dir.path}/Dogear');
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    final model = tester.widget<Sidebar>(find.byType(Sidebar)).model;
    final context = tester.element(find.byType(StudyLibraryView));
    await tester.runAsync(() async {
      importStudyBytes(context, study, bytes, 'worksheet.pdf', opened: model.showStudyReader);
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();
    await tester.pump();
    expect(find.byType(StudyLibraryView), findsNothing, reason: 'the book opened in its place');
    expect(find.text('Bring in your Dogear marks?'), findsOneWidget);
    expect(find.textContaining('Dogear has 1 highlight for this book'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => study.close());
  });
}
