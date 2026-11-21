/// The first-run import of the GTK Bahá’í Reader's settings, highlights, notes, saved passages and collections.
///
/// The GTK file (`$XDG_CONFIG_HOME/bahai-reader/settings.json`) is only ever read: it is opened once for reading, never
/// written, moved, renamed or deleted, and neither are its `settings.json.bad*` backups, the rest of
/// `~/.config/bahai-reader/` or `~/.local/share/bahai-reader/`. A missing or damaged file imports nothing and is left as
/// it is.
///
/// The rule, so that importing twice changes nothing and never undoes a change made in this app:
/// * Marks are merged, never replaced. A highlight is added unless this app already has one on the same passage that
///   overlaps it (one colour per word; this app's highlight, with its note, wins). Saved passages, "Said"/"Fasted"
///   records and sent reminders are added when missing. Collections are matched by name (ignoring case); a passage goes
///   into a collection only if it is in none here yet. Reading positions are added for books that have none here.
/// * Settings with no value here yet (location, clock hours, prayer, the Long prayer's period and nudge, the counter's
///   target, reading font, interface font, line spacing, margins, Side by side, the last passage, section and book,
///   reminder switches not set here) are copied. Settings that always have a value (appearance, text size, language,
///   keeping records, the highlight colour, Continue reading) are copied only on the first run, when this app had no
///   settings file of its own.
/// * Not imported: `keep_running` (turning it on writes a login entry; doing that unasked would start a second background
///   reminder process at login beside the GTK app's), `sidebar_width` (this window sizes its sidebar as a share of the
///   width, as the GTK libadwaita window does) and `writings_by` (the GTK classic window's grouping; Writings here are
///   always listed by author, as in the GTK libadwaita window). Unknown keys are ignored.
library;

import 'dart:convert';
import 'dart:io';

import '../calendar/badi.dart';
import '../calendar/reminders.dart';
import '../marks/highlight.dart';
import 'settings_store.dart';

/// What an import found and did.
class GtkImport {
  GtkImport(this.status, {this.problem});

  /// `imported`, `missing` (no GTK settings file) or `damaged` (it could not be read or is not a settings file).
  final String status;
  final String? problem;
  int highlights = 0, saved = 0, collections = 0, positions = 0, records = 0;

  /// The GTK keys whose values were copied into this app's settings.
  final List<String> settings = [];

  bool get done => status != 'damaged';

  /// A sentence for people, or null when there was nothing to say.
  String? get message {
    if (status == 'missing') return null;
    if (status == 'damaged') {
      return 'The GTK Bahá’í Reader’s settings could not be read ($problem), so nothing was imported from it. '
          'Its file was left as it is.';
    }
    final parts = [
      if (highlights > 0) '$highlights highlight${highlights == 1 ? '' : 's'} and notes',
      if (saved > 0) '$saved saved passage${saved == 1 ? '' : 's'}',
      if (collections > 0) '$collections collection${collections == 1 ? '' : 's'}',
      if (settings.isNotEmpty) 'your settings',
    ];
    if (parts.isEmpty) return 'Nothing new to import from the GTK Bahá’í Reader.';
    final list = parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    return 'Imported $list from the GTK Bahá’í Reader. Its own files were not changed.';
  }
}

/// GTK `theme` values and this app's.
const gtkThemes = {'Omarchy': 'system', 'Light': 'light', 'Dark': 'dark', 'Sepia': 'sepia'};

/// Reads the GTK settings file (read only) and merges it into [into]. [fresh]: this app had no settings file of its own.
Future<GtkImport> importGtk(Settings into, {File? source, required bool fresh}) async {
  final file = source ?? gtkSettingsFile();
  final String text;
  try {
    if (!await file.exists()) return GtkImport('missing');
    text = await file.readAsString();
  } on FileSystemException catch (e) {
    return GtkImport('damaged', problem: e.osError?.message ?? e.message);
  }
  Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException {
    data = null;
  }
  if (data is! Map) return GtkImport('damaged', problem: 'it is not a settings file');
  return mergeGtk(into, data, fresh: fresh);
}

/// Merges a GTK settings map into [into] by the rule above. [data] is not changed.
GtkImport mergeGtk(Settings into, Map data, {required bool fresh}) {
  final result = GtkImport('imported');
  void took(String key) => result.settings.add(key);

  // ----- marks -----
  for (final h in cleanHighlights(data['highlights'])) {
    final overlaps = into.highlights.any((r) => r.id == h.id && r.start < h.end && h.start < r.end);
    if (!overlaps) {
      into.highlights.add(h);
      result.highlights++;
    }
  }
  final gtkSaved = [
    for (final s in data['saved'] is List ? data['saved'] as List : const [])
      if (s is String) s,
  ];
  // Every passage filed in a GTK collection counts as saved there, as GTK's own cleaning makes it.
  final gtkCollections = cleanCollections(data['collections'], gtkSaved);
  for (final id in gtkSaved) {
    if (!into.saved.contains(id)) {
      into.saved.add(id);
      result.saved++;
    }
  }
  final filed = {for (final c in into.collections) ...c.items};
  for (final c in gtkCollections) {
    var target = into.collections.where((x) => x.name.toLowerCase() == c.name.toLowerCase()).firstOrNull;
    if (target == null) {
      into.collections.add(target = Collection(c.name));
      result.collections++;
    }
    for (final id in c.items) {
      if (filed.add(id)) target.items.add(id);
    }
  }
  final records = data['records'] is Map ? data['records'] as Map : const {};
  for (final (list, key, pattern) in [(into.said, 'said', saidPattern), (into.fasted, 'fasted', dayPattern)]) {
    for (final k in records[key] is List ? records[key] as List : const []) {
      if (k is String && pattern.hasMatch(k) && !list.contains(k)) {
        list.add(k);
        result.records++;
      }
    }
  }
  for (final k in data['reminders_sent'] is List ? data['reminders_sent'] as List : const []) {
    if (k is String &&
        dayPattern.hasMatch(k.length >= 10 ? k.substring(0, 10) : k) &&
        !into.remindersSent.contains(k)) {
      into.remindersSent.add(k);
    }
  }
  final positions = data['positions'];
  if (positions is Map) {
    for (final e in positions.entries) {
      if (e.key is String && e.value is String && !into.positions.containsKey(e.key)) {
        into.positions[e.key as String] = e.value as String;
        result.positions++;
      }
    }
  }
  final expanded = data['expanded'];
  if (expanded is Map) {
    for (final e in expanded.entries) {
      if (e.key is! String || e.value is! bool) continue;
      // The Hidden Words is a section of its own in GTK and a book in Writings here.
      final key = (e.key as String).startsWith('hidden/')
          ? 'writings/The Hidden Words/${(e.key as String).substring(7)}'
          : e.key as String;
      into.expanded.putIfAbsent(key, () => e.value as bool);
    }
  }

  // ----- settings with no value here yet -----
  final place = Place.clean(data['location']);
  if (into.location == null && place != null) {
    into.location = place;
    took('location');
  }
  final hours = ClockHours.clean(data['clock_hours']);
  if (into.clockHours == null && hours != null) {
    into.clockHours = hours;
    took('clock_hours');
  }
  if (into.prayer == null && const ['short', 'medium', 'long', 'none'].contains(data['prayer'])) {
    into.prayer = data['prayer'] as String;
    took('prayer');
  }
  if (into.longPeriod == null && longPeriods.any((p) => p.$1 == data['long_period'])) {
    into.longPeriod = data['long_period'] as String;
    took('long_period');
  }
  final lead = data['long_lead_hours'];
  if (into.longLeadHours == null && lead is int && longLead(lead) == lead) {
    into.longLeadHours = lead;
    took('long_lead_hours');
  }
  final target = Counter.validTarget(data['counter_target']);
  if (into.counterTarget == null && target != null) {
    into.counterTarget = target;
    took('counter_target');
  }
  if (data['reminders'] is Map) {
    var any = false;
    for (final e in (data['reminders'] as Map).entries) {
      if (reminderSwitches.contains(e.key) && e.value is bool && !into.reminders.containsKey(e.key)) {
        into.reminders[e.key as String] = e.value as bool;
        any = true;
      }
    }
    if (any) took('reminders');
  }
  if (into.font == null && data['font'] is String && (data['font'] as String).isNotEmpty) {
    into.font = data['font'] as String;
    took('font');
  }
  if (into.chromeFont == null && Settings.chromeFonts.contains(data['chrome_font'])) {
    into.chromeFont = data['chrome_font'] as String;
    took('chrome_font');
  }
  final spacing = clampSetting(data['spacing'], 0, 20), margin = clampSetting(data['margin'], 24, 160);
  if (into.spacing == null && spacing != null) {
    into.spacing = spacing;
    took('spacing');
  }
  if (into.margin == null && margin != null) {
    into.margin = margin;
    took('margin');
  }
  final compare = data['compare'];
  if (into.compare == null && compare is int) {
    into.compare = compare;
    took('compare');
  }
  if (into.last == null && data['last'] is String) {
    into.last = data['last'] as String;
    took('last');
  }
  if (into.section == null) {
    final section = data['section'] == 'gleanings' ? 'writings' : data['section'];
    if (Settings.sections.contains(section)) {
      into.section = section as String;
      took('section');
    }
  }
  if (into.book == null && data['book'] is String) {
    into.book = data['book'] as String;
    took('book');
  }

  // ----- settings that always have a value: only on the first run -----
  if (fresh) {
    if (gtkThemes[data['theme']] case final theme?) {
      into.theme = theme;
      took('theme');
    }
    if (clampSetting(data['size'], 15, 36) case final size?) {
      into.textSize = size.toDouble();
      took('size');
    }
    final language = data['language'];
    if (language is int) {
      into.language = language;
      took('language');
    }
    if (data['keep_records'] is bool) {
      into.keepRecords = data['keep_records'] as bool;
      took('keep_records');
    }
    if (cleanHighlightColor(data['highlight_color']) case final color?) {
      into.highlightColor = color;
      took('highlight_color');
    }
    final recent = data['recent'];
    if (recent is List && into.recent.isEmpty) {
      into.recent = [
        ...{
          for (final b in recent)
            if (b is String) b,
        },
      ].take(Settings.recentBooks).toList();
      if (into.recent.isNotEmpty) took('recent');
    }
  }
  if (result.highlights > 0 || result.saved > 0) into.importedGtk = true;
  return result;
}

/// GTK `SAID_KEY` and `DAY_KEY`.
final saidPattern = RegExp(
  r'^\d{4}-\d\d-\d\d:((short|medium):(morning|noon|evening)|long:(sunset|noon|midnight|at:\d+))$',
);
final dayPattern = RegExp(r'^\d{4}-\d\d-\d\d$');
