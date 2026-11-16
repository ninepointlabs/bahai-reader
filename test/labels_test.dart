import 'package:bahai_reader/core/library/labels.dart';
import 'package:bahai_reader/core/library/library.dart';
import 'package:bahai_reader/core/library/passage.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'disk_bundle.dart';

/// The phone reader's heading: a name or a number, never the passage's opening words cut short.
void main() {
  test('books by author: the Central Figures and institutions in order, then others, Compilations, Other', () async {
    Passage p(String? author) =>
        Passage(id: 'x', title: 'x', section: 'writings', tags: const [], text: '', citation: '', wordCount: 1, author: author);
    Work w(String title, List<String?> authors) =>
        Work(title: title, kind: 'writings', passages: [for (final a in authors) p(a)]);
    final books = [
      w('Mixed', ['Bahá’u’lláh', '‘Abdu’l‑Bahá']),
      w('Unsigned', [null]),
      w('Talks', ['‘Abdu’l‑Bahá', null]),
      w('Someone', ['A Scholar']),
      w('Íqán', ['Bahá’u’lláh']),
    ];
    expect(authorOf(books[0]), compilations);
    expect(authorOf(books[2]), '‘Abdu’l‑Bahá', reason: 'passages without an author do not make a compilation');
    expect([for (final (a, ws) in booksByAuthor(books)) '$a: ${ws.map((w) => w.title).join(', ')}'], [
      'Bahá’u’lláh: Íqán',
      '‘Abdu’l‑Bahá: Talks',
      'A Scholar: Someone',
      'Compilations: Mixed',
      'Other: Unsigned',
    ]);
    final english = booksByAuthor((await LibraryRepository(bundle: DiskBundle()).load(1)).books);
    expect(english.map((e) => e.$1), ['Bahá’u’lláh', '‘Abdu’l‑Bahá', 'Shoghi Effendi', 'The Universal House of Justice'],
        reason: 'no bundled English book has more than one author');
  });

  test('phone headings', () async {
    final lib = await LibraryRepository(bundle: DiskBundle()).load(1);
    String? h(String id) => phoneHeading(lib.byId[id]!);
    expect(h('prayers:392'), isNull, reason: 'Medium Obligatory Prayer: its text has its own heading line');
    expect(h('prayers:13083'), isNull, reason: 'opening words, behind a margin number');
    expect(h('prayers:8255'), isNull, reason: 'opening words, after the tablet’s name');
    expect(h('hidden:2'), '2');
    expect(h('hidden:1'), '1', reason: 'opening words after the preface');
    expect(h('saq:9'), '7 · Muhammad', reason: 'a chapter name stays');
    expect(h('prayers:13691'), 'Epistle to the Son of the Wolf');
    // No prayer is headed by a title cut off mid-sentence.
    final cutOff = [
      for (final p in lib.passages)
        if (p.isPrayer && (phoneHeading(p)?.length ?? 0) >= 80) p.id,
    ];
    expect(cutOff, isEmpty);
    // In every bundled language, a long heading taken from a title is a real name, never words from the text.
    for (final lang in [1, 90]) {
      final l = await LibraryRepository(bundle: DiskBundle()).load(lang);
      final fromText = [
        for (final p in l.passages)
          if (phoneHeading(p) case final t? when t.length >= 60 && p.heading == null && p.unnumbered.contains(t.split(' · ').last))
            p.id,
      ];
      expect(fromText, isEmpty, reason: 'language $lang');
    }
  });
}
