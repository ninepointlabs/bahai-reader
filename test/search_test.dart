import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/search/fold.dart';
import 'package:bahai_reader/core/search/search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final folder = Folder((jsonDecode(File('assets/library/fold.json').readAsStringSync()) as Map).cast<String, String>());

  test('fold matches the GTK fold(): no case, accents, apostrophes or hyphens', () {
    expect(folder.fold('Bahá’u’lláh'), 'bahaullah');
    expect(folder.fold('‘Abdu’l‑Bahá'), 'abdulbaha');
    expect(folder.fold('Riḍván'), 'ridvan');
    expect(folder.fold('Kitáb-i-Íqán'), 'kitabiiqan');
  });

  test('find maps the match back onto the original text', () {
    const text = 'Praise be to Bahá’u’lláh, the Lord.';
    final span = folder.find(text, folder.fold('Bahaullah'))!;
    expect(text.substring(span.$1, span.$2), 'Bahá’u’lláh');
    expect(snippet(text, span).$2, 'Bahá’u’lláh');
  });

  test('full-library search: "Bahaullah" finds passages with "Bahá’u’lláh"', () {
    final lib = parseLibrary(File('assets/library/1.json').readAsStringSync());
    final index = SearchIndex.sync(lib, folder);
    final found = index.search('Bahaullah', limit: 100000);
    expect(found.length, greaterThan(100));
    expect(found.every((p) => folder.fold('${p.title} ${p.text} ${p.tags.join(' ')}').contains('bahaullah')), isTrue);
    expect(index.search('o son of spirit').map((p) => p.id), contains('hidden:1'));
    expect(index.search('   '), isEmpty);
  });
}
