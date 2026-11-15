import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
    this.textSize = 20,
    this.highlightColor = 'yellow',
    List<Highlight>? highlights,
    List<String>? saved,
    Map<String, String>? positions,
    this.importedGtk = false,
  })  : highlights = highlights ?? [],
        saved = saved ?? [],
        positions = positions ?? {};

  /// `system`, `light` or `dark`.
  String theme;
  int language;
  double textSize;
  String highlightColor;
  List<Highlight> highlights;

  /// Saved passages (bookmarks): passage ids, as in GTK `prefs["saved"]`.
  List<String> saved;

  /// The last passage read in each work: {work title: passage id}.
  Map<String, String> positions;
  bool importedGtk;

  static const themes = ['system', 'light', 'dark'];

  Map<String, Object> toJson() => {
        'theme': theme,
        'language': language,
        'size': textSize,
        'highlight_color': highlightColor,
        'highlights': [for (final h in highlights) h.toJson()],
        'saved': saved,
        'positions': positions,
        'imported_gtk': importedGtk,
      };

  /// Drops or replaces values of the wrong type, keeping everything usable (like GTK `clean_settings()`).
  factory Settings.fromJson(Object? data) {
    final j = data is Map ? data : const {};
    final size = j['size'];
    final saved = j['saved'];
    final positions = j['positions'];
    return Settings(
      theme: themes.contains(j['theme']) ? j['theme'] as String : 'system',
      language: j['language'] is int ? j['language'] as int : 1,
      textSize: size is num && size.isFinite ? size.toDouble().clamp(15, 36) : 20,
      highlightColor: highlightColors.contains(j['highlight_color']) ? j['highlight_color'] as String : 'yellow',
      highlights: cleanHighlights(j['highlights']),
      saved: saved is List ? [...{for (final s in saved) if (s is String) s}] : [],
      positions: positions is Map
          ? {for (final e in positions.entries) if (e.key is String && e.value is String) e.key as String: e.value as String}
          : {},
      importedGtk: j['imported_gtk'] == true,
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

  /// Writes atomically: a temporary file in the same folder, then a rename.
  Future<void> save(Settings settings) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(settings.toJson()), flush: true);
    await tmp.rename(file.path);
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
