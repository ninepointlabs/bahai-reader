/// The Badí‘ calendar, sun times and obligatory prayer times: a port of the GTK app's `badi.py` (its reminders are in reminders.dart).
///
/// Dates come from two sources of the Universal House of Justice: the message of 10 July 2014 fixes the Holy Days within
/// the Badí‘ calendar; the table "Badí‘ dates 172 to 221 B.E." (`assets/calendar/badi-dates.json`, copied from the GTK app)
/// gives each year's Naw-Rúz, Twin Holy Birthdays and length of Ayyám-i-Há. Outside the table the functions return null
/// or nothing rather than a guess.
///
/// A calendar day is a UTC [DateTime] at midnight ([day]); a moment is a [tz.TZDateTime] in the place's time zone.
library;

import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

const unpublished = 'Dates for this year have not been published yet.';
const ayyamIHa = 'Ayyám-i-Há';
const intercalary = 0;
const fastMonth = 19;
const monthDays = 19;
const clockAssembly =
    'Where days and nights vary greatly, prayer and fasting may follow the clock. Your National Spiritual Assembly can tell you the hours used in your country.';

const months = [
  ('Bahá', 'Splendour'), ('Jalál', 'Glory'), ('Jamál', 'Beauty'), ('‘Aẓamat', 'Grandeur'), ('Núr', 'Light'),
  ('Raḥmat', 'Mercy'), ('Kalimát', 'Words'), ('Kamál', 'Perfection'), ('Asmá’', 'Names'), ('‘Izzat', 'Might'),
  ('Mashíyyat', 'Will'), ('‘Ilm', 'Knowledge'), ('Qudrat', 'Power'), ('Qawl', 'Speech'), ('Masá’il', 'Questions'),
  ('Sharaf', 'Honour'), ('Sulṭán', 'Sovereignty'), ('Mulk', 'Dominion'), ('‘Alá’', 'Loftiness'),
];
const gregorianMonths = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'
];

int monthNumber(String name) => months.indexWhere((m) => m.$1 == name) + 1;

// ----- calendar days -----
DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
DateTime dayOf(DateTime moment) => DateTime.utc(moment.year, moment.month, moment.day);
DateTime addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);
int daysBetween(DateTime a, DateTime b) => b.difference(a).inDays;
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return day(p[0], p[1], p[2]);
}

/// Python's `date.toordinal()`: 1 for 1 January of year 1.
int ordinal(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1, 1, 1)).inDays + 1;

String gregorianText(DateTime d, {bool year = false}) => '${d.day} ${gregorianMonths[d.month - 1]}${year ? ' ${d.year}' : ''}';

class BadiDate {
  const BadiDate(this.year, this.month, this.day);
  final int year, month, day;
  String get monthName => month == intercalary ? ayyamIHa : months[month - 1].$1;
  String? get meaning => month == intercalary ? null : months[month - 1].$2;
  @override
  String toString() => '$day $monthName $year B.E.';
  @override
  bool operator ==(Object other) => other is BadiDate && other.year == year && other.month == month && other.day == day;
  @override
  int get hashCode => Object.hash(year, month, day);
}

class Event {
  const Event(this.kind, this.name, this.badi, this.date,
      {this.workSuspended = false, this.readings, this.prayers, this.meaning});

  /// `holy` or `feast`.
  final String kind;
  final String name;
  final BadiDate badi;

  /// The Gregorian day it falls on; it begins at sunset the evening before.
  final DateTime date;
  final bool workSuspended;

  /// The Holy Day's tag in Days of Remembrance (its readings), and its category in the prayers.
  final String? readings, prayers;
  final String? meaning;
  DateTime get begins => addDays(date, -1);
}

class Period {
  const Period(this.name, this.meaning, this.badi, this.first, this.last);
  final String name;
  final String? meaning;
  final BadiDate badi;
  final DateTime first, last;
}

/// (name, month, day, work suspended, Days of Remembrance tag, prayer category), from the message of 10 July 2014.
const _fixedHolyDays = [
  ('Naw-Rúz', 1, 1, true, 'NAWRUZ', 'Naw-Rúz'),
  ('First day of Riḍván', 2, 13, true, 'RIDVAN', null),
  ('Ninth day of Riḍván', 3, 2, true, 'RIDVAN', null),
  ('Twelfth day of Riḍván', 3, 5, true, 'RIDVAN', null),
  ('Declaration of the Báb', 4, 8, true, 'DECLARATIONBAB', null),
  ('Ascension of Bahá’u’lláh', 4, 13, true, 'ASCENSIONBAHAULLAH', null),
  ('Martyrdom of the Báb', 6, 17, true, 'MARTYRDOMBAB', null),
  ('Day of the Covenant', 14, 4, false, null, null),
  ('Ascension of ‘Abdu’l‑Bahá', 14, 6, false, null, null),
];

/// The Days of Remembrance part each Holy Day tag names (GTK `HOLY_DAYS`).
const holyDayParts = {
  'NAWRUZ': 'Naw-Rúz',
  'RIDVAN': 'Riḍván',
  'DECLARATIONBAB': 'Declaration of the Báb',
  'MARTYRDOMBAB': 'Martyrdom of the Báb',
  'ASCENSIONBAHAULLAH': 'Ascension of Bahá’u’lláh',
  'BIRTHBAB': 'Birth of the Báb',
  'BIRTHBAHAULLAH': 'Birth of Bahá’u’lláh',
};

/// Prayer categories for the periods without a Holy Day of their own.
const ayyamPrayers = 'Intercalary Days';
const fastPrayers = 'The Fast';
const daysOfNote = 30;
const fastNearDays = 30;

/// The calendar over the published table.
class BadiCalendar {
  BadiCalendar(List<Map<String, dynamic>> rows) : _rows = {for (final r in rows) (r['year'] as num).toInt(): r};

  /// From the table's JSON (`{"years": [...]}`); a damaged table leaves the calendar empty.
  factory BadiCalendar.fromJson(Object? data) {
    try {
      return BadiCalendar([for (final r in (data as Map)['years'] as List) (r as Map).cast<String, dynamic>()]);
    } catch (_) {
      return BadiCalendar(const []);
    }
  }

  final Map<int, Map<String, dynamic>> _rows;

  DateTime? nawRuz(int year) => _rows[year] == null ? null : parseDay(_rows[year]!['naw_ruz'] as String);
  int _ayyamDays(int year) => (_rows[year]!['ayyam_i_ha_days'] as num).toInt();

  DateTime? toGregorian(BadiDate b) {
    if (!_rows.containsKey(b.year)) return null;
    final start = nawRuz(b.year)!;
    final int days;
    if (b.month == intercalary) {
      days = 18 * monthDays + b.day - 1;
    } else if (b.month == fastMonth) {
      days = 18 * monthDays + _ayyamDays(b.year) + b.day - 1;
    } else {
      days = (b.month - 1) * monthDays + b.day - 1;
    }
    return addDays(start, days);
  }

  int? yearLength(int year) => _rows.containsKey(year) ? 19 * monthDays + _ayyamDays(year) : null;

  /// The Badí‘ date falling on a Gregorian day (it began at sunset the evening before), or null outside the table.
  BadiDate? fromGregorian(DateTime date) {
    if (_rows.isEmpty) return null;
    final md = date.month * 100 + date.day;
    var year = md >= 322 ? date.year - 1843 : date.year - 1844;
    if ((md == 320 || md == 321) && _rows.containsKey(year + 1) && !date.isBefore(nawRuz(year + 1)!)) year += 1;
    if (!_rows.containsKey(year) || date.isBefore(nawRuz(year)!)) return null;
    var days = daysBetween(nawRuz(year)!, date);
    if (days >= yearLength(year)!) return null;
    if (days < 18 * monthDays) return BadiDate(year, days ~/ monthDays + 1, days % monthDays + 1);
    days -= 18 * monthDays;
    final extra = _ayyamDays(year);
    if (days < extra) return BadiDate(year, intercalary, days + 1);
    return BadiDate(year, fastMonth, days - extra + 1);
  }

  List<Event> holyDays(int year) {
    final row = _rows[year];
    if (row == null) return [];
    Event event(String name, int month, int d, bool suspended, [String? readings, String? prayers]) {
      final b = BadiDate(year, month, d);
      return Event('holy', name, b, toGregorian(b)!, workSuspended: suspended, readings: readings, prayers: prayers);
    }

    Map<String, dynamic> m(String key) => (row[key] as Map).cast<String, dynamic>();
    final twin = [
      event('Birth of the Báb', monthNumber(m('birth_bab')['month'] as String), (m('birth_bab')['day'] as num).toInt(), true,
          'BIRTHBAB'),
      event('Birth of Bahá’u’lláh', monthNumber(m('birth_bahaullah')['month'] as String),
          (m('birth_bahaullah')['day'] as num).toInt(), true, 'BIRTHBAHAULLAH'),
    ];
    return [for (final f in _fixedHolyDays) event(f.$1, f.$2, f.$3, f.$4, f.$5, f.$6), ...twin]
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Event> feasts(int year) {
    if (!_rows.containsKey(year)) return [];
    return [
      for (var month = 1; month <= 19; month++)
        Event('feast', 'Feast of ${months[month - 1].$1}', BadiDate(year, month, 1), toGregorian(BadiDate(year, month, 1))!,
            meaning: months[month - 1].$2, prayers: month == fastMonth ? 'The Fast' : null),
    ];
  }

  List<Event> events(int year) => [...holyDays(year), ...feasts(year)]
    ..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : (a.kind == 'holy' ? 0 : 1).compareTo(b.kind == 'holy' ? 0 : 1);
    });

  /// Holy Days and Feasts from this Gregorian day on, within [days], as far as dates are published.
  List<Event> upcoming(DateTime date, [int days = 365]) {
    final first = fromGregorian(date);
    if (first == null) return [];
    final last = addDays(date, days);
    return [
      for (var y = first.year; y < first.year + 3; y++)
        for (final e in events(y))
          if (!e.date.isBefore(date) && !e.date.isAfter(last)) e,
    ];
  }

  Event? nextFeast(DateTime date) => upcoming(date, 40).where((e) => e.kind == 'feast').firstOrNull;
  Event? nextHolyDay(DateTime date) => upcoming(date).where((e) => e.kind == 'holy').firstOrNull;

  /// The nineteen months and Ayyám-i-Há, in order, with their Gregorian dates.
  List<Period> yearMonths(int year) {
    if (!_rows.containsKey(year)) return [];
    final periods = <Period>[];
    void add(int month, int length) {
      final b = BadiDate(year, month, 1);
      final first = toGregorian(b)!;
      periods.add(Period(b.monthName, b.meaning, b, first, addDays(first, length - 1)));
    }

    for (var m = 1; m <= 18; m++) {
      add(m, monthDays);
    }
    add(intercalary, _ayyamDays(year));
    add(fastMonth, monthDays);
    return periods;
  }

  (DateTime, DateTime)? fastDays(int year) {
    final first = toGregorian(BadiDate(year, fastMonth, 1));
    return first == null ? null : (first, addDays(first, monthDays - 1));
  }

  int? fastDay(DateTime date) {
    final b = fromGregorian(date);
    return b != null && b.month == fastMonth ? b.day : null;
  }

  DateTime? nextFast(DateTime date) {
    final b = fromGregorian(date);
    if (b == null) return null;
    final span = fastDays(b.year)!;
    return !date.isAfter(span.$1) ? span.$1 : null;
  }

  Period? ayyamIHaOf(int year) => yearMonths(year).where((p) => p.badi.month == intercalary).firstOrNull;

  Period? nextAyyamIHa(DateTime date) {
    final b = fromGregorian(date);
    final p = b == null ? null : ayyamIHaOf(b.year);
    return p != null && !date.isAfter(p.last) ? p : null;
  }

  /// During the Fast, its day; else its first day if it is near; else null.
  ({int? day, DateTime date})? fastState(DateTime observed) {
    final n = fastDay(observed);
    if (n != null) return (day: n, date: observed);
    final first = nextFast(observed);
    return first != null && daysBetween(observed, first) <= fastNearDays ? (day: null, date: first) : null;
  }
}

String eventSummary(Event e, DateTime today) {
  if (e.date == today) return 'Today.';
  if (e.begins == today) return 'Begins at sunset today.';
  return 'Begins at sunset on ${gregorianText(e.begins)}.';
}

// ----- places and the sun -----

/// Sunrise, noon and sunset hours the user entered, in minutes after midnight, standing in for the sun.
class ClockHours {
  const ClockHours(this.sunrise, this.noon, this.sunset);
  final int sunrise, noon, sunset;

  static ClockHours? clean(Object? value) {
    if (value is! Map) return null;
    final f = [value['sunrise'], value['noon'], value['sunset']];
    if (!f.every((n) => n is int && n >= 0 && n < 1440)) return null;
    final (a, b, c) = (f[0] as int, f[1] as int, f[2] as int);
    return a < b && b < c ? ClockHours(a, b, c) : null;
  }

  Map<String, int> toJson() => {'sunrise': sunrise, 'noon': noon, 'sunset': sunset};
}

/// Minutes after midnight from "HH:MM" or "H:MM", or null.
int? parseClock(String text) {
  final m = RegExp(r'^(\d+):(\d\d)$').firstMatch(text.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  return h < 24 && min < 60 ? h * 60 + min : null;
}

/// A saved location: a label, coordinates rounded to two decimals and an IANA time zone.
class Place {
  const Place({required this.label, required this.lat, required this.lon, required this.zone, this.clock});
  final String label;
  final double lat, lon;

  /// Null only for a clock-only place (clock hours without a location): then this computer's zone is used.
  final String? zone;
  final ClockHours? clock;

  bool get hasLocation => zone != null;

  /// The saved place, or null if unusable (GTK `clean_place()`).
  static Place? clean(Object? value) {
    if (value is! Map) return null;
    final lat = value['lat'], lon = value['lon'], zone = value['tz'];
    if (lat is! num || lon is! num || !lat.isFinite || !lon.isFinite) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180 || zone is! String || !validZone(zone)) return null;
    double r(num n) => (n * 100).round() / 100;
    final label = value['label'] is String ? (value['label'] as String).split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ') : '';
    return Place(label: label.isEmpty ? '${r(lat)}, ${r(lon)}' : label, lat: r(lat), lon: r(lon), zone: zone);
  }

  Map<String, Object> toJson() => {'label': label, 'lat': lat, 'lon': lon, 'tz': zone!};

  /// The saved location (or only this computer's zone) with entered hours standing in for the sun.
  static Place withClock(Place? location, ClockHours hours) => Place(
      label: location?.label ?? 'Clock times', lat: location?.lat ?? 0, lon: location?.lon ?? 0, zone: location?.zone, clock: hours);

  tz.Location get location => zone != null ? zoneOf(zone!) : tz.local;
}

tz.Location zoneOf(String name) {
  try {
    return tz.getLocation(name);
  } catch (_) {
    return tz.local;
  }
}

bool validZone(String name) {
  try {
    tz.getLocation(name);
    return true;
  } catch (_) {
    return tz.timeZoneDatabase.locations.isEmpty;
  }
}

class SunTimes {
  const SunTimes(this.date, this.sunrise, this.noon, this.sunset, this.polar, {this.clock = false});
  final DateTime date;
  final tz.TZDateTime? sunrise;
  final tz.TZDateTime noon;
  final tz.TZDateTime? sunset;

  /// `day` when the sun does not set, `night` when it does not rise.
  final String? polar;
  final bool clock;
}

const _sunAltitude = 90.833;
double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;
final _j2000 = DateTime.utc(2000, 1, 1, 12);

double _century(DateTime moment) => moment.difference(_j2000).inMicroseconds / 1e6 / 86400 / 36525;

/// (equation of time in minutes, declination in degrees): NOAA's solar calculation, after Meeus.
(double, double) _sun(double t) {
  final meanLong = _rad((280.46646 + t * (36000.76983 + t * 0.0003032)) % 360);
  final anomaly = _rad(357.52911 + t * (35999.05029 - 0.0001537 * t));
  final ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  final centre = math.sin(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(2 * anomaly) * (0.019993 - 0.000101 * t) +
      math.sin(3 * anomaly) * 0.000289;
  final omega = _rad(125.04 - 1934.136 * t);
  final apparent = _rad(_deg(meanLong) + centre - 0.00569 - 0.00478 * math.sin(omega));
  final meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
  final obliquity = _rad(meanObliquity + 0.00256 * math.cos(omega));
  final declination = _deg(math.asin(math.sin(obliquity) * math.sin(apparent)));
  final y = math.pow(math.tan(obliquity / 2), 2).toDouble();
  final equation = y * math.sin(2 * meanLong) -
      2 * ecc * math.sin(anomaly) +
      4 * ecc * y * math.sin(anomaly) * math.cos(2 * meanLong) -
      0.5 * y * y * math.sin(4 * meanLong) -
      1.25 * ecc * ecc * math.sin(2 * anomaly);
  return (_deg(equation) * 4, declination);
}

(double?, String?) _hourAngle(double latitude, double declination) {
  final lat = _rad(latitude), dec = _rad(declination);
  final value = math.cos(_rad(_sunAltitude)) / (math.cos(lat) * math.cos(dec)) - math.tan(lat) * math.tan(dec);
  if (value < -1) return (null, 'day');
  if (value > 1) return (null, 'night');
  return (_deg(math.acos(value)), null);
}

DateTime _plusMinutes(DateTime t, double minutes) => t.add(Duration(microseconds: (minutes * 60e6).round()));

/// Sunrise, solar noon and sunset of the solar day whose noon falls on this local date, in that zone.
SunTimes sunTimes(DateTime date, double latitude, double longitude, tz.Location zone) {
  latitude = latitude.clamp(-89.99, 89.99);
  var base = DateTime.utc(date.year, date.month, date.day);
  DateTime noonOf(DateTime d) {
    var moment = _plusMinutes(d, 720 - 4 * longitude);
    for (var i = 0; i < 2; i++) {
      moment = _plusMinutes(d, 720 - 4 * longitude - _sun(_century(moment)).$1);
    }
    return moment;
  }

  var noon = noonOf(base);
  for (var i = 0; i < 2; i++) {
    final local = dayOf(tz.TZDateTime.from(noon, zone));
    if (local == date) break;
    base = base.add(Duration(days: local.isBefore(date) ? 1 : -1));
    noon = noonOf(base);
  }
  (tz.TZDateTime?, String?) event(bool rise) {
    var moment = noon;
    String? reason;
    for (var i = 0; i < 3; i++) {
      final (equation, declination) = _sun(_century(moment));
      final (angle, why) = _hourAngle(latitude, declination);
      reason = why;
      if (angle == null) return (null, reason);
      moment = _plusMinutes(base, 720 - 4 * (longitude + (rise ? angle : -angle)) - equation);
    }
    return (tz.TZDateTime.from(moment, zone), null);
  }

  final (sunrise, whyRise) = event(true);
  final (sunset, whySet) = event(false);
  return SunTimes(date, sunrise, tz.TZDateTime.from(noon, zone), sunset, whySet ?? whyRise);
}

tz.TZDateTime _atMinutes(tz.Location zone, DateTime date, int minutes) =>
    tz.TZDateTime(zone, date.year, date.month, date.day, minutes ~/ 60, minutes % 60);

/// Sun times at a saved place, or the entered hours in their place, or null without either.
SunTimes? placeSun(Place? place, DateTime date) {
  if (place == null) return null;
  final hours = place.clock;
  if (hours != null) {
    final z = place.location;
    return SunTimes(date, _atMinutes(z, date, hours.sunrise), _atMinutes(z, date, hours.noon), _atMinutes(z, date, hours.sunset),
        null,
        clock: true);
  }
  if (!place.hasLocation) return null;
  return sunTimes(date, place.lat, place.lon, place.location);
}

String sunSummary(SunTimes sun, String Function(tz.TZDateTime) clock) {
  final parts = [
    if (sun.sunrise != null) 'sunrise ${clock(sun.sunrise!)}',
    'noon ${clock(sun.noon)}',
    if (sun.sunset != null) 'sunset ${clock(sun.sunset!)}',
  ];
  var text = parts.join(', ');
  text = text[0].toUpperCase() + text.substring(1);
  if (sun.polar == 'day') text += '. The sun does not set today.';
  if (sun.polar == 'night') text += '. The sun does not rise today.';
  return text;
}

/// The time now (or at [moment]) at the place, or in this computer's zone.
tz.TZDateTime localNow(Place? place, [DateTime? moment]) {
  final m = moment ?? DateTime.now();
  return tz.TZDateTime.from(m, place?.zone != null ? place!.location : tz.local);
}

bool _before(DateTime a, DateTime b) => a.microsecondsSinceEpoch < b.microsecondsSinceEpoch;

/// The Gregorian day whose Badí‘ date is current: with a place the next Badí‘ day begins at local sunset.
DateTime observedDate(tz.TZDateTime moment, Place? place) {
  final today = dayOf(moment);
  if (place == null) return today;
  final before = placeSun(place, addDays(today, -1));
  if (before?.sunset != null && _before(moment, before!.sunset!)) return addDays(today, -1);
  final sun = placeSun(place, today);
  if (sun?.sunset != null && !_before(moment, sun!.sunset!)) return addDays(today, 1);
  return today;
}

// ----- the Alláh-u-Abhá counter -----
class Counter {
  Counter([int? target]) : target = validTarget(target) ?? defaultTarget;
  static const defaultTarget = 95;
  static const presets = [95, 19, 9];
  static const limit = 9999;
  int count = 0;
  int target;

  static int? validTarget(Object? value) {
    if (value is String) value = int.tryParse(value.trim());
    return value is int && value >= 1 && value <= limit ? value : null;
  }

  bool get done => count >= target;
  bool add() {
    if (done) return false;
    count++;
    return true;
  }

  bool undo() {
    if (count == 0) return false;
    count--;
    return true;
  }

  void reset() => count = 0;
  bool setTarget(Object? value) {
    final t = validTarget(value);
    if (t == null) return false;
    target = t;
    count = math.min(count, t);
    return true;
  }

  /// Screen readers are told only at every nineteenth and at the target, so counting isn't drowned out (GTK).
  bool get milestone => count > 0 && (done || count % 19 == 0);

  @override
  String toString() => '$count of $target';
}

// ----- obligatory prayer times -----
const prayerNames = {'short': 'Short Obligatory Prayer', 'medium': 'Medium Obligatory Prayer', 'long': 'Long Obligatory Prayer'};
const longPeriods = [
  ('sunset', 'Sunset to sunset'),
  ('noon', 'Noon to noon'),
  ('midnight', 'Midnight to midnight'),
  ('rolling', '24 hours since last said'),
];
const longDefaultPeriod = 'sunset';
const longGuidance =
    '“The beginning of the 24-hour period for the recitation of the Long Obligatory Prayer has not been specifically stated in the Sacred Texts, and the Universal House of Justice has not made any ruling on this point.” (Letter written on its behalf, 17 December 1990)';
const eveningHours = 2;
const clockSunrise = 6, clockNoon = 12, clockSunset = 18;
const partNames = {'morning': 'Morning', 'noon': 'Noon', 'evening': 'Evening'};
const _saidLabels = {'morning': 'Said this morning', 'noon': 'Said at noon', 'evening': 'Said this evening'};

class Window {
  const Window(this.prayer, this.part, this.date, this.opens, this.closes);
  final String prayer;

  /// `noon`; or `morning`, `noon`, `evening` for the medium prayer; for the long prayer its period or `at:<seconds>`.
  final String part;
  final DateTime date;
  final tz.TZDateTime opens, closes;
  String get key => '${isoDay(date)}:$prayer:$part';
  bool isOpen(DateTime moment) => !_before(moment, opens) && _before(moment, closes);
  bool isPast(DateTime moment) => !_before(moment, closes);
}

tz.TZDateTime clockTime(DateTime date, int hour) => tz.TZDateTime(tz.local, date.year, date.month, date.day, hour);

/// The windows of a prayer on a day: empty for the long prayer, and where the sun does not rise or set.
List<Window> prayerWindows(String prayer, DateTime date, Place? place) {
  if (prayer != 'short' && prayer != 'medium') return [];
  tz.TZDateTime sunrise, noon, sunset;
  if (place != null) {
    final sun = placeSun(place, date);
    if (sun == null || sun.sunrise == null || sun.sunset == null) return [];
    (sunrise, noon, sunset) = (sun.sunrise!, sun.noon, sun.sunset!);
  } else {
    (sunrise, noon, sunset) = (clockTime(date, clockSunrise), clockTime(date, clockNoon), clockTime(date, clockSunset));
  }
  final afternoon = Window(prayer, 'noon', date, noon, sunset);
  if (prayer == 'short') return [afternoon];
  final eveningEnd = tz.TZDateTime.from(sunset.toUtc().add(const Duration(hours: eveningHours)), sunset.location);
  return [Window(prayer, 'morning', date, sunrise, noon), afternoon, Window(prayer, 'evening', date, sunset, eveningEnd)];
}

/// Today, or yesterday while its last window is still open after midnight.
DateTime prayerDay(String prayer, tz.TZDateTime moment, Place? place) {
  final today = dayOf(moment), yesterday = addDays(today, -1);
  return prayerWindows(prayer, yesterday, place).any((w) => w.isOpen(moment)) ? yesterday : today;
}

/// The window open now, or else the next one to open.
Window? currentWindow(String prayer, tz.TZDateTime moment, Place? place) {
  final today = dayOf(moment);
  for (final d in [addDays(today, -1), today, addDays(today, 1)]) {
    for (final w in prayerWindows(prayer, d, place)) {
      if (!w.isPast(moment)) return w;
    }
  }
  return null;
}

bool isTracked(String? prayer) => prayer == 'short' || prayer == 'medium' || prayer == 'long';

tz.TZDateTime atHour(DateTime date, int hour, Place? place) =>
    place?.zone != null ? tz.TZDateTime(place!.location, date.year, date.month, date.day, hour) : clockTime(date, hour);

tz.TZDateTime _periodEnd(DateTime date, Place? place) {
  final sun = placeSun(place, date);
  return sun?.sunset ?? atHour(addDays(date, 1), 0, place);
}

tz.TZDateTime _noonOf(DateTime date, Place? place) => placeSun(place, date)?.noon ?? atHour(date, clockNoon, place);

String longPeriod(String? chosen) => longPeriods.any((p) => p.$1 == chosen) ? chosen! : longDefaultPeriod;

(DateTime, int)? _longMark(Iterable<String> said, DateTime moment) {
  (DateTime, int)? found;
  for (final key in said) {
    final parts = key.split(':');
    if (parts.length == 4 && parts[1] == 'long' && parts[2] == 'at' && int.tryParse(parts[3]) != null) {
      final at = int.parse(parts[3]);
      if (moment.millisecondsSinceEpoch / 1000 < at + 86400 && (found == null || at > found.$2)) found = (parseDay(parts[0]), at);
    }
  }
  return found;
}

/// The long prayer's current twenty-four hours under the chosen period.
Window longWindow(String? period, tz.TZDateTime moment, Place? place, Iterable<String> said) {
  final mode = longPeriod(period);
  final today = dayOf(moment);
  if (mode == 'rolling') {
    final mark = _longMark(said, moment);
    final (d, at) = mark ?? (today, moment.millisecondsSinceEpoch ~/ 1000);
    return Window('long', 'at:$at', d, tz.TZDateTime.fromMillisecondsSinceEpoch(moment.location, at * 1000),
        tz.TZDateTime.fromMillisecondsSinceEpoch(moment.location, (at + 86400) * 1000));
  }
  if (mode == 'sunset') {
    final d = observedDate(moment, place);
    return Window('long', mode, d, _periodEnd(addDays(d, -1), place), _periodEnd(d, place));
  }
  if (mode == 'noon') {
    final d = !_before(moment, _noonOf(today, place)) ? today : addDays(today, -1);
    return Window('long', mode, d, _noonOf(d, place), _noonOf(addDays(d, 1), place));
  }
  return Window('long', mode, today, atHour(today, 0, place), atHour(addDays(today, 1), 0, place));
}

String longLine(String? period, Window w, bool marked, String Function(tz.TZDateTime) clock) {
  final mode = longPeriod(period);
  if (mode == 'rolling') {
    if (marked) return 'Said at ${clock(w.opens)}. The 24 hours end at ${clock(w.closes)}.';
    return 'Mark it when you say it. The 24 hours run from then.';
  }
  return '${longPeriods.firstWhere((p) => p.$1 == mode).$2}: this period ends at ${clock(w.closes)}.';
}

String saidLabel(Window w) {
  if (w.prayer == 'long') return w.part.startsWith('at:') ? 'Said' : 'Said today';
  return w.prayer == 'short' ? 'Said today' : _saidLabels[w.part]!;
}

/// Whether a window is open, and when it opens or closes. It never says anything was missed.
String windowLine(Window w, tz.TZDateTime moment, String Function(tz.TZDateTime) clock) {
  if (w.isOpen(moment)) return 'Open now, until ${clock(w.closes)}';
  if (w.isPast(moment)) return 'Its time has ended (${clock(w.opens)} to ${clock(w.closes)})';
  return 'Opens at ${clock(w.opens)}, until ${clock(w.closes)}';
}

/// Marks worth keeping: all of them, or with the history off only what the current day needs.
List<String> pruneSaid(List<String> said, DateTime today, {bool keepHistory = true}) {
  if (keepHistory) return said;
  final oldest = isoDay(addDays(today, -1));
  return [for (final k in said) if (k.length >= 10 && k.substring(0, 10).compareTo(oldest) >= 0) k];
}

/// A time as the desktop's clock shows it: 12-hour ("5:28 PM") where the locale uses it, else 24-hour ("17:28").
String formatClock(DateTime m, {required bool twelveHour}) {
  final mm = m.minute.toString().padLeft(2, '0');
  if (!twelveHour) return '${m.hour.toString().padLeft(2, '0')}:$mm';
  final h = m.hour % 12 == 0 ? 12 : m.hour % 12;
  return '$h:$mm ${m.hour < 12 ? 'AM' : 'PM'}';
}

/// Regions whose usual clock is 12-hour, for [formatClock].
const twelveHourRegions = {'US', 'CA', 'AU', 'NZ', 'PH', 'IN', 'PK', 'BD', 'EG', 'SA', 'MY'};
