import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/calendar/badi.dart';
import 'package:bahai_reader/core/calendar/reminders.dart';
import 'package:bahai_reader/core/calendar/zones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

/// The Dart reminders against answers from the GTK app's own badi.py (scripts/reminder_fixtures.py, run with
/// TZ=America/Chicago): every candidate reminder, its text and times, and which are due, for 1,152 cases.
void main() {
  initTimeZones();
  tz.setLocalLocation(tz.getLocation('America/Chicago'));
  final fx = jsonDecode(File('test/fixtures/reminders.json').readAsStringSync()) as Map<String, dynamic>;
  final cal = BadiCalendar.fromJson(jsonDecode(File('assets/calendar/badi-dates.json').readAsStringSync()));
  final places = <String, Place?>{
    'haifa': Place.clean({'label': 'Haifa', 'lat': 32.82, 'lon': 34.99, 'tz': 'Asia/Jerusalem'}),
    'chicago': Place.clean({'label': 'Chicago', 'lat': 41.85, 'lon': -87.65, 'tz': 'America/Chicago'}),
    'clock': Place.withClock(null, const ClockHours(360, 750, 1140)),
    'none': null,
  };
  final settings = {
    for (final e in (fx['settings'] as Map).entries)
      e.key as String: ReminderSettings(
        switches: ((e.value as Map)['reminders'] as Map).cast<String, bool>(),
        prayer: (e.value as Map)['prayer'] as String?,
        longPeriod: (e.value as Map)['long_period'] as String?,
        longLeadHours: (e.value as Map)['long_lead_hours'] as int?,
      ),
  };
  String clock(tz.TZDateTime m) => formatClock(m, twelveHour: false);
  int ms(String iso) => DateTime.parse(iso).millisecondsSinceEpoch;

  test('candidate and due reminders match the GTK app', () {
    var checked = 0;
    for (final c in (fx['cases'] as List).cast<Map<String, dynamic>>()) {
      final place = places[c['place']];
      final s = settings[c['settings']]!;
      final moment = tz.TZDateTime.from(DateTime.parse(c['moment'] as String), place?.location ?? tz.local);
      final said = (c['said'] as List).cast<String>();
      final why = '${c['place']} ${c['settings']} ${c['moment']}';
      final found = candidateReminders(cal, s, moment, place, clock, said);
      final expected = (c['candidates'] as List).cast<List>();
      expect([for (final r in found) r.id], [for (final e in expected) e[0]], reason: why);
      for (var i = 0; i < found.length; i++) {
        final (r, e) = (found[i], expected[i]);
        expect([r.group, r.title, r.body, r.said, r.opens], [e[1], e[2], e[3], e[6], e[7]], reason: '$why ${r.id}');
        expect((r.at.millisecondsSinceEpoch - ms(e[4] as String)).abs(), lessThan(1000), reason: '$why ${r.id} at');
        expect((r.until.millisecondsSinceEpoch - ms(e[5] as String)).abs(), lessThan(1000), reason: '$why ${r.id} until');
        checked++;
      }
      final (due, marked) = dueReminders(cal, s, moment, place, clock, (c['sent'] as List).cast<String>(), said);
      expect([for (final r in due) r.id], c['due'], reason: '$why due');
      expect(marked, c['marked'], reason: '$why marked');
    }
    expect(checked, greaterThan(10000));
  });

  test('sent ids are pruned after three days, and the Long lead is checked', () {
    expect(pruneSent(['2026-11-11:a', '2026-11-12:b', '2026-11-15:c'], day(2026, 11, 15)), ['2026-11-12:b', '2026-11-15:c']);
    expect([longLead(null), longLead(0), longLead(5), longLead(13), longLead('3')], [2, 2, 5, 2, 2]);
  });

  test('upcoming reminders for phones: the same reminders, ahead of time, each once', () {
    final chicago = places['chicago'];
    final s = settings['medium']!;
    final moment = tz.TZDateTime(chicago!.location, 2026, 2, 28, 13, 10);
    final (later, now) = upcomingReminders(cal, s, moment, chicago, clock, const [], const []);
    expect(later.map((r) => r.id).toSet().length, later.length, reason: 'no duplicates');
    expect(later.every((r) => r.at.isAfter(moment)), isTrue);
    expect(later.last.at.difference(moment).inDays, lessThanOrEqualTo(8));
    // Everything the desktop would send over those days, at its time, is among them.
    for (var h = 0; h < 24 * 6; h += 1) {
      final m = tz.TZDateTime.from(moment.add(Duration(hours: h, minutes: 1)), chicago.location);
      for (final r in candidateReminders(cal, s, m, chicago, clock)) {
        if (r.at.isAfter(moment) && !r.at.isAfter(m) && m.isBefore(r.until)) {
          expect(later.any((x) => x.id == r.id), isTrue, reason: '${r.id} at $m');
        }
      }
    }
    expect(now.map((r) => r.id), ['2026-02-28:medium:noon:opens']);
    final (_, again) = upcomingReminders(cal, s, moment, chicago, clock, [for (final r in now) r.id], const []);
    expect(again, isEmpty, reason: 'not handed over twice');
    final (afterSaid, _) = upcomingReminders(cal, s, moment, chicago, clock, const [], ['2026-02-28:medium:noon']);
    expect(afterSaid.any((r) => r.said == '2026-02-28:medium:noon'), isFalse, reason: 'said: no closing nudge');
  });
}
