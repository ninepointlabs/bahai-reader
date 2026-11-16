import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/labels.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show settle;
import 'disk_bundle.dart';

/// The desktop window: the GTK app's layout (sidebar, header bar, reading pane, search dialog).
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-desktop'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<AppState> state() => AppState.create(
      repository: LibraryRepository(bundle: DiskBundle()), store: SettingsStore(File('${dir.path}/settings.json')));

  void wide(WidgetTester tester, [Size size = const Size(1400, 900)]) {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> keys(WidgetTester tester, LogicalKeyboardKey key, {bool control = false, bool shift = false}) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('home lists the library by author; a book opens with its contents; save, next, continue reading',
      (tester) async {
    wide(tester);
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    for (final label in ['Home', 'Prayers', 'Writings', 'Saved', 'Library', 'Bahá’u’lláh', 'Shoghi Effendi', '18 books']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Continue reading'), findsNothing, reason: 'nothing read yet');
    await tester.tap(find.text('The Hidden Words'));
    await tester.pumpAndSettle();
    expect(find.text('Search this section…'), findsOneWidget);
    expect(find.text('From the Arabic'), findsOneWidget);
    expect(find.text('Arabic no. 1'), findsWidgets, reason: 'heading and header subtitle');
    expect(find.text('Passage 1 of 153 · about 1 minute'), findsOneWidget);
    expect(find.text('The Hidden Words · 1 of 153'), findsOneWidget);
    await keys(tester, LogicalKeyboardKey.keyD, control: true);
    expect(s.settings.saved, ['hidden:1']);
    await tester.tap(find.text('Next →'));
    await tester.pumpAndSettle();
    expect(find.text('Arabic no. 2'), findsWidgets);
    await keys(tester, LogicalKeyboardKey.arrowRight, control: false);
    expect(s.settings.positions['The Hidden Words'], 'hidden:2');
    expect(s.settings.recent, ['The Hidden Words']);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Continue reading'), findsOneWidget);
    expect(find.text('Arabic no. 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a selection offers colours; a highlight opens its colour and note; Saved lists it', (tester) async {
    wide(tester);
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true, openId: 'hidden:1'));
    await settle(tester);
    SelectableText text() => tester.widget<SelectableText>(find.byType(SelectableText).first);
    text().onSelectionChanged!(const TextSelection(baseOffset: 0, extentOffset: 16), SelectionChangedCause.drag);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Note…'), findsOneWidget, reason: 'the bar shows once the selection settles');
    await tester.tap(find.byTooltip('Green'));
    await tester.pumpAndSettle();
    final h = s.settings.highlights.single;
    expect((h.id, h.start, h.color), ('hidden:1', 0, 'green'));
    text().onSelectionChanged!(const TextSelection.collapsed(offset: 3), SelectionChangedCause.tap);
    await tester.pumpAndSettle();
    expect(find.text('Remove highlight'), findsOneWidget);
    await tester.tap(find.byTooltip('Blue'));
    await tester.enterText(find.widgetWithText(TextField, 'Your note (kept on this device only)'), 'a note');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect((s.settings.highlights.single.color, s.settings.highlights.single.note), ('blue', 'a note'));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('No saved passages yet'), findsOneWidget);
    await tester.tap(find.text('Highlights & notes · 1'));
    await tester.pumpAndSettle();
    expect(find.text('1 highlight, 1 with a note'), findsOneWidget);
    expect(find.text('a note'), findsOneWidget);
    await tester.tap(find.text('a note'));
    await tester.pumpAndSettle();
    expect(find.text('Arabic no. 1'), findsWidgets, reason: 'the card opens its passage');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+K searches this book or everything; Enter opens the first match', (tester) async {
    wide(tester);
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true, openId: 'iqan:1'));
    await settle(tester);
    await tester.runAsync(() => s.searchIndex());
    await keys(tester, LogicalKeyboardKey.keyK, control: true);
    await settle(tester);
    expect(find.text('Search'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Search the texts…'), 'Bahaullah');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^This book · \d+$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Everything · \d+$')), findsOneWidget);
    await tester.tap(find.textContaining(RegExp(r'^This book · ')));
    await tester.pumpAndSettle();
    expect(find.text('The Kitáb-i-Íqán'), findsWidgets, reason: 'results grouped under the book');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Search the texts…'), findsNothing, reason: 'the dialog closed');
    expect(find.textContaining('of the book'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow window: the sidebar and the content take turns', (tester) async {
    wide(tester, const Size(600, 860));
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    expect(find.text('Continue reading'), findsNothing);
    expect(find.text('Library'), findsOneWidget, reason: 'Home at first');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Writings'), findsOneWidget, reason: 'the sections');
    await tester.tap(find.text('Prayers'));
    await tester.pumpAndSettle();
    expect(find.text('Topics'), findsOneWidget, reason: 'Prayers shows its index of topics first, as on phones');
    final topic = s.library!.prayerCategories.first;
    await tester.tap(find.text(topic.title));
    await tester.pumpAndSettle();
    expect(find.text('All topics'), findsOneWidget, reason: 'a topic lists its prayers');
    expect(find.text('${topic.passages.length} prayer${topic.passages.length == 1 ? '' : 's'}'), findsOneWidget);
    await tester.tap(find.text(listTitle(topic.passages.first)).first);
    await tester.pumpAndSettle();
    expect(find.text('All topics'), findsNothing, reason: 'a prayer opens to read');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prayers'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Continue: '), findsOneWidget, reason: 'the prayer last read, above the topics');
    expect(tester.takeException(), isNull);
  });
}
