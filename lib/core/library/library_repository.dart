import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'library.dart';
import 'packs.dart';
import 'passage.dart';

/// Where language packs are kept: this app's own folder (its downloads; the only one it writes) and the GTK app's,
/// which is only read, so languages already downloaded there can be read here without downloading them again.
class PackFolders {
  const PackFolders({this.own, this.gtk});
  final Directory? own;
  final Directory? gtk;

  static String _dataHome() {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    return xdg != null && xdg.isNotEmpty ? xdg : '${Platform.environment['HOME']}/.local/share';
  }

  /// Linux: `$XDG_DATA_HOME/bahai-reader-flutter/libraries` and (read only) `$XDG_DATA_HOME/bahai-reader/libraries`.
  static PackFolders standard({Directory? appSupport}) {
    if (Platform.isLinux) {
      final base = _dataHome();
      return PackFolders(own: Directory('$base/bahai-reader-flutter/libraries'), gtk: Directory('$base/bahai-reader/libraries'));
    }
    return PackFolders(own: appSupport == null ? null : Directory('${appSupport.path}/libraries'));
  }

  File? ownPack(int language) => own == null ? null : File('${own!.path}/$language.json');
  File? gtkPack(int language) => gtk == null ? null : File('${gtk!.path}/$language.json');
}

/// Loads libraries: English (and any language bundled with this build) from `assets/library/`, other languages from
/// language packs on disk (see [PackFolders]). Never touches the network; downloading is `downloads.dart`'s, and only
/// when asked.
class LibraryRepository {
  LibraryRepository({AssetBundle? bundle, this.folders = const PackFolders()}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  PackFolders folders;
  final Map<int, Future<Library>> _cache = {};
  List<LanguageInfo>? _bundled;
  Map<String, List<Map<String, dynamic>>>? _catalog;

  /// The languages bundled with this build.
  Future<List<LanguageInfo>> bundledLanguages() async {
    if (_bundled != null) return _bundled!;
    final data = jsonDecode(await _bundle.loadString('assets/library/manifest.json')) as Map<String, dynamic>;
    return _bundled = [for (final l in data['languages'] as List) LanguageInfo.fromJson(l as Map<String, dynamic>)];
  }

  /// The BahaiPrayers.net language catalog: {feed key: [{Id, Name, English, IsLeftToRight, ...}]}. The bundled copy,
  /// updated by a list fetched with "Check available languages" (GTK `catalog()`).
  Future<Map<String, List<Map<String, dynamic>>>> catalog() async {
    if (_catalog != null) return _catalog!;
    Map<String, List<Map<String, dynamic>>> parse(String text) {
      final data = jsonDecode(text);
      if (data is! Map) throw const FormatException('Invalid catalog');
      return {
        for (final e in data.entries)
          if (e.value is List) e.key as String: [for (final r in e.value as List) if (r is Map) r.cast<String, dynamic>()],
      };
    }

    final bundled = parse(await _bundle.loadString('assets/library/languages.json'));
    var merged = bundled;
    final fetched = folders.own == null ? null : File('${folders.own!.path}/languages.json');
    try {
      if (fetched != null && await fetched.exists()) {
        final fresh = {...bundled, ...parse(await fetched.readAsString())};
        if (validCatalog(fresh)) merged = fresh;
      }
    } on Object {
      // A damaged list: the bundled one is still there.
    }
    return _catalog = merged;
  }

  void forgetCatalog() => _catalog = null;

  /// What a language is called, and its direction, from the catalog (or the bundled manifest).
  Future<LanguageInfo> info(int id) async {
    for (final l in await bundledLanguages()) {
      if (l.id == id) return l;
    }
    final row = (await catalog())['prayers']?.where((r) => r['Id'] == id).firstOrNull;
    if (row == null) return LanguageInfo(id: id, name: 'Language $id', english: 'Language $id');
    final name = '${row['Name']}'.replaceAll(RegExp(r'\.$'), '');
    return LanguageInfo(id: id, name: name, english: '${row['English'] ?? name}', rtl: row['IsLeftToRight'] == false);
  }

  /// The pack for a language, as stored, from this app's folder, else the GTK app's; null if neither has a usable one.
  Future<(Map<String, dynamic>, File)?> pack(int language) async {
    for (final file in [folders.ownPack(language), folders.gtkPack(language)]) {
      if (file == null) continue;
      try {
        if (!await file.exists()) continue;
        final data = await compute(_readPack, (file.path, language));
        if (data != null) return (data, file);
      } on Object {
        continue;
      }
    }
    return null;
  }

  /// A pack file that is there but cannot be read (for a notice), or null.
  Future<File?> damagedPack(int language) async {
    for (final file in [folders.ownPack(language), folders.gtkPack(language)]) {
      if (file != null && await file.exists() && (await pack(language)) == null) return file;
    }
    return null;
  }

  /// Every language that can be read offline: the bundled ones, then those with a usable pack on disk.
  Future<List<LanguageInfo>> languages() async {
    final found = [...await bundledLanguages()];
    final ids = <int>{for (final l in found) l.id};
    for (final dir in [folders.own, folders.gtk]) {
      if (dir == null || !await dir.exists()) continue;
      await for (final f in dir.list()) {
        final stem = f.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), '');
        final id = int.tryParse(stem);
        if (f is! File || !f.path.endsWith('.json') || id == null || id == 1 || ids.contains(id)) continue;
        if (await pack(id) != null) {
          ids.add(id);
          found.add(await info(id));
        }
      }
    }
    return found;
  }

  Future<bool> bundles(int language) async => (await bundledLanguages()).any((l) => l.id == language);

  Future<Library> load(int language) => _cache.putIfAbsent(language, () async {
        // This app's own download of a language comes first (it may be newer); then a bundled copy; then the GTK app's.
        final own = folders.ownPack(language);
        if (language != 1 && own != null && await own.exists()) {
          final p = await pack(language);
          if (p != null) return compute(_libraryFromPack, (p.$1, language));
        }
        if (await bundles(language)) {
          final raw = await _bundle.loadString('assets/library/$language.json', cache: false);
          // English is ~13 MB of JSON; decode it off the UI thread.
          return compute(parseLibrary, raw);
        }
        final p = await pack(language);
        if (p == null) throw PackError('The library for language $language is not downloaded or could not be read.');
        return compute(_libraryFromPack, (p.$1, language));
      });

  /// After a download: read the language again.
  void forget(int language) => _cache.remove(language);

  Future<String> calendarTable() => _bundle.loadString('assets/calendar/badi-dates.json');
  Future<String> cityList() => _bundle.loadString('assets/calendar/cities.json', cache: false);

  Future<Map<String, String>> foldTable() async =>
      (jsonDecode(await _bundle.loadString('assets/library/fold.json')) as Map).cast<String, String>();
}

/// A usable catalog: every feed has a list of {Id: int, Name: string} (GTK `catalog()`'s check).
bool validCatalog(Map<String, dynamic> data) => feeds.keys.every((k) {
      final rows = data[k];
      return rows is List && rows.isNotEmpty && rows.every((r) => r is Map && r['Id'] is int && r['Name'] is String);
    });

Map<String, dynamic>? _readPack((String, int) args) => checkPack(jsonDecode(File(args.$1).readAsStringSync()), args.$2);

Library _libraryFromPack((Map<String, dynamic>, int) args) => parseLibrary(packLibraryJson(args.$1, args.$2));

Library parseLibrary(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  return Library(
    (data['language'] as num).toInt(),
    [for (final item in data['items'] as List) Passage.fromJson(item as Map<String, dynamic>)],
    daily: [for (final id in data['daily'] as List? ?? const []) id as String],
    obligatory: [
      for (final g in data['obligatory'] as List? ?? const []) (g[0] as String, [for (final id in g[1] as List) id as String]),
    ],
  );
}
