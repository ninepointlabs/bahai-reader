import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/calendar/badi.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_test.dart' show settle;
import 'disk_bundle.dart';

/// Today, the obligatory prayers section, the counter and Location & reminders, in the desktop window.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-today'));
  tearDown(() => removeTemp(dir));

  /// 15 November 2026, 1 pm in Chicago: 12 Qudrat 183 B.E., the Short prayer's window open.
  Future<AppState> state({bool chicago = true}) async {
    final s = await AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()), store: SettingsStore(File('${dir.path}/settings.json')));
    tz.setLocalLocation(tz.getLocation('America/Chicago'));
    s.fixedNow = DateTime.utc(2026, 11, 15, 19);
    s.twelveHour = true;
    if (chicago) s.settings.location = Place.clean({'label': 'Chicago', 'lat': 41.85, 'lon': -87.65, 'tz': 'America/Chicago'});
    return s;
  }

  Future<AppState> start(WidgetTester tester, {bool chicago = true}) async {
    tester.view
      ..physicalSize = const Size(1400, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => state(chicago: chicago)))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    return s;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  testWidgets('Home has the day at a glance; Today has every card; Said is marked from Today and from the prayer',
      (tester) async {
    final s = await start(tester);
    expect(find.text('12 Qudrat 183 B.E.'), findsOneWidget);
    expect(find.text('Choose which obligatory prayer you say to see its times here.'), findsOneWidget);
    expect(find.text('PASSAGE OF THE DAY'), findsOneWidget);
    s.settings.prayer = 'short';
    await tapText(tester, 'Open Today');
    for (final t in ['Sun', 'Obligatory prayer', 'Alláh-u-Abhá', 'Next Feast and Holy Day', 'Passage of the day']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.textContaining('Sunrise: '), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Open now, until \d+:\d\d PM$')), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget, reason: 'the Today calendar in the sidebar');
    expect(find.textContaining('This year, 183 B.E.'), findsOneWidget);
    await tapText(tester, 'Said today');
    final key = currentWindow('short', s.now(), s.settings.place)!.key;
    expect(s.settings.said, [key]);
    expect(find.text('✓ Said today'), findsOneWidget);
    await tapText(tester, 'Open the Short Obligatory Prayer');
    expect(find.text('Obligatory prayers'), findsWidgets, reason: 'the section, with a Back button');
    expect(find.text('Alláh-u-Abhá counter'), findsOneWidget);
    expect(find.text('Short Obligatory Prayer'), findsWidgets);
    expect(find.text('✓ Said today'), findsOneWidget, reason: 'the same mark in the reading footer');
    await tapText(tester, '✓ Said today');
    expect(s.settings.said, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Prayers starts with Obligatory prayers; the counter counts, undoes and goes back', (tester) async {
    final s = await start(tester);
    await tapText(tester, 'Prayers');
    await tester.tap(find.byTooltip('The three obligatory prayers, their guidance, and the Alláh-u-Abhá counter'));
    await tester.pumpAndSettle();
    expect(find.text('The three prayers'), findsOneWidget);
    expect(find.text('Kitáb-i-Aqdas'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('The three obligatory prayers, their guidance, and the Alláh-u-Abhá counter'), findsOneWidget,
        reason: 'back in Prayers');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('0 of 95'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('2 of 95'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('1 of 95'), findsOneWidget);
    await tester.tap(find.text('95'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9').last);
    await tester.pumpAndSettle();
    expect(find.text('1 of 9'), findsOneWidget);
    expect(s.settings.counterTarget, 9);
    await tester.tap(find.text('Alláh-u-Abhá').last); // the heading on the page, not the sidebar
    await tester.pumpAndSettle();
    expect(find.text('1 of 9'), findsOneWidget, reason: 'on desktops a click on the page does not count');
    expect(find.text('Or tap anywhere on the page'), findsNothing);
    expect(find.textContaining('Kitáb-i-Aqdas'), findsWidgets, reason: 'the verse and its citation');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('0 of 95'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Location & reminders: a city sets the place; the prayer choice shows on Today', (tester) async {
    final s = await start(tester, chicago: false);
    expect(find.text('Add location…'), findsNothing, reason: 'Home does not show the sun card');
    await tester.runAsync(() => s.cities());
    await tapText(tester, 'Open Today');
    await tapText(tester, 'Add location…');
    await tester.enterText(find.widgetWithText(TextField, 'Type a city…'), 'Haifa');
    await settle(tester);
    final haifa = find.textContaining('Haifa, Israel');
    expect(haifa, findsOneWidget);
    await tester.tap(haifa);
    await settle(tester);
    expect(s.settings.location?.zone, 'Asia/Jerusalem');
    await tester.scrollUntilVisible(find.text('Medium'), 200,
        scrollable: find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first);
    await tapText(tester, 'Medium');
    expect(s.settings.prayer, 'medium');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Haifa, Israel'), findsWidgets, reason: 'the sun card names the place');
    expect(find.textContaining('Morning: '), findsOneWidget);
    expect(find.text('Said this evening'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
