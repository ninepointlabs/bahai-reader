import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../calendar/badi.dart';
import '../calendar/reminders.dart';
import '../marks/highlight.dart';

/// This experiment's own settings file. It never reads from or writes to the GTK app's `~/.config/bahai-reader/`
/// except [importFromGtk], which only reads a copy.
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
  })  : reminders = reminders ?? {},
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

  ReminderSettings get reminderSettings =>
      ReminderSettings(switches: reminders, prayer: prayer, longPeriod: longPeriod, longLeadHours: longLeadHours);

  /// Where the day's times come from: the location, with entered clock hours in place of the sun if any.
  Place? get place => clockHours != null ? Place.withClock(location, clockHours!) : location;

  static const themes = ['system', 'light', 'dark', 'sepia'];
  static const recentBooks = 6;

  Map<String, Object> toJson() => {
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
      };

  /// Drops or replaces values of the wrong type, keeping everything usable (like GTK `clean_settings()`).
  factory Settings.fromJson(Object? data) {
    final j = data is Map ? data : const {};
    final size = j['size'];
    final saved = j['saved'];
    final positions = j['positions'];
    final recent = j['recent'];
    final records = j['records'] is Map ? j['records'] as Map : const {};
    List<String> strings(Object? v) => v is List ? [for (final s in v) if (s is String) s] : [];
    return Settings(
      theme: themes.contains(j['theme']) ? j['theme'] as String : 'system',
      language: j['language'] is int ? j['language'] as int : 1,
      textSize: size is num && size.isFinite ? size.toDouble().clamp(15, 36) : 22,
      highlightColor: highlightColors.contains(j['highlight_color']) ? j['highlight_color'] as String : 'yellow',
      highlights: cleanHighlights(j['highlights']),
      saved: saved is List ? [...{for (final s in saved) if (s is String) s}] : [],
      positions: positions is Map
          ? {for (final e in positions.entries) if (e.key is String && e.value is String) e.key as String: e.value as String}
          : {},
      recent: recent is List ? [...{for (final r in recent) if (r is String) r}].take(recentBooks).toList() : [],
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
      remindersSent: [for (final k in strings(j['reminders_sent'])) if (RegExp(r'^\d{4}-\d\d-\d\d').hasMatch(k)) k],
      keepRunning: j['keep_running'] == true,
    );
  }
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
    } else {
      dir = await getApplicationSupportDirectory();
    }
    return SettingsStore(File('${dir.path}/settings.json'));
  }

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
    return (Settings(), 'Your settings file could not be read, so default settings are in use. It was kept as ${backup.path}.');
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

/// Copies highlights and saved passages from the GTK app's settings into [into]. The GTK file is only read.
/// Returns (highlights added, saved passages added), or throws if the file cannot be read.
Future<(int, int)> importFromGtk(Settings into, {File? source}) async {
  final data = jsonDecode(await (source ?? gtkSettingsFile()).readAsString());
  if (data is! Map) throw const FormatException('Not a settings file');
  var marks = 0, saved = 0;
  for (final h in cleanHighlights(data['highlights'])) {
    if (!into.highlights.contains(h)) {
      into.highlights.add(h);
      marks++;
    }
  }
  final ids = data['saved'];
  if (ids is List) {
    for (final id in ids) {
      if (id is String && !into.saved.contains(id)) {
        into.saved.add(id);
        saved++;
      }
    }
  }
  into.importedGtk = true;
  return (marks, saved);
}
