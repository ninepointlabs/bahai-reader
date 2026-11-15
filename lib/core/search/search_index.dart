import 'package:flutter/foundation.dart';

import '../library/library.dart';
import '../library/passage.dart';
import 'fold.dart';

/// Full-library search: each passage's title, text and categories folded once (in a background isolate), then a plain
/// substring scan per query. Results come back in library order, as in the GTK app's `search_passages()`.
class SearchIndex {
  SearchIndex._(this.library, this.folder, this._folded);
  final Library library;
  final Folder folder;
  final List<String> _folded;

  static Future<SearchIndex> build(Library library, Folder folder) async {
    final docs = [for (final p in library.passages) '${p.title} ${p.text} ${p.tags.join(' ')}'];
    final folded = await compute(_foldAll, (folder.table, docs));
    return SearchIndex._(library, folder, folded);
  }

  /// Synchronous build, for tests.
  factory SearchIndex.sync(Library library, Folder folder) => SearchIndex._(
      library, folder, [for (final p in library.passages) folder.fold('${p.title} ${p.text} ${p.tags.join(' ')}')]);

  List<Passage> search(String query, {int limit = 500}) {
    final q = folder.fold(query.trim());
    if (q.isEmpty) return const [];
    final found = <Passage>[];
    for (var i = 0; i < _folded.length && found.length < limit; i++) {
      if (_folded[i].contains(q)) found.add(library.passages[i]);
    }
    return found;
  }
}

List<String> _foldAll((Map<String, String>, List<String>) args) {
  final folder = Folder(args.$1);
  return [for (final d in args.$2) folder.fold(d)];
}
