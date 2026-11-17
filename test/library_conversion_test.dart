import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/library/citations.dart';
import 'package:bahai_reader/core/library/library.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final english = parseLibrary(File('assets/library/1.json').readAsStringSync());
  final manifest = jsonDecode(File('assets/library/manifest.json').readAsStringSync()) as Map;

  test('English passage ids survived conversion unchanged', () {
    for (final id in [
      'hidden:1',
      'hidden:2',
      'prayers:15692',
      'aqdas:Paragraphs:6',
      'aqdas:Notes:1',
      'gleanings:1',
      'iqan:1',
      'saq:1',
    ]) {
      expect(english.byId, contains(id), reason: id);
    }
    expect(english.passages.length, 3526);
    expect(english.byId.length, english.passages.length, reason: 'ids are unique');
    expect(english.passages.where((p) => RegExp(r'^\d+:').hasMatch(p.id)), isEmpty,
        reason: 'English ids have no language prefix');
  });

  test('bahai.org text replaces BahaiPrayers.net text under the same id', () {
    final p = english.byId['hidden:2']!;
    expect(p.official, isTrue);
    expect(p.citation, endsWith(bahaiOrgNotice));
    expect(p.match, 'hidden:True:2');
  });

  test('official-only works, prayers, days and Riḍván have no match', () {
    for (final p in english.passages) {
      final collection = p.id.split(':').first;
      if (['prayers', 'days', 'ridvan', 'uhj', 'se'].contains(collection) || p.id.startsWith('ridvan')) {
        expect(p.match, isNull, reason: p.id);
      }
    }
    expect(english.passages.where((p) => p.tags.contains('Messages of the Universal House of Justice')).every((p) => p.match == null), isTrue);
  });

  test('every bundled language: prefixed ids, unique, BMP-only text, valid spans', () {
    for (final l in manifest['languages'] as List) {
      final id = l['id'] as int;
      final lib = parseLibrary(File('assets/library/$id.json').readAsStringSync());
      expect(lib.passages.length, l['passages']);
      expect(lib.byId.length, lib.passages.length);
      for (final p in lib.passages) {
        if (id != 1) expect(p.id, startsWith('$id:'));
        expect(p.text.runes.length, p.text.length, reason: '${p.id}: offsets must be code points = UTF-16 units');
        for (final s in p.spans) {
          expect(0 <= s.start && s.start <= s.end && s.end <= p.text.length, isTrue, reason: p.id);
        }
      }
    }
  });

  test('Amharic Hidden Words pair with English by match', () {
    final amharic = parseLibrary(File('assets/library/90.json').readAsStringSync());
    final p = amharic.byId['90:hidden:7400']!;
    expect(p.match, 'hidden:True:2');
    expect(english.byMatch[p.match]!.id, 'hidden:2');
  });

  test('library groups works clearly', () {
    final titles = english.books.map((w) => w.title).toList();
    expect(titles, containsAll([hiddenWords, 'The Kitáb-i-Aqdas', 'Gleanings from the Writings of Bahá’u’lláh']));
    expect(english.prayerCategories, isNotEmpty);
    final aqdas = english.books.firstWhere((w) => w.title == 'The Kitáb-i-Aqdas');
    expect(aqdas.contents.map((g) => g.$1), containsAll(['Text', 'Questions and Answers', 'Notes']));
    final (work, i) = english.workOf(english.byId['hidden:2']!)!;
    expect(work.title, hiddenWords);
    expect(work.passages[i].id, 'hidden:2');
  });

  test('copied text carries the citation', () {
    final p = english.byId['hidden:2']!;
    final copied = clipping(p, 'O SON OF SPIRIT!');
    expect(copied, 'O SON OF SPIRIT!\n\n— ${p.citation}');
  });
}
