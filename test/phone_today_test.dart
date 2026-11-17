import 'dart:async';
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/calendar/badi.dart';
import 'package:bahai_reader/core/calendar/reminders.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/platform/notifier.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/features/library/contents_screen.dart';
import 'package:bahai_reader/features/library/library_screen.dart';
import 'package:bahai_reader/features/reader/reader_screen.dart';
import 'package:bahai_reader/features/today/counter_view.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp.dart';
import 'package:timezone/timezone.dart' as tz;

import 'disk_bundle.dart';

/// Stands in for Android's alarms and notifications.
class FakeScheduler extends Notifier {
  final shown = <Reminder>[];
  final handed = <List<Reminder>>[];
  final pending = <NotificationAction>[];
  final withdrawn = <String>[];
  int permissionAsked = 0;
  @override
  String? get unavailable => null;
  @override
  Stream<NotificationAction> get actions => const Stream.empty();
  @override
  bool get schedules => true;
  @override
  Future<void> send(Reminder r) async => shown.add(r);
  @override
  Future<void> withdraw(String group) async => withdrawn.add(group);
  @override
  Future<void> schedule(List<Reminder> later) async => handed.add(later);
  @override
  Future<List<NotificationAction>> takePending() async {
    final all = [...pending];
    pending.clear();
    return all;
  }

  @override
  Future<void> requestPermission() async => permissionAsked++;
}

/// Today, the obligatory prayers and reminders in the phone layout.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-phone'));
  tearDown(() => removeTemp(dir));

  /// 15 November 2026, 1 pm in Chicago: the Short prayer's window is open.
  Future<AppState> state() async {
    final s = await AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()), store: SettingsStore(File('${dir.path}/settings.json')));
    tz.setLocalLocation(tz.getLocation('America/Chicago'));
    s.fixedNow = DateTime.utc(2026, 11, 15, 19);
    s.twelveHour = true;
    s.settings.location = Place.clean({'label': 'Chicago', 'lat': 41.85, 'lon': -87.65, 'tz': 'America/Chicago'});
    return s;
  }

  Future<AppState> start(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(420, 860)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: false));
    await tester.pumpAndSettle();
    return s;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  testWidgets('the phone opens on Today; a prayer is chosen in Location & reminders, said, and opened', (tester) async {
    final s = await start(tester);
    expect(find.text('12 Qudrat 183 B.E.'), findsOneWidget);
    await tapText(tester, 'Choose a prayer…');
    expect(find.widgetWithText(AppBar, 'Location & reminders'), findsOneWidget, reason: 'a full page on phones');
    await tester.scrollUntilVisible(find.text('Short'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(tester, 'Short');
    expect(s.settings.prayer, 'short');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Said today');
    expect(s.settings.said, ['2026-11-15:short:noon']);
    await tapText(tester, 'Open the Short Obligatory Prayer');
    expect(find.byType(ReaderScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('✓ Said today'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('✓ Said today'), findsOneWidget, reason: 'the same mark in the prayer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Prayers starts with the Obligatory prayers: the counter, the prayers and their guidance', (tester) async {
    await start(tester);
    await tapText(tester, 'Prayers');
    expect(find.byType(Card), findsNothing, reason: 'on a phone the prayers are a compact index, not cards');
    expect(find.byType(ListTile), findsWidgets);
    final category = AppScope.read(tester.element(find.byType(LibraryScreen))).library!.prayerCategories.first;
    await tapText(tester, category.title);
    expect(find.byType(ContentsScreen), findsOneWidget, reason: 'a topic opens its list of prayers, not the first prayer');
    expect(find.byType(ReaderScreen), findsNothing);
    await tester.tap(find.byType(ListTile).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ContentsScreen))).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Obligatory prayers'), -300,
        scrollable: find.ancestor(of: find.byType(ListTile).first, matching: find.byType(Scrollable)).first);
    await tapText(tester, 'Obligatory prayers');
    expect(find.text('Alláh-u-Abhá counter'), findsOneWidget);
    await tapText(tester, 'Alláh-u-Abhá counter');
    expect(find.byType(CounterView), findsOneWidget);
    await tapText(tester, 'Count');
    expect(find.text('1 of 95'), findsOneWidget);
    await tapText(tester, 'Alláh-u-Abhá'); // a tap on the page, away from the button, counts too
    await tester.tap(find.text('Or tap anywhere on the page'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 95'), findsOneWidget);
    await tapText(tester, 'Undo');
    expect(find.text('2 of 95'), findsOneWidget, reason: 'the other buttons do only their own thing');
    expect(tester.takeException(), isNull);
  });

  test('on phones reminders are handed over a week ahead, again after Said, and taps made while closed are taken',
      () async {
    final s = await state();
    s.settings.prayer = 'short';
    final n = FakeScheduler();
    s.startReminders(n);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(n.handed.last, isEmpty, reason: 'all off until turned on');
    await s.setReminder('prayer', true);
    expect(n.permissionAsked, 1);
    expect([for (final r in n.shown) r.id], ['2026-11-15:short:noon:opens'], reason: 'due now: shown at once');
    final week = n.handed.last;
    expect(week.first.id, '2026-11-15:short:noon:closing');
    expect(week.where((r) => r.id.endsWith(':opens')).length, greaterThanOrEqualTo(6));
    await s.sendDueReminders();
    expect(n.shown, hasLength(1), reason: 'not shown twice');

    n.pending.addAll(['said:2026-11-15:short:noon', 'open:prayer:short']);
    final opened = s.openRequests.first;
    await s.takePendingActions();
    expect(s.settings.said, ['2026-11-15:short:noon']);
    expect(await opened, 'prayer:short');
    expect(n.handed.last.any((r) => r.id == '2026-11-15:short:noon:closing'), isFalse, reason: 'said: no closing nudge');
    s.dispose();
  });
}
