import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/library/packs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compares a converted pack with what the GTK code made of the same pack (the converter's output, which calls the GTK
/// app's own `load_library()`): every passage field, the passage-of-the-day order and the Obligatory prayers groups.
void compareWith(Map<String, dynamic> made, Map<String, dynamic> expected) {
  final mine = made['items'] as List, theirs = expected['items'] as List;
  expect(mine.length, theirs.length);
  for (var i = 0; i < theirs.length; i++) {
    final a = mine[i] as Map, b = theirs[i] as Map;
    // The converter leaves out keys whose value is null.
    expect(a..removeWhere((_, v) => v == null), b, reason: 'passage ${b['id']}');
  }
  expect(made['daily'], expected['daily']);
  expect(made['obligatory'], expected['obligatory']);
}

void main() {
  test('Python’s random.Random(1844).shuffle, in Dart', () {
    // python3 -c "import random; x=list(range(20)); random.Random(1844).shuffle(x); print(x)"
    final x = List.generate(20, (i) => i);
    PythonRandom(1844).shuffle(x);
    expect(x, [13, 14, 10, 11, 19, 1, 9, 5, 18, 0, 4, 6, 2, 7, 8, 15, 17, 12, 3, 16]);
  });

  test('a GTK language pack gives the same library as the GTK app (Amharic)', () {
    final pack = checkPack(jsonDecode(File('test/fixtures/pack-90.json').readAsStringSync()), 90)!;
    final made = jsonDecode(packLibraryJson(pack, 90)) as Map<String, dynamic>;
    final expected = jsonDecode(File('assets/library/90.json').readAsStringSync()) as Map<String, dynamic>;
    compareWith(made, expected);
  });

  test('a pack for another language, or a damaged one, is refused', () {
    final pack = jsonDecode(File('test/fixtures/pack-90.json').readAsStringSync());
    expect(checkPack(pack, 4), isNull);
    expect(checkPack({'hidden': []}, 90), isNull);
    expect(checkPack({'prayers': {'IsInError': true}}, 90), isNull);
    expect(checkPack('not a pack', 90), isNull);
  });

  test('plain text from feed HTML, and word counts, as the GTK app makes them', () {
    expect(plain("<p><i>Covenant</i></p><p class='dropCap'>O God &amp; Lord</p>"), 'Covenant\n\nO God & Lord');
    expect(plain('<h2>A</h2>\n\n  \n<p>B<br/>C</p>'), 'A\n\nB\n\nC');
    expect(wordCount('Bahá’u’lláh — the well-beloved, 12 words'), 5);
  });

  // The whole English BahaiPrayers.net library, against the GTK code's own output. Needs a file made by
  // scripts/pack_fixtures.py (not in the repository: ~10 MB); skipped without it.
  final english = Platform.environment['GTK_ENGLISH_PACK'];
  test('the English feeds give the same passages as the GTK app', () {
    final data = jsonDecode(File(english!).readAsStringSync()) as Map<String, dynamic>;
    final made = jsonDecode(packLibraryJson((data['pack'] as Map).cast<String, dynamic>(), 1)) as Map<String, dynamic>;
    compareWith(made, (data['expected'] as Map).cast<String, dynamic>());
  }, skip: english == null ? 'set GTK_ENGLISH_PACK to run' : false);
}
