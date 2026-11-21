import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../calendar/badi.dart';
import '../calendar/reminders.dart';
import '../marks/highlight.dart';
import 'android_backup.dart';

/// This experiment's own settings file. It never reads from or writes to the GTK app's `~/.config/bahai-reader/`
/// except the GTK import (`gtk_import.dart`), which only reads it.
///
/// Linux: `$XDG_CONFIG_HOME/bahai-reader-flutter/settings.json` (default `~/.config/bahai-reader-flutter/`).
/// Elsewhere: Flutter's application support directory.
class Settings {
  Settings({
    this.theme = 'system',
    this.language = 1,
    this.textSize = 22,
    this.highlightColor = 'yellow',
    List<Highlight>? highlights,
    List<String>? saved,
    Map<String, String>? positions,
    List<String>? recent,
    this.importedGtk = false,
    this.location,
    this.clockHours,
    this.prayer,
    this.longPeriod,
    this.keepRecords = true,
    List<String>? said,
    List<String>? fasted,
    this.counterTarget,
    Map<String, bool>? reminders,
    this.longLeadHours,
    List<String>? remindersSent,
    this.keepRunning = false,
    this.askedExactTimes = false,
    this.font,
    this.chromeFont,
    this.spacing,
    this.margin,
    this.compare,
    List<Collection>? collections,
    Map<String, bool>? expanded,
    this.last,
    this.section,
    this.book,
    this.gtkImport,
    this.userdataVersion,
    Map<String, Object?>? legacy,
  }) : legacy = legacy ?? {},
       collections = collections ?? [],
       expanded = expanded ?? {},
       reminders = reminders ?? {},
       remindersSent = remindersSent ?? [],
       said = said ?? [],
       fasted = fasted ?? [],
       highlights = highlights ?? [],
       saved = saved ?? [],
       positions = positions ?? {},
       recent = recent ?? [];

  /// `system` (the Omarchy theme where there is one, else the system's light or dark), `light`, `dark` or `sepia`.
  String theme;
  int language;
  double textSize;
  String highlightColor;
  List<Highlight> highlights;

  /// Saved passages (bookmarks): passage ids, as in GTK `prefs["saved"]`.
  List<String> saved;

  /// The last passage read in each work: {work title: passage id}.
  Map<String, String> positions;

  /// Books read most recently, newest first (GTK `prefs["recent"]`), for Continue reading.
  List<String> recent;
  bool importedGtk;

  // ----- Today and the obligatory prayers (same keys and meanings as the GTK app's settings) -----
  /// Where sunrise, noon and sunset are worked out for; it stays on this device.
  Place? location;

  /// Hours entered to stand in for the sun (where days and nights vary greatly).
  ClockHours? clockHours;

  /// Which obligatory prayer is said: `short`, `medium`, `long`, `none` (don't track), or null (not chosen yet).
  String? prayer;

  /// The Long prayer's twenty-four hours: `sunset`, `noon`, `midnight` or `rolling`.
  String? longPeriod;

  /// Keep a private record of "Said today" and "Fasted today"; off keeps only what the current day needs.
  bool keepRecords;

  /// Marks: `<date>:<prayer>:<part>` for Said, `<date>` for Fasted.
  List<String> said;
  List<String> fasted;
  int? counterTarget;

  // ----- Reminders (GTK keys) -----
  /// Which reminders are on, by [reminderSwitches] key. All are off until turned on.
  Map<String, bool> reminders;

  /// Hours before the Long prayer's period resets for its nudge (1–12; null is the default, 2).
  int? longLeadHours;

  /// Ids of reminders already sent (or skipped), for the last few days, so none is sent twice.
  List<String> remindersSent;

  /// Keep reminders running when the window is closed (Linux: an autostart entry and a hidden window).
  bool keepRunning;

  /// The phone has once offered to allow reminders at the minute ("Alarms & reminders"), so it doesn't ask at every start.
  bool askedExactTimes;

  // ----- reading (GTK keys `font`, `chrome_font`, `spacing`, `margin`, `compare`) -----
  /// The reading font's family, or null for the default (Noto Serif, else DejaVu Serif).
  String? font;

  /// `System` (the desktop's interface font) or `Monospace`; null is System.
  String? chromeFont;

  /// Extra space between wrapped lines, in pixels (0–20; null is 8), and the page's side margins (24–160; null is 80).
  int? spacing, margin;

  /// The language shown beside the passage (Side by side), or null for off.
  int? compare;

  /// Named collections of saved passages, in their own order; a passage is in one at most (GTK `collections`).
  List<Collection> collections;

  /// Contents groups opened or closed by hand: {path: open} (GTK `expanded`).
  Map<String, bool> expanded;

  /// Where the window was: the last passage read, the section and the open book (GTK `last`, `section`, `book`).
  String? last, section, book;

  /// When the first-run import from the GTK app was done, and what it found ({"at", "status"}); null until then.
  Map<String, String>? gtkImport;

  /// Set once highlights, notes, saved passages, collections, positions, Said/Fasted records and the personal choices
  /// in [userDataKeys] live in the user-data store (`userdata.sqlite`, see `lib/core/userdata/`); null before that.
  int? userdataVersion;

  /// The [userDataKeys] values exactly as they were in this file when they moved to the user-data store. They are
  /// written back unchanged, never updated, so an older version of the app opened on this file still finds the marks
  /// as they were at the move.
  Map<String, Object?> legacy;

  /// Keys whose values live in the user-data store once [userdataVersion] is set: what a person made, and the
  /// personal choices that should follow them to another device. Everything else here belongs to this device.
  static const userDataKeys = [
    'highlights',
    'saved',
    'collections',
    'positions',
    'recent',
    'records',
    'prayer',
    'long_period',
    'keep_records',
    'counter_target',
    'highlight_color',
  ];

  /// The [userDataKeys] part of [toJson] as if nothing had moved yet: what the user-data store holds.
  Map<String, Object> userDataJson() {
    final all = _toJson();
    return {
      for (final k in userDataKeys) k: ?all[k],
    };
  }

  int get spacingOrDefault => spacing ?? 8;
  int get marginOrDefault => margin ?? 80;

  ReminderSettings get reminderSettings =>
      ReminderSettings(switches: reminders, prayer: prayer, longPeriod: longPeriod, longLeadHours: longLeadHours);

  /// Where the day's times come from: the location, with entered clock hours in place of the sun if any.
  Place? get place => clockHours != null ? Place.withClock(location, clockHours!) : location;

  static const themes = ['system', 'light', 'dark', 'sepia'];
  static const recentBooks = 6;

  /// This file's contents. Once [userdataVersion] is set, the [userDataKeys] are the frozen [legacy] values.
  Map<String, Object> toJson() {
    final all = _toJson();
    if (userdataVersion == null) return all;
    return {
      for (final e in all.entries)
        if (!userDataKeys.contains(e.key)) e.key: e.value,
      for (final e in legacy.entries) e.key: ?e.value,
      'userdata_version': userdataVersion!,
    };
  }

  Map<String, Object> _toJson() => {
    'theme': theme,
    'language': language,
    'size': textSize,
    'highlight_color': highlightColor,
    'highlights': [for (final h in highlights) h.toJson()],
    'saved': saved,
    'positions': positions,
    'recent': recent,
    'imported_gtk': importedGtk,
    'location': ?location?.toJson(),
    'clock_hours': ?clockHours?.toJson(),
    'prayer': ?prayer,
    'long_period': ?longPeriod,
    'keep_records': keepRecords,
    'records': {'said': said, 'fasted': fasted},
    'counter_target': ?counterTarget,
    'reminders': reminders,
    'long_lead_hours': ?longLeadHours,
    'reminders_sent': remindersSent,
    'keep_running': keepRunning,
    if (askedExactTimes) 'asked_exact_times': true,
    'font': ?font,
    'chrome_font': ?chromeFont,
    'spacing': ?spacing,
    'margin': ?margin,
    'compare': ?compare,
    'collections': [for (final c in collections) c.toJson()],
    'expanded': expanded,
    'last': ?last,
    'section': ?section,
    'book': ?book,
    'gtk_import': ?gtkImport,
  };

  /// Drops or replaces values of the wrong type, keeping everything usable (like GTK `clean_settings()`).
  factory Settings.fromJson(Object? data) {
    final j = data is Map ? data : const {};
    final size = j['size'];
    final saved = j['saved'];
    final positions = j['positions'];
    final recent = j['recent'];
    final records = j['records'] is Map ? j['records'] as Map : const {};
    List<String> strings(Object? v) => v is List
        ? [
            for (final s in v)
              if (s is String) s,
          ]
        : [];
    final savedList = saved is List
        ? [
            ...{
              for (final s in saved)
                if (s is String) s,
            },
          ]
        : <String>[];
    return Settings(
      theme: themes.contains(j['theme']) ? j['theme'] as String : 'system',
      language: j['language'] is int ? j['language'] as int : 1,
      textSize: size is num && size.isFinite ? size.toDouble().clamp(15, 36) : 22,
      highlightColor: cleanHighlightColor(j['highlight_color']) ?? 'yellow',
      highlights: cleanHighlights(j['highlights']),
      saved: savedList,
      positions: positions is Map
          ? {
              for (final e in positions.entries)
                if (e.key is String && e.value is String) e.key as String: e.value as String,
            }
          : {},
      recent: recent is List
          ? [
              ...{
                for (final r in recent)
                  if (r is String) r,
              },
            ].take(recentBooks).toList()
          : [],
      importedGtk: j['imported_gtk'] == true,
      location: Place.clean(j['location']),
      clockHours: ClockHours.clean(j['clock_hours']),
      prayer: const ['short', 'medium', 'long', 'none'].contains(j['prayer']) ? j['prayer'] as String : null,
      longPeriod: longPeriods.any((p) => p.$1 == j['long_period']) ? j['long_period'] as String : null,
      keepRecords: j['keep_records'] is bool ? j['keep_records'] as bool : true,
      said: strings(records['said']),
      fasted: strings(records['fasted']),
      counterTarget: Counter.validTarget(j['counter_target']),
      reminders: j['reminders'] is Map
          ? {
              for (final e in (j['reminders'] as Map).entries)
                if (reminderSwitches.contains(e.key) && e.value is bool) e.key as String: e.value as bool,
            }
          : {},
      longLeadHours: longLead(j['long_lead_hours']) == j['long_lead_hours'] ? j['long_lead_hours'] as int : null,
      remindersSent: [
        for (final k in strings(j['reminders_sent']))
          if (RegExp(r'^\d{4}-\d\d-\d\d').hasMatch(k)) k,
      ],
      keepRunning: j['keep_running'] == true,
      askedExactTimes: j['asked_exact_times'] == true,
      font: j['font'] is String && (j['font'] as String).isNotEmpty ? j['font'] as String : null,
      chromeFont: chromeFonts.contains(j['chrome_font']) ? j['chrome_font'] as String : null,
      spacing: clampSetting(j['spacing'], 0, 20),
      margin: clampSetting(j['margin'], 24, 160),
      compare: j['compare'] is int ? j['compare'] as int : null,
      collections: cleanCollections(j['collections'], savedList),
      expanded: j['expanded'] is Map
          ? {
              for (final e in (j['expanded'] as Map).entries)
                if (e.key is String && e.value is bool) e.key as String: e.value as bool,
            }
          : {},
      last: j['last'] is String ? j['last'] as String : null,
      section: sections.contains(j['section']) ? j['section'] as String : null,
      book: j['book'] is String ? j['book'] as String : null,
      userdataVersion: j['userdata_version'] is int ? j['userdata_version'] as int : null,
      legacy: j['userdata_version'] is int
          ? {
              for (final k in userDataKeys)
                if (j.containsKey(k)) k: j[k],
            }
          : null,
      gtkImport: j['gtk_import'] is Map
          ? {
              for (final e in (j['gtk_import'] as Map).entries)
                if (e.key is String && e.value is String) e.key as String: e.value as String,
            }
          : null,
    );
  }

  static const chromeFonts = ['System', 'Monospace'];

  /// The sections a window can open on (GTK `SHELL_SECTIONS`; `hidden` is the Hidden Words, a book in Writings here).
  static const sections = ['home', 'today', 'prayers', 'obligatory', 'hidden', 'writings', 'study', 'saved'];
}

/// A number setting clamped to its range (GTK `LIMITS`), or null if it is not a number.
int? clampSetting(Object? v, int low, int high) => v is num && v.isFinite ? v.toInt().clamp(low, high) : null;

const unsorted = 'Unsorted';

/// A named collection of saved passages (GTK `{"name", "items"}`).
class Collection {
  Collection(this.name, [List<String>? items, this.uid]) : items = items ?? [];
  String name;
  final List<String> items;

  /// The collection's id in the user-data store, or null until it is first stored. Not part of the GTK shape.
  String? uid;
  Map<String, Object> toJson() => {'name': name, 'items': items};
}

/// A collection's name with its spaces tidied (GTK `collection_name()`).
String collectionName(Object? name) =>
    name is String ? name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ') : '';

/// Usable collections, each passage in one at most; every passage filed in one stays saved, even when the saved list
/// itself was damaged. A nameless entry's passages stay saved (as Unsorted); same-named collections are merged.
/// A port of GTK `clean_collections()`.
List<Collection> cleanCollections(Object? data, List<String> saved) {
  final clean = <Collection>[];
  final filed = <String>{};
  for (final entry in data is List ? data : const []) {
    if (entry is! Map) continue;
    final items = entry['items'] is List
        ? [
            for (final i in entry['items'] as List)
              if (i is String) i,
          ]
        : <String>[];
    for (final i in {...items}) {
      if (!saved.contains(i)) saved.add(i);
    }
    final name = collectionName(entry['name']);
    if (name.isEmpty || name.toLowerCase() == unsorted.toLowerCase()) continue;
    var target = clean.where((c) => c.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    final uid = entry['uid'];
    if (target == null) clean.add(target = Collection(name, null, uid is String && uid.isNotEmpty ? uid : null));
    for (final item in items) {
      if (filed.add(item)) target.items.add(item);
    }
  }
  return clean;
}

class SettingsStore {
  SettingsStore(this.file);
  final File file;

  static Future<SettingsStore> standard() async {
    Directory dir;
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_CONFIG_HOME'];
      final base = xdg != null && xdg.isNotEmpty ? xdg : '${Platform.environment['HOME']}/.config';
      dir = Directory('$base/bahai-reader-flutter');
    } else if (Platform.isAndroid) {
      // In or out of Android's backup, as chosen in Settings (android_backup.dart).
      dir = await userDataFolder(await getApplicationSupportDirectory());
    } else {
      dir = await getApplicationSupportDirectory();
    }
    return SettingsStore(File('${dir.path}/settings.json'));
  }

  /// True when there is no settings file yet: the first run.
  Future<bool> isNew() async => !await file.exists();

  /// The settings, or defaults. An unreadable file is set aside as `settings.json.bad[.n]`, never overwritten.
  Future<(Settings, String?)> load() async {
    if (!await file.exists()) return (Settings(), null);
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map) return (Settings.fromJson(data), null);
    } on FormatException {
      // fall through
    } on FileSystemException catch (e) {
      return (Settings(), 'Your settings could not be read (${e.message}), so default settings are in use.');
    }
    var backup = File('${file.path}.bad');
    for (var n = 1; await backup.exists(); n++) {
      backup = File('${file.path}.bad.$n');
    }
    await file.rename(backup.path);
    return (
      Settings(),
      'Your settings file could not be read, so default settings are in use. It was kept as ${backup.path}.',
    );
  }

  Future<void> _last = Future.value();

  /// Writes atomically: a temporary file in the same folder, then a rename. Saves run one after another (each with the
  /// settings as they were when asked), so two close together never share the temporary file.
  Future<void> save(Settings settings) {
    final text = const JsonEncoder.withIndent(' ').convert(settings.toJson());
    return _last = _last.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    });
  }
}

/// The GTK app's settings file. Read only.
File gtkSettingsFile() {
  final xdg = Platform.environment['XDG_CONFIG_HOME'];
  final base = xdg != null && xdg.isNotEmpty ? xdg : '${Platform.environment['HOME']}/.config';
  return File('$base/bahai-reader/settings.json');
}
