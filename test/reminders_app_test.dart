import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/calendar/badi.dart';
import 'package:bahai_reader/core/calendar/reminders.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/platform/notifier.dart';
import 'package:bahai_reader/core/platform/window_control.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/features/desktop/reading_view.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_test.dart' show settle;
import 'disk_bundle.dart';

/// Records what would be shown, instead of the desktop's notifications.
class FakeNotifier implements Notifier {
  final sent = <Reminder>[];
  final withdrawn = <String>[];
  final clicks = StreamController<NotificationAction>.broadcast();
  @override
  String? unavailable;
  @override
  Stream<NotificationAction> get actions => clicks.stream;
  @override
  Future<void> send(Reminder r) async => sent.add(r);
  @override
  Future<void> withdraw(String group) async => withdrawn.add(group);
}

/// Reminders in the app: sending what is due once, "Said today" and "Open" from a notification, the settings and the
/// login entry.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-reminders'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// 15 November 2026, 1 pm in Chicago: the Short prayer's window is open.
  Future<AppState> state() async {
    final s = await AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()), store: SettingsStore(File('${dir.path}/settings.json')));
    tz.setLocalLocation(tz.getLocation('America/Chicago'));
    s.fixedNow = DateTime.utc(2026, 11, 15, 19);
    s.twelveHour = true;
    s.settings.location = Place.clean({'label': 'Chicago', 'lat': 41.85, 'lon': -87.65, 'tz': 'America/Chicago'});
    s.settings.prayer = 'short';
    return s;
  }

  test('a due reminder is sent once; "Said today" marks it and stops the closing nudge; "Open" asks for the prayer',
      () async {
    final s = await state();
    final n = FakeNotifier();
    s.notifier = n;
    await s.sendDueReminders();
    expect(n.sent, isEmpty, reason: 'every reminder is off until turned on');
    await s.setReminder('prayer', true);
    expect([for (final r in n.sent) r.title], ['Short Obligatory Prayer']);
    expect(n.sent.single.body, startsWith('Its time is open, until 4:'));
    await s.sendDueReminders();
    expect(n.sent, hasLength(1), reason: 'not sent twice');
    expect(s.settings.remindersSent, contains(n.sent.single.id));

    await s.notificationAction('said:${n.sent.single.said}');
    expect(s.settings.said, [n.sent.single.said]);
    expect(n.withdrawn, ['prayer:short']);
    await s.notificationAction('said:not-a-mark');
    expect(s.settings.said, hasLength(1));

    s.fixedNow = DateTime.utc(2026, 11, 15, 22, 5); // 4:05 pm, within 30 minutes of sunset
    await s.sendDueReminders();
    expect(n.sent, hasLength(1), reason: 'already said, so no closing nudge');

    final opened = s.openRequests.first;
    await s.notificationAction('open:prayer:short');
    expect(await opened, 'prayer:short');

    final saved = Settings.fromJson(jsonDecode(await File('${dir.path}/settings.json').readAsString()));
    expect(saved.reminders, {'prayer': true});
    expect(saved.remindersSent, isNotEmpty);
  });

  test('the reminder settings are checked on loading', () {
    final s = Settings.fromJson({
      'reminders': {'prayer': true, 'feast': 'yes', 'bogus': true, 'fast_daily': false},
      'long_lead_hours': 13,
      'reminders_sent': ['2026-11-15:x', 'bad', 4],
      'keep_running': true,
    });
    expect(s.reminders, {'prayer': true, 'fast_daily': false});
    expect(s.longLeadHours, isNull);
    expect(s.remindersSent, ['2026-11-15:x']);
    expect(s.keepRunning, isTrue);
    expect(Settings.fromJson({'long_lead_hours': 5}).longLeadHours, 5);
  });

  test('the login entry starts the app hidden, and is removed when turned off', () async {
    final a = Autostart(environment: {'XDG_CONFIG_HOME': dir.path}, executable: '/opt/my "app"/bahai_reader');
    expect(await a.set(true), isNull);
    final text = a.file.readAsStringSync();
    expect(a.file.path, '${dir.path}/autostart/com.ninepointlabs.bahai_reader-reminders.desktop');
    expect(text, contains(r'Exec="/opt/my \"app\"/bahai_reader" --background'));
    expect(await a.set(false), isNull);
    expect(a.file.existsSync(), isFalse);
  });

  testWidgets('Location & reminders turns reminders on; a notification\'s Open goes to the prayer', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(state))!;
    s.notifier = FakeNotifier();
    s.autostart = Autostart(environment: {'XDG_CONFIG_HOME': dir.path}, executable: '/usr/bin/true');
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Today'));
    await tester.pumpAndSettle();
    expect(find.text('Reminders…'), findsWidgets);
    await tester.ensureVisible(find.text('Reminders…').first);
    await tester.tap(find.text('Reminders…').first);
    await tester.pumpAndSettle();
    expect(find.text('Location & reminders'), findsOneWidget);
    final scroll = find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first;
    for (final (label, key) in [
      ('Remind me when its time opens and before it closes', 'prayer'),
      ('Holy Days, the day before and on the day', 'holy'),
      ('During the Fast, before sunrise and at sunset each day', 'fast_daily'),
    ]) {
      await tester.scrollUntilVisible(find.text(label), 200, scrollable: scroll);
      await tester.tap(find.text(label));
      await settle(tester);
      expect(s.settings.reminders[key], isTrue, reason: key);
    }
    await tester.scrollUntilVisible(find.text('Keep reminders running when the window is closed'), 200, scrollable: scroll);
    await tester.tap(find.text('Keep reminders running when the window is closed'));
    for (var i = 0; i < 20 && s.keepRunningMessage == null; i++) {
      await settle(tester);
    }
    expect(s.settings.keepRunning, isTrue);
    expect(s.autostart!.file.existsSync(), isTrue);
    expect(find.text('Starts when you log in.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.runAsync(() => s.notificationAction('open:prayer:short'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingView), findsOneWidget);
    expect(find.text('Short Obligatory Prayer'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
