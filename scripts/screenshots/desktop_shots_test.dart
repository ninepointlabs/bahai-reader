// Renders the desktop window for the website's screenshots, off screen, with the real library and system fonts.
//   flutter test scripts/screenshots/desktop_shots_test.dart --update-goldens
// writes PNGs to scripts/screenshots/out/; scripts/screenshots/convert.sh turns them into docs/screenshots/*.webp.
// Not part of the test suite (it lives outside test/ and needs the fonts below installed).
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/calendar/badi.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/app_test.dart' show settle;
import '../../test/disk_bundle.dart';

const size = Size(1600, 1000);
final material = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';

final fonts = {
  'Noto Serif': [
    for (final s in ['Regular', 'Bold', 'Italic', 'BoldItalic']) '/usr/share/fonts/noto/NotoSerif-$s.ttf',
  ],
  'Adwaita Sans': [
    '/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf',
    '/usr/share/fonts/Adwaita/AdwaitaSans-Italic.ttf',
  ],
  'Roboto': [
    for (final s in ['Regular', 'Medium', 'Bold']) '$material/Roboto-$s.ttf',
  ],
  'MaterialIcons': ['$material/MaterialIcons-Regular.otf'],
};

Future<void> loadFonts() async {
  for (final MapEntry(key: family, value: files) in fonts.entries) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }
}

void main() {
  late Directory dir;
  setUpAll(loadFonts);
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-shots'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A reader's state: Haifa, the short obligatory prayer, three books read, a highlight with a note.
  Future<AppState> state(WidgetTester tester, {String theme = 'dark'}) async {
    final s = (await tester.runAsync(
      () => AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()),
        store: SettingsStore(File('${dir.path}/settings.json')),
      ),
    ))!;
    await tester.runAsync(() async {
      await s.setTheme(theme);
      await s.setLocation(Place.clean({'label': 'Haifa, Israel', 'lat': 32.82, 'lon': 34.99, 'tz': 'Asia/Jerusalem'}));
      await s.setPrayer('short');
      final lib = s.library!;
      for (final (book, id) in [
        ('The Kitáb-i-Íqán', 'iqan:40'),
        ('Gleanings from the Writings of Bahá’u’lláh', 'gleanings:27'),
        ('The Hidden Words', 'hidden:12'),
      ]) {
        s.rememberPosition(lib.books.firstWhere((w) => w.title == book), lib.byId[id]!);
      }
      final p = lib.byId['hidden:12']!;
      const words = 'within thee have I placed the essence of My light';
      final at = p.text.indexOf(words);
      await s.addHighlight(
        p,
        at,
        at + words.length,
        color: 'yellow',
        note: 'Content with what is placed within: nothing else is needed.',
      );
    });
    return s;
  }

  void window(WidgetTester tester) {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> shot(String name) => expectLater(find.byType(BahaiReaderApp), matchesGoldenFile('out/$name.png'));

  Future<void> keys(WidgetTester tester, LogicalKeyboardKey key, {bool control = false}) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
  }

  Future<AppState> open(WidgetTester tester, {String? id, String theme = 'dark', int? margin}) async {
    window(tester);
    final s = await state(tester, theme: theme);
    if (margin != null) s.settings.margin = margin;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true, openId: id));
    await settle(tester);
    return s;
  }

  testWidgets('home', (tester) async {
    await open(tester);
    await shot('01-home-library');
  });

  testWidgets('a book with its contents', (tester) async {
    await open(tester, id: 'gleanings:27');
    await shot('02-reader-book-contents');
  });

  testWidgets('a highlight with its note', (tester) async {
    await open(tester, id: 'hidden:12');
    final text = tester.widget<SelectableText>(find.byType(SelectableText).first);
    final at = (text.data ?? text.textSpan!.toPlainText()).indexOf('the essence');
    text.onSelectionChanged!(TextSelection.collapsed(offset: at), SelectionChangedCause.tap);
    await settle(tester);
    await shot('03-reader-highlight-note');
  });

  testWidgets('today', (tester) async {
    await open(tester);
    await keys(tester, LogicalKeyboardKey.keyT, control: true);
    await shot('04-today');
  });

  testWidgets('search', (tester) async {
    final s = await open(tester, id: 'hidden:12');
    await tester.runAsync(() => s.searchIndex());
    await keys(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.enterText(find.widgetWithText(TextField, 'Search the texts…'), 'radiant heart');
    await tester.pump(const Duration(milliseconds: 200));
    await settle(tester);
    await tester.tap(find.textContaining(RegExp(r'^Everything · ')));
    await settle(tester);
    await shot('06-search-ctrl-k');
  });

  testWidgets('focus mode', (tester) async {
    await open(tester, id: 'gleanings:27', margin: 160);
    await keys(tester, LogicalKeyboardKey.f11);
    await shot('07-focus-mode');
  });

  testWidgets('light', (tester) async {
    await open(tester, id: 'hidden:12', theme: 'light');
    await shot('10b-light-reader-highlight');
  });
}
