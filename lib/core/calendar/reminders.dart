/// Reminders: a port of the reminder half of the GTK app's `badi.py`, checked against it (test/reminders_test.dart).
///
/// A pure function of the wall clock and what has been sent, so nothing relies on a long timer, and restarts, suspend
/// and changes of the clock or time zone cost nothing: the caller asks every 30 seconds what is due now
/// ([dueReminders]). Sending them is the platform's job (see `core/platform/notifier.dart`).
library;

import 'package:timezone/timezone.dart' as tz;

import 'badi.dart';

/// The switches in Location & reminders, under the GTK app's keys.
const reminderSwitches = ['prayer', 'long', 'feast', 'holy', 'fast', 'fast_daily'];

const nudgeMinutes = 30;
const sentDays = 3;
const feastHour = 15; // the afternoon of the day a Feast begins at sunset
const holyDayHour = 9;
const fastNoticeDays = [5, 3, 1];
const fastLeadMinutes = 30;
const longLeadDefault = 2, longLeadMin = 1, longLeadMax = 12; // hours before the Long prayer's period resets

/// The hours before the Long prayer's period resets for its nudge: the saved value if valid, else the default.
int longLead(Object? hours) => hours is int && hours >= longLeadMin && hours <= longLeadMax ? hours : longLeadDefault;

class Reminder {
  const Reminder(this.id, this.group, this.title, this.body, this.at, this.until, {this.said, this.opens = 'today'});

  /// Starts with the date it belongs to.
  final String id;

  /// At most one reminder per group is shown at a time; a later one replaces it.
  final String group;
  final String title, body;

  /// Due from this moment; stale from [until], and never sent after it.
  final tz.TZDateTime at, until;

  /// The mark a "Said today" action sets, and which stops the reminder when already set.
  final String? said;

  /// What "Open" opens: `today` or `prayer:<short|medium|long>`.
  final String opens;
}

/// What the reminders need to know from the settings.
class ReminderSettings {
  const ReminderSettings({this.switches = const {}, this.prayer, this.longPeriod, this.longLeadHours});
  final Map<String, bool> switches;
  final String? prayer, longPeriod;
  final int? longLeadHours;
  bool on(String key) => switches[key] ?? false;
}

tz.TZDateTime _shift(tz.TZDateTime t, Duration d) => tz.TZDateTime.from(t.toUtc().add(d), t.location);
bool _before(DateTime a, DateTime b) => a.microsecondsSinceEpoch < b.microsecondsSinceEpoch;

/// When a prayer's window opens, and about 30 minutes before it closes if it has not been said yet.
List<Reminder> prayerReminders(String prayer, DateTime date, Place? place, String Function(tz.TZDateTime) clock) {
  final found = <Reminder>[];
  if (!isTracked(prayer)) return found;
  for (final w in prayerWindows(prayer, date, place)) {
    final title = prayer == 'short' ? prayerNames[prayer]! : '${prayerNames[prayer]}: ${partNames[w.part]!.toLowerCase()}';
    found.add(Reminder('${w.key}:opens', 'prayer:$prayer', title, 'Its time is open, until ${clock(w.closes)}.', w.opens, w.closes,
        said: w.key, opens: 'prayer:$prayer'));
    final nudge = _shift(w.closes, const Duration(minutes: -nudgeMinutes));
    if (_before(w.opens, nudge)) {
      found.add(Reminder('${w.key}:closing', 'prayer:$prayer', title, 'Its time closes at ${clock(w.closes)}.', nudge, w.closes,
          said: w.key, opens: 'prayer:$prayer'));
    }
  }
  return found;
}

/// One nudge, a set time before the Long prayer's period resets, only if it isn't marked. With "rolling" there is
/// nothing to reset until it has been said, so the nudge comes before the 24 hours since it was last said end. The
/// prayer is for when one feels moved to it, so there is no alarm at a fixed time.
List<Reminder> longReminders(ReminderSettings s, tz.TZDateTime moment, Place? place, String Function(tz.TZDateTime) clock,
    Iterable<String> said) {
  final w = longWindow(s.longPeriod, moment, place, said);
  final rolling = longPeriod(s.longPeriod) == 'rolling';
  if (rolling && !said.contains(w.key)) return [];
  final at = _shift(w.closes, Duration(hours: -longLead(s.longLeadHours)));
  if (!_before(w.opens, at)) return [];
  final body = rolling
      ? 'The 24 hours since you last said it end at ${clock(w.closes)}.'
      : 'Not marked yet. This period ends at ${clock(w.closes)}.';
  return [
    Reminder('${w.key}:closing', 'prayer:long', prayerNames['long']!, body, at, w.closes,
        said: rolling ? null : w.key, opens: 'prayer:long'),
  ];
}

tz.TZDateTime _sunsetOrClock(DateTime date, Place? place) => placeSun(place, date)?.sunset ?? atHour(date, clockSunset, place);

/// A Feast, on the afternoon of the day it begins at sunset. A Holy Day, the afternoon before, and on the day.
List<Reminder> eventReminders(Event e, Place? place) {
  final begins = e.begins;
  final sunset = _sunsetOrClock(begins, place);
  // Where the sun sets before the usual hour, an hour before sunset instead.
  final usual = atHour(begins, feastHour, place), early = _shift(sunset, const Duration(hours: -1));
  final afternoon = _before(early, usual) ? early : usual;
  final title = e.meaning != null && e.meaning!.isNotEmpty ? '${e.name} (${e.meaning})' : e.name;
  final note = e.workSuspended ? ' Work is suspended.' : '';
  return [
    Reminder('${isoDay(begins)}:${e.kind}:${e.name}:before', '${e.kind}:${isoDay(e.date)}', title, 'Begins at sunset today.$note',
        afternoon, sunset),
    if (e.kind == 'holy')
      Reminder('${isoDay(e.date)}:holy:${e.name}:day', 'holy:${isoDay(e.date)}', title, 'Today.$note',
          atHour(e.date, holyDayHour, place), _sunsetOrClock(e.date, place)),
  ];
}

/// 5, 3 and 1 days before the Fast.
List<Reminder> fastNoticeReminders(BadiCalendar cal, DateTime today, Place? place) {
  final first = cal.nextFast(today);
  if (first == null) return [];
  return [
    for (final days in fastNoticeDays)
      if (addDays(first, -days) case final d)
        Reminder('${isoDay(d)}:fast:notice', 'fast:${isoDay(d)}', 'The Fast',
            'The Fast begins at sunrise ${days == 1 ? 'tomorrow' : 'on ${gregorianText(first)}'}.',
            atHour(d, holyDayHour, place), atHour(d, clockSunset + 3, place)),
  ];
}

/// Each day of the Fast, before sunrise and at sunset. Clock times without a location; none where the sun does not
/// rise or set.
List<Reminder> fastDailyReminders(BadiCalendar cal, DateTime date, Place? place, String Function(tz.TZDateTime) clock) {
  final number = cal.fastDay(date);
  if (number == null) return [];
  tz.TZDateTime sunrise, sunset;
  if (place != null) {
    final sun = placeSun(place, date);
    if (sun == null || sun.sunrise == null || sun.sunset == null) return [];
    (sunrise, sunset) = (sun.sunrise!, sun.sunset!);
  } else {
    (sunrise, sunset) = (atHour(date, clockSunrise, null), atHour(date, clockSunset, null));
  }
  final d = isoDay(date);
  return [
    Reminder('$d:fast:sunrise', 'fastday:$d', 'The Fast', 'Day $number of $monthDays. Sunrise is at ${clock(sunrise)}.',
        _shift(sunrise, const Duration(minutes: -fastLeadMinutes)), sunrise),
    Reminder('$d:fast:sunset', 'fastday:$d', 'The Fast', 'Day $number of $monthDays. Sunset is at ${clock(sunset)}.', sunset,
        _shift(sunset, const Duration(hours: 1))),
  ];
}

/// Every reminder turned on, around this moment.
List<Reminder> candidateReminders(BadiCalendar cal, ReminderSettings s, tz.TZDateTime moment, Place? place,
    String Function(tz.TZDateTime) clock,
    [Iterable<String> said = const []]) {
  final found = <Reminder>[];
  final today = dayOf(moment);
  final days = [addDays(today, -1), today, addDays(today, 1)];
  final prayer = s.prayer;
  if (s.on('prayer') && prayer != null) {
    for (final d in days) {
      found.addAll(prayerReminders(prayer, d, place, clock));
    }
  }
  if (s.on('long') && prayer == 'long') found.addAll(longReminders(s, moment, place, clock, said));
  for (final e in cal.upcoming(addDays(today, -1), 3)) {
    if (s.on(e.kind == 'holy' ? 'holy' : 'feast')) found.addAll(eventReminders(e, place));
  }
  if (s.on('fast')) found.addAll(fastNoticeReminders(cal, today, place));
  if (s.on('fast_daily')) {
    for (final d in days) {
      found.addAll(fastDailyReminders(cal, d, place, clock));
    }
  }
  return found;
}

/// (reminders to send now, ids to mark as sent). Each is sent at most once and only while still in its time; after a
/// long sleep a stale one is simply skipped, and of those still due only the latest of each group goes out.
(List<Reminder>, List<String>) dueReminders(BadiCalendar cal, ReminderSettings s, tz.TZDateTime moment, Place? place,
    String Function(tz.TZDateTime) clock, Iterable<String> sent, Iterable<String> said) {
  final sentSet = sent.toSet(), saidSet = said.toSet();
  final chosen = <String, Reminder>{};
  final marked = <String>[];
  for (final r in candidateReminders(cal, s, moment, place, clock, saidSet)) {
    if (sentSet.contains(r.id) || _before(moment, r.at) || !_before(moment, r.until)) continue;
    marked.add(r.id);
    if (r.said != null && saidSet.contains(r.said)) continue;
    final best = chosen[r.group];
    if (best == null || _before(best.at, r.at)) chosen[r.group] = r;
  }
  return (chosen.values.toList(), marked);
}

/// Forget what was sent more than a few days ago; the date starts each id.
List<String> pruneSent(List<String> sent, DateTime today) {
  final oldest = isoDay(addDays(today, -sentDays));
  return [for (final k in sent) if (k.length >= 10 && k.substring(0, 10).compareTo(oldest) >= 0) k];
}
