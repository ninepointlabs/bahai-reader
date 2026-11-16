import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'library.dart';
import 'passage.dart';

/// Loads bundled libraries from `assets/library/`. Never touches the network.
class LibraryRepository {
  LibraryRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  final Map<int, Future<Library>> _cache = {};
  List<LanguageInfo>? _languages;

  Future<List<LanguageInfo>> languages() async {
    if (_languages != null) return _languages!;
    final data = jsonDecode(await _bundle.loadString('assets/library/manifest.json')) as Map<String, dynamic>;
    return _languages = [for (final l in data['languages'] as List) LanguageInfo.fromJson(l as Map<String, dynamic>)];
  }

  Future<Library> load(int language) => _cache.putIfAbsent(language, () async {
        final raw = await _bundle.loadString('assets/library/$language.json', cache: false);
        // English is ~13 MB of JSON; decode it off the UI thread.
        return compute(parseLibrary, raw);
      });

  Future<String> calendarTable() => _bundle.loadString('assets/calendar/badi-dates.json');
  Future<String> cityList() => _bundle.loadString('assets/calendar/cities.json', cache: false);

  Future<Map<String, String>> foldTable() async =>
      (jsonDecode(await _bundle.loadString('assets/library/fold.json')) as Map).cast<String, String>();
}

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
