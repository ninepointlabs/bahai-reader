import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/calendar/badi.dart';
import 'package:bahai_reader/core/calendar/zones.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

/// The Dart calendar against answers from the GTK app's own badi.py and library.py (scripts/calendar_fixtures.py,
/// run with TZ=America/Chicago).
void main() {
  initTimeZones();
  tz.setLocalLocation(tz.getLocation('America/Chicago'));
  final fx = jsonDecode(File('test/fixtures/calendar.json').readAsStringSync()) as Map<String, dynamic>;
  final cal = BadiCalendar.fromJson(jsonDecode(File('assets/calendar/badi-dates.json').readAsStringSync()));
  final places = <String, Place>{
    'haifa': Place.clean({'label': 'Haifa', 'lat': 32.82, 'lon': 34.99, 'tz': 'Asia/Jerusalem'})!,
    'chicago': Place.clean({'label': 'Chicago', 'lat': 41.85, 'lon': -87.65, 'tz': 'America/Chicago'})!,
    'tromso': Place.clean({'label': 'Tromsø', 'lat': 69.65, 'lon': 18.96, 'tz': 'Europe/Oslo'})!,
    'kiritimati': Place.clean({'label': 'Kiritimati', 'lat': 1.87, 'lon': -157.4, 'tz': 'Pacific/Kiritimati'})!,
    'clock': Place.withClock(null, const ClockHours(360, 750, 1140)),
  };
  tz.TZDateTime moment(String iso, Place p) => tz.TZDateTime.from(DateTime.parse(iso), p.location);
  void sameInstant(DateTime? a, String? b, String why) {
    if (b == null) return expect(a, isNull, reason: why);
    expect(a, isNotNull, reason: why);
    expect((a!.microsecondsSinceEpoch - DateTime.parse(b).microsecondsSinceEpoch).abs(), lessThan(1000000), reason: '$why: $a vs $b');
  }

  test('Badí‘ dates, upcoming events, the Fast and the months match the GTK app', () {
    for (final row in fx['dates'] as List) {
      final d = parseDay(row['date'] as String);
      expect(cal.fromGregorian(d)?.toString(), row['badi'], reason: '${row['date']}');
      expect([for (final e in cal.upcoming(d, 120)) [e.name, isoDay(e.date), e.kind]], row['upcoming'], reason: '${row['date']}');
      final f = cal.fastState(d);
      expect(f == null ? null : [f.day, isoDay(f.date)], row['fast'], reason: '${row['date']}');
      expect(cal.nextAyyamIHa(d) == null ? null : isoDay(cal.nextAyyamIHa(d)!.first), row['ayyam']);
      final b = cal.fromGregorian(d);
      expect(b == null ? [] : [for (final m in cal.yearMonths(b.year)) [m.name, isoDay(m.first), isoDay(m.last)]], row['months']);
    }
  });

  test('sunrise, noon and sunset match to the second, including polar days and clock hours', () {
    for (final row in fx['sun'] as List) {
      // The timezone package's data has daylight-saving changes only up to 2037; Python's zoneinfo goes on by rule.
      if (parseDay(row['date'] as String).year > 2037) continue;
      final s = placeSun(places[row['place']], parseDay(row['date'] as String))!;
      final why = '${row['place']} ${row['date']}';
      sameInstant(s.sunrise, row['sunrise'] as String?, '$why sunrise');
      sameInstant(s.noon, row['noon'] as String, '$why noon');
      sameInstant(s.sunset, row['sunset'] as String?, '$why sunset');
      expect(s.polar, row['polar'], reason: why);
    }
  });

  test('the observed day, prayer windows and the long prayer period match', () {
    for (final row in fx['observed'] as List) {
      final p = places[row['place']]!;
      expect(isoDay(observedDate(moment(row['moment'] as String, p), p)), row['observed'], reason: '$row');
    }
    for (final row in fx['windows'] as List) {
      final p = places[row['place']]!;
      final w = currentWindow(row['prayer'] as String, moment(row['moment'] as String, p), p);
      final want = row['window'] as List?;
      if (want == null) {
        expect(w, isNull, reason: '$row');
        continue;
      }
      expect(w?.key, want[0], reason: '$row');
      sameInstant(w!.opens, want[1] as String, '$row opens');
      sameInstant(w.closes, want[2] as String, '$row closes');
    }
    for (final row in fx['long'] as List) {
      final p = places[row['place']]!;
      final w = longWindow(row['period'] as String, moment(row['moment'] as String, p), p, const []);
      final want = row['window'] as List;
      expect(w.key, want[0], reason: '$row');
      sameInstant(w.opens, want[1] as String, '$row opens');
      sameInstant(w.closes, want[2] as String, '$row closes');
    }
  });

  test('the passage of the day is the GTK app’s', () async {
    final lib = parseLibrary(await File('assets/library/1.json').readAsString());
    for (final row in fx['daily'] as List) {
      expect(lib.passageOfTheDay(ordinal(parseDay(row[0] as String)))?.id, row[1], reason: '${row[0]}');
    }
    expect(lib.obligatoryGroups.map((g) => g.title), ['The three prayers', 'Kitáb-i-Aqdas']);
    expect(lib.obligatoryGroups.first.passages.map((p) => p.tags.first),
        ['Short Obligatory Prayer', 'Medium Obligatory Prayer', 'Long Obligatory Prayer']);
  });

  test('clock text, counter and clock hours', () {
    final m = tz.TZDateTime(tz.getLocation('America/Chicago'), 2026, 11, 15, 17, 5);
    expect(formatClock(m, twelveHour: true), '5:05 PM');
    expect(formatClock(m, twelveHour: false), '17:05');
    expect(parseClock('6:30'), 390);
    expect(parseClock('24:00'), isNull);
    expect(ClockHours.clean({'sunrise': 600, 'noon': 500, 'sunset': 900}), isNull, reason: 'out of order');
    final c = Counter(3);
    expect([c.add(), c.add(), c.add(), c.add(), c.done], [true, true, true, false, true]);
    expect(c.setTarget('2'), isTrue);
    expect('$c', '2 of 2');
    expect(Counter.validTarget(0), isNull);
  });
}
