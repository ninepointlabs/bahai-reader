/// What the Today page and Home's cards say, as plain data: a port of the GTK app's `today.py` (`today_content()`,
/// `prayer_card()`, `fast_card()`) and the Today calendar in the sidebar (`contents.py` `build_calendar()`).
/// "Reminders…" buttons open Location & reminders, as in the GTK app.
library;

import 'package:timezone/timezone.dart' as tz;

import '../library/library.dart';
import '../library/passage.dart';
import '../settings/settings_store.dart';
import 'badi.dart';

/// What a button on a card does; the window carries it out.
sealed class TodayAction {
  const TodayAction();
}

/// Opens the Today page.
class OpenToday extends TodayAction {
  const OpenToday();
}

/// Opens Location & reminders.
class OpenLocation extends TodayAction {
  const OpenLocation();
}

class OpenCounter extends TodayAction {
  const OpenCounter();
}

/// Opens the first of [passages] among them, with [label] over its heading.
class OpenGroup extends TodayAction {
  const OpenGroup(this.passages, this.label);
  final List<Passage> passages;
  final String label;
}

/// Opens a passage in the Obligatory prayers section (a prayer or its guidance).
class OpenObligatory extends TodayAction {
  const OpenObligatory(this.passage, [this.label]);
  final Passage passage;
  final String? label;
}

/// Opens a passage where it belongs (its book), with [label] over its heading.
class OpenPassage extends TodayAction {
  const OpenPassage(this.passage, this.label);
  final Passage passage;
  final String label;
}

/// Marks or unmarks "Said" for a window key, or "Fasted" for a date.
class MarkSaid extends TodayAction {
  const MarkSaid(this.key, {this.long = false});
  final String key;

  /// The long prayer's key is worked out again at the click (with "24 hours since last said" it starts then).
  final bool long;
}

class MarkFasted extends TodayAction {
  const MarkFasted(this.key);
  final String key;
}

enum RowKind { title, large, text, dim, reading, button, toggle }

class TodayRow {
  const TodayRow(this.kind, this.text, {this.action, this.active = false});
  final RowKind kind;
  final String text;
  final TodayAction? action;

  /// For a toggle: whether it is on.
  final bool active;
}

typedef Clock = String Function(tz.TZDateTime);

/// Everything Today needs to know: the calendar, the library, the settings, the time and how to show a time.
class TodayContext {
  TodayContext({required this.calendar, required this.library, required this.settings, required this.moment, required this.clock});
  final BadiCalendar calendar;
  final Library library;
  final Settings settings;
  final tz.TZDateTime moment;
  final Clock clock;

  Place? get place => settings.place;
  late final DateTime observed = observedDate(moment, place);

  /// Opens a Holy Day's or Feast's readings (Days of Remembrance), else its prayers; null if this library has neither.
  TodayAction? eventOpener(Event e) {
    final part = e.readings == null ? null : holyDayParts[e.readings];
    if (part != null) {
      final readings = library.readingsFor(part);
      if (readings.isNotEmpty) return OpenGroup(readings, 'Readings for ${e.name}');
    }
    return prayerOpener(e.prayers, 'Prayers for ${e.name}');
  }

  TodayAction? prayerOpener(String? category, String label) {
    if (category == null) return null;
    final prayers = library.prayersIn(category);
    return prayers.isEmpty ? null : OpenGroup(prayers, label);
  }

  TodayAction? aqdasOpener(String part, int number, {bool obligatory = false}) {
    final p = library.aqdas(part, number);
    if (p == null) return null;
    return obligatory ? OpenObligatory(p) : OpenPassage(p, 'Kitáb-i-Aqdas, $part');
  }

  Passage? prayerItem(String chosen) => library.prayersIn(prayerNames[chosen]!).firstOrNull;

  Window? said(String? prayer) {
    if (!isTracked(prayer)) return null;
    if (prayer == 'long') return longWindow(settings.longPeriod, moment, place, settings.said);
    return currentWindow(prayer!, moment, place);
  }
}

/// {card: rows} for the Today page: date, sun, prayer, counter, events, fast, passage.
Map<String, List<TodayRow>> todayContent(TodayContext c) {
  final cal = c.calendar, moment = c.moment, place = c.place, observed = c.observed;
  final today = cal.fromGregorian(observed);
  final calendarDay = dayOf(moment);
  final sun = placeSun(place, calendarDay);
  final cards = <String, List<TodayRow>>{};
  TodayRow t(String s) => TodayRow(RowKind.text, s);
  TodayRow dim(String s) => TodayRow(RowKind.dim, s);
  TodayRow title(String s) => TodayRow(RowKind.title, s);
  TodayRow button(String s, TodayAction? a) => TodayRow(RowKind.button, s, action: a);

  // Date
  final date = <TodayRow>[];
  if (today != null) {
    date.add(TodayRow(RowKind.large, '$today'));
    final evening = observed != calendarDay;
    date.add(t(gregorianText(calendarDay, year: true) +
        (observed.isAfter(calendarDay) ? ', after sunset' : evening ? ', before sunset' : '')));
    date.add(t(today.month == intercalary
        ? '$ayyamIHa: the days before the month of ‘Alá’.'
        : 'The month of ${today.monthName}: ${today.meaning}.'));
    if (place == null) {
      date.add(dim('The Bahá’í day begins at sunset. Without a location, this date follows the calendar day.'));
    } else if (sun != null && sun.clock) {
      date.add(dim('The Bahá’í day begins at sunset. Here this date changes at the sunset hour you set.'));
    } else if (sun?.polar == 'day') {
      date.add(dim('The Bahá’í day begins at sunset. The sun does not set here today, so this date follows the calendar day.'));
    } else if (sun?.polar == 'night') {
      date.add(dim('The Bahá’í day begins at sunset. The sun does not rise here today, so this date follows the calendar day.'));
    } else {
      date.add(dim('The Bahá’í day begins at sunset.'));
    }
  } else {
    date
      ..add(t(gregorianText(calendarDay, year: true)))
      ..add(t(unpublished))
      ..add(dim('Badí‘ dates here come from the Universal House of Justice’s table for 172 to 221 B.E.'));
  }
  cards['date'] = date;

  // Sun
  final sunRows = <TodayRow>[title(sun != null && sun.clock ? 'Clock times' : 'Sun')];
  if (sun != null && sun.clock) {
    sunRows.addAll([
      t('Sunrise hour: ${c.clock(sun.sunrise!)}'),
      t('Noon hour: ${c.clock(sun.noon)}'),
      t('Sunset hour: ${c.clock(sun.sunset!)}'),
      dim('Hours you set, used instead of the sun.'),
      button('Change clock times…', const OpenLocation()),
    ]);
  } else if (sun != null) {
    if (sun.sunrise != null) sunRows.add(t('Sunrise: ${c.clock(sun.sunrise!)}'));
    sunRows.add(t('Solar noon: ${c.clock(sun.noon)}'));
    if (sun.sunset != null) sunRows.add(t('Sunset: ${c.clock(sun.sunset!)}'));
    if (sun.polar == 'day') sunRows.add(t('The sun does not set today.'));
    if (sun.polar == 'night') sunRows.add(t('The sun does not rise today.'));
    sunRows
      ..add(dim(place!.label))
      ..add(button('Change location…', const OpenLocation()));
  } else {
    sunRows
      ..add(t('Add your location to see sunrise, noon and sunset'))
      ..add(button('Add location…', const OpenLocation()));
  }
  cards['sun'] = sunRows;

  final prayer = prayerCard(c);
  if (prayer != null) cards['prayer'] = prayer;

  cards['counter'] = [title('Alláh-u-Abhá'), dim('Kitáb-i-Aqdas ¶18'), button('Open the counter', const OpenCounter())];

  // Next Feast and Holy Day
  final events = <TodayRow>[title('Next Feast and Holy Day')];
  final feast = cal.nextFeast(observed), holy = cal.nextHolyDay(observed);
  if (feast != null) {
    events
      ..add(t('${feast.name} (${feast.meaning})'))
      ..add(dim(eventSummary(feast, observed)));
    final opener = c.eventOpener(feast);
    if (opener != null) events.add(button('Prayers for ${feast.name}', opener));
  }
  if (holy != null) {
    events
      ..add(t(holy.name))
      ..add(dim(eventSummary(holy, observed) + (holy.workSuspended ? ' Work is suspended.' : ' Work is not suspended.')));
    final part = holy.readings == null ? null : holyDayParts[holy.readings];
    if (part != null && c.library.readingsFor(part).isNotEmpty) {
      events.add(button('Readings for ${holy.name}', c.eventOpener(holy)));
    }
    final opener = c.prayerOpener(holy.prayers, 'Prayers for ${holy.name}');
    if (opener != null) events.add(button('Prayers for ${holy.name}', opener));
  }
  final ayyam = cal.nextAyyamIHa(observed);
  if (ayyam != null && daysBetween(observed, ayyam.first) <= daysOfNote) {
    events
      ..add(t(ayyamIHa))
      ..add(dim(!ayyam.first.isAfter(observed) ? 'Now.' : 'Begins at sunset on ${gregorianText(addDays(ayyam.first, -1))}.'));
    final opener = c.prayerOpener(ayyamPrayers, 'Prayers for $ayyamIHa');
    if (opener != null) events.add(button('Prayers for $ayyamIHa', opener));
  }
  if (feast == null && holy == null) {
    events.add(t(unpublished));
  } else {
    events.add(button('Reminders…', const OpenLocation()));
  }
  cards['events'] = events;

  final fast = fastCard(c);
  if (fast != null) cards['fast'] = fast;

  final passage = c.library.passageOfTheDay(ordinal(calendarDay));
  if (passage != null) {
    cards['passage'] = [
      title('Passage of the day'),
      TodayRow(RowKind.reading, openingOf(passage)),
      if (passage.citation.isNotEmpty) dim('— ${passage.citation}'),
      button('Read the passage of the day', OpenPassage(passage, 'Passage of the day')),
    ];
  }
  return cards;
}

/// A passage's opening words, about 240 characters, without its paragraph numbers.
String openingOf(Passage p) {
  final opening = p.unnumbered.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (opening.length <= 240) return opening;
  final cut = opening.substring(0, 240);
  final sp = cut.lastIndexOf(' ');
  return '${sp > 0 ? cut.substring(0, sp) : cut}…';
}

/// The chosen prayer's times and Said state; a prompt when none is chosen; null with "Don't track".
List<TodayRow>? prayerCard(TodayContext c) {
  final chosen = c.settings.prayer, place = c.place, moment = c.moment;
  if (chosen == 'none') return null;
  final rows = <TodayRow>[const TodayRow(RowKind.title, 'Obligatory prayer')];
  if (chosen == null) {
    return rows
      ..add(const TodayRow(RowKind.text, 'Choose which obligatory prayer you say to see its times here.'))
      ..add(const TodayRow(RowKind.button, 'Choose a prayer…', action: OpenLocation()));
  }
  final name = prayerNames[chosen]!;
  rows.add(TodayRow(RowKind.text, name));
  if (chosen == 'long') {
    rows.add(const TodayRow(RowKind.text,
        'Once in twenty-four hours, at whatever time you find yourself in a state of humbleness and longing adoration.'));
    final guidance = c.aqdasOpener('Questions and Answers', 82, obligatory: true);
    if (guidance != null) rows.add(TodayRow(RowKind.button, 'Read the guidance (Question and Answer 82)', action: guidance));
    final w = longWindow(c.settings.longPeriod, moment, place, c.settings.said);
    final marked = c.settings.said.contains(w.key);
    rows
      ..add(TodayRow(RowKind.text, longLine(c.settings.longPeriod, w, marked, c.clock)))
      ..add(TodayRow(RowKind.toggle, saidLabel(w), action: MarkSaid(w.key, long: true), active: marked))
      ..add(const TodayRow(RowKind.dim, longGuidance))
      ..add(const TodayRow(RowKind.dim, 'So the period is your choice, in Location & reminders. This app makes no ruling.'));
  } else {
    final windows = prayerWindows(chosen, prayerDay(chosen, moment, place), place);
    if (windows.isEmpty) {
      rows.add(const TodayRow(RowKind.text,
          'The sun does not rise or set here today, so its times cannot be taken from the sun. In such regions the Kitáb-i-Aqdas says to gauge the times of prayer by clocks.'));
      final g = c.aqdasOpener('Text', 10, obligatory: true);
      if (g != null) rows.add(TodayRow(RowKind.button, 'Read the guidance (¶10)', action: g));
      rows
        ..add(const TodayRow(RowKind.dim, clockAssembly))
        ..add(const TodayRow(RowKind.button, 'Use clock times…', action: OpenLocation()));
    }
    for (final w in windows) {
      final label = windowLine(w, moment, c.clock);
      rows.add(TodayRow(RowKind.text, chosen == 'short' ? label : '${partNames[w.part]}: $label'));
      if (w.part == 'morning' && moment.isBefore(w.closes)) {
        rows.add(const TodayRow(RowKind.dim, 'The morning prayer may be said as early as dawn (Note 5).'));
      }
      rows.add(TodayRow(RowKind.toggle, saidLabel(w), action: MarkSaid(w.key), active: c.settings.said.contains(w.key)));
    }
    if (windows.isNotEmpty && place?.clock != null) rows.add(const TodayRow(RowKind.dim, 'These use the clock times you set.'));
    if (windows.isNotEmpty && place == null) {
      rows
        ..add(const TodayRow(RowKind.dim, 'Without a location these use the clock instead of the sun. Add a location to follow the sun.'))
        ..add(const TodayRow(RowKind.button, 'Add location…', action: OpenLocation()));
    }
    if (windows.isNotEmpty) {
      final g = c.aqdasOpener('Questions and Answers', 83, obligatory: true);
      if (g != null) rows.add(TodayRow(RowKind.button, 'Read the guidance (Question and Answer 83)', action: g));
    }
  }
  final item = c.prayerItem(chosen);
  if (item != null) rows.add(TodayRow(RowKind.button, 'Open the $name', action: OpenObligatory(item)));
  if (isTracked(chosen)) rows.add(const TodayRow(RowKind.button, 'Reminders…', action: OpenLocation()));
  return rows;
}

/// During the month of ‘Alá’ its day, the fasting hours and a private check; near it, when it begins; otherwise null.
List<TodayRow>? fastCard(TodayContext c) {
  final state = c.calendar.fastState(c.observed);
  if (state == null) return null;
  final rows = <TodayRow>[const TodayRow(RowKind.title, 'The Fast')];
  final place = c.place;
  if (state.day == null) {
    rows.add(TodayRow(RowKind.text, 'The Fast begins at sunrise on ${gregorianText(state.date)}.'));
  } else {
    rows.add(TodayRow(RowKind.text, 'Day ${state.day} of $monthDays'));
    final sun = placeSun(place, state.date);
    if (sun != null && sun.sunrise != null && sun.sunset != null) {
      rows.add(TodayRow(
          RowKind.text,
          sun.clock
              ? 'Fasting hours, by the clock times you set: ${c.clock(sun.sunrise!)} to ${c.clock(sun.sunset!)}'
              : 'Fasting hours: sunrise at ${c.clock(sun.sunrise!)} to sunset at ${c.clock(sun.sunset!)}'));
    } else if (sun != null) {
      rows.add(const TodayRow(RowKind.text,
          'The sun does not rise or set here today. In such regions the Kitáb-i-Aqdas says to gauge the times by clocks.'));
      final g = c.aqdasOpener('Notes', 17);
      if (g != null) rows.add(TodayRow(RowKind.button, 'Read the guidance (Note 17)', action: g));
      rows
        ..add(const TodayRow(RowKind.dim, clockAssembly))
        ..add(const TodayRow(RowKind.button, 'Use clock times…', action: OpenLocation()));
    } else {
      rows
        ..add(const TodayRow(RowKind.text, 'The fasting hours run from sunrise to sunset.'))
        ..add(const TodayRow(RowKind.button, 'Add location…', action: OpenLocation()));
    }
    final key = isoDay(state.date);
    rows.add(TodayRow(RowKind.toggle, 'Fasted today', action: MarkFasted(key), active: c.settings.fasted.contains(key)));
  }
  final prayers = c.prayerOpener(fastPrayers, 'Prayers for the Fast');
  if (prayers != null) rows.add(TodayRow(RowKind.button, 'Prayers for the Fast', action: prayers));
  final about = c.aqdasOpener('Text', 16);
  if (about != null) rows.add(TodayRow(RowKind.button, 'Read about the Fast (¶16)', action: about));
  rows.add(const TodayRow(RowKind.button, 'Reminders…', action: OpenLocation()));
  return rows;
}

/// Home's three cards: the date, the obligatory prayer's state, the passage of the day (GTK `refresh_home()`).
List<(String, String?, List<TodayRow>)> homeCards(TodayContext c) {
  final cards = todayContent(c);
  final date = [
    ...cards['date']!.where((r) => r.kind != RowKind.dim).take(3),
    const TodayRow(RowKind.button, 'Open Today', action: OpenToday()),
  ];
  final prayer = cards['prayer']
      ?.where((r) => r.kind != RowKind.button || r.text.startsWith('Open the '))
      .toList();
  final passage = cards['passage'];
  return [
    ('date', 'Today', date),
    if (prayer != null) ('prayer', null, prayer),
    if (passage != null) ('passage', null, passage),
  ];
}

/// A row of the Today calendar in the sidebar: a name, its dates, and what choosing it opens (if anything).
class CalendarRow {
  const CalendarRow(this.group, this.name, this.detail, this.action);
  final String group, name, detail;
  final TodayAction? action;
}

/// Upcoming Holy Days and Feasts, then this Badí‘ year's months (GTK `build_calendar()`).
List<CalendarRow> calendarRows(TodayContext c) {
  final cal = c.calendar, day = c.observed;
  final today = cal.fromGregorian(day);
  if (today == null) return const [];
  final rows = <CalendarRow>[];
  for (final e in cal.upcoming(day)) {
    var detail = '${gregorianText(e.date)}. ${eventSummary(e, day)}';
    if (e.workSuspended) detail += ' Work is suspended.';
    rows.add(CalendarRow('Upcoming', e.meaning != null ? '${e.name} (${e.meaning})' : e.name, detail, c.eventOpener(e)));
  }
  final thisYear = 'This year, ${today.year} B.E.';
  for (final p in cal.yearMonths(today.year)) {
    final prayers = p.badi.month == intercalary
        ? ayyamPrayers
        : p.badi.month == fastMonth
            ? fastPrayers
            : null;
    rows.add(CalendarRow(thisYear, p.meaning != null ? '${p.name} (${p.meaning})' : p.name,
        '${gregorianText(p.first)} to ${gregorianText(p.last)}', c.prayerOpener(prayers, 'Prayers for ${p.name}')));
  }
  return rows;
}
