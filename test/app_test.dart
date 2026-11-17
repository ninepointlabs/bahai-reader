import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp.dart';

import 'disk_bundle.dart';

/// Lets futures that complete on the real event loop (isolates, runAsync work) reach the widgets, then settles.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-app'));
  tearDown(() => removeTemp(dir));

  Future<AppState> state() => AppState.create(
      repository: LibraryRepository(bundle: DiskBundle()), store: SettingsStore(File('${dir.path}/settings.json')));

  test('marks follow between English and Amharic without rewriting stored ids', () async {
    final s = await state();
    final en = s.library!.byId['hidden:2']!;
    await s.addHighlight(en, 0, 16, color: 'blue', note: 'a note');
    await s.toggleSaved(en);
    await s.setLanguage(90);
    await s.marksReady;
    final am = s.library!.byId['90:hidden:7400']!;
    expect(s.isSaved(am), isTrue);
    expect(s.highlightsOf(am), isEmpty, reason: 'no guessed word range on the translation');
    expect(s.followedHighlights(am).single.note, 'a note');
    expect(s.settings.saved, ['hidden:2']);
    expect(s.settings.highlights.single.id, 'hidden:2');
    // A prayer has no match: it stays with its own language.
    expect(s.passageOf('prayers:15692'), isNull);
  });

  testWidgets('the app starts, lists the library and opens a work', (tester) async {
    tester.view..physicalSize = const Size(1280, 900)..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s));
    await tester.pumpAndSettle();
    expect(find.text('Bahá’í Reader'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget, reason: 'the phone layout opens on Today');
    await tester.tap(find.text('Writings'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing, reason: 'tablets too: authors that fold open, not cards');
    await tester.tap(find.text('Prayers'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing, reason: 'and the prayer topics as an index');
    expect(find.text('Obligatory prayers'), findsOneWidget);
    await tester.tap(find.text('Writings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bahá’u’lláh'));
    await tester.pumpAndSettle();
    expect(find.text('The Hidden Words'), findsOneWidget);
    await tester.tap(find.text('The Hidden Words'));
    await tester.pumpAndSettle();
    expect(find.text('From the Arabic'), findsOneWidget, reason: 'a book opens its contents first, by part');
    await tester.tap(find.textContaining('O SON OF SPIRIT').first);
    await tester.pumpAndSettle();
    expect(find.text('Contents'), findsOneWidget, reason: 'wide window: contents beside the text');
    expect(find.textContaining('O SON OF SPIRIT', findRichText: true), findsWidgets);
    await tester.tap(find.byTooltip('Save passage'));
    await tester.pumpAndSettle();
    expect(s.settings.saved, ['hidden:1']);
    expect(find.byTooltip('Remove from saved'), findsOneWidget);
    await tester.ensureVisible(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 153'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow window: contents in a drawer; highlight from a selection', (tester) async {
    tester.view..physicalSize = const Size(420, 860)..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Writings'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing, reason: 'narrow: the books are a compact index');
    expect(find.text('Bahá’u’lláh'), findsOneWidget, reason: 'books under their authors');
    expect(find.text('The Hidden Words'), findsNothing, reason: 'each author starts folded');
    await tester.tap(find.text('Bahá’u’lláh'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Bahá’u’lláh')).dy, lessThan(tester.getTopLeft(find.text('The Hidden Words')).dy));
    await tester.tap(find.text('The Hidden Words'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('O SON OF SPIRIT').first);
    await tester.pumpAndSettle();
    expect(find.text('Contents'), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Contents'), findsOneWidget);
    await tester.tapAt(const Offset(410, 400)); // close the drawer
    await tester.pumpAndSettle();
    final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    selectable.onSelectionChanged!(const TextSelection(baseOffset: 0, extentOffset: 16), SelectionChangedCause.drag);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Highlight green'));
    await tester.pumpAndSettle();
    final h = s.settings.highlights.single;
    expect((h.id, h.start, h.color), ('hidden:1', 0, 'green'));
    expect(h.words, s.library!.byId['hidden:1']!.text.substring(h.start, h.end));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search screen: "Bahaullah" finds passages and opens one at the match', (tester) async {
    tester.view..physicalSize = const Size(1280, 900)..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s));
    await tester.pumpAndSettle();
    await tester.runAsync(() => s.searchIndex()); // folds the library in an isolate
    await tester.tap(find.byTooltip('Search'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'O SON OF SPIRIT bahaullah');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('No passages found.'), findsOneWidget, reason: 'phrase that is not in any text');
    await tester.enterText(find.byType(TextField), 'Kitab-i-Iqan');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^\d+ passages$')), findsOneWidget);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('of ', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a drawn highlight opens it for editing; removing it works', (tester) async {
    tester.view..physicalSize = const Size(1280, 900)..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(state))!;
    final p = s.library!.byId['hidden:1']!;
    await tester.runAsync(() => s.addHighlight(p, 0, 16, color: 'blue'));
    await tester.pumpWidget(BahaiReaderApp(state: s, openId: 'hidden:1'));
    await settle(tester);
    final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    selectable.onSelectionChanged!(const TextSelection.collapsed(offset: 3), SelectionChangedCause.tap);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove highlight'), findsOneWidget);
    await tester.tap(find.byTooltip('green'));
    await tester.pumpAndSettle();
    expect(s.settings.highlights.single.color, 'green');
    tester.widget<SelectableText>(find.byType(SelectableText)).onSelectionChanged!(const TextSelection.collapsed(offset: 3), SelectionChangedCause.tap);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove highlight'));
    await tester.pumpAndSettle();
    expect(s.settings.highlights, isEmpty);
  });
}
