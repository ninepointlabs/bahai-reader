import 'package:bahai_reader/core/library/labels.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'disk_bundle.dart';

/// Titles cut at a fixed length end at a whole word with "…"; names and whole texts are kept.
void main() {
  test('cut titles end at a whole word with an ellipsis', () async {
    final lib = await LibraryRepository(bundle: DiskBundle()).load(1);
    String t(String title) => listTitle(lib.passages.firstWhere((p) => p.title == title));
    final first = lib.passages.firstWhere((p) => p.title.startsWith('1 · He is the Almighty. Praised be Thou'));
    expect(first.title, endsWith('ordained N'), reason: 'the stored title is cut mid-word');
    expect(listTitle(first), '1 · He is the Almighty. Praised be Thou, O my God, that Thou hast ordained…');
    expect(t('Epistle to the Son of the Wolf'), 'Epistle to the Son of the Wolf', reason: 'a name is kept');
    var changed = 0;
    for (final p in lib.passages) {
      final shown = listTitle(p);
      if (shown == p.title || obligatoryPrayers.contains(shown)) continue;
      changed++;
      expect(shown, endsWith('…'), reason: p.id);
      expect(p.title, startsWith(shown.substring(0, shown.length - 1)), reason: '${p.id}: only whole words are kept');
    }
    expect(changed, greaterThan(100));
  });
}
