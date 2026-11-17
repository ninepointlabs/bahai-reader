import 'package:bahai_reader/core/marks/highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const text = 'O SON OF SPIRIT! My first counsel is this: Possess a pure, kindly and radiant heart.';

  group('makeHighlight', () {
    test('records id, offsets, words, colour and date like the GTK app', () {
      final h = makeHighlight('hidden:1', text, 17, 39, color: 'green', today: '2026-11-15')!;
      expect(h.toJson(), {
        'id': 'hidden:1',
        'start': 17,
        'end': 39,
        'words': 'My first counsel is th',
        'color': 'green',
        'created': '2026-11-15',
      });
    });

    test('never begins or ends on a space', () {
      final h = makeHighlight('hidden:1', text, 16, 26, today: 'x')!;
      expect(h.start, 17);
      expect(h.words, 'My first');
      expect(makeHighlight('hidden:1', text, 16, 17), isNull);
    });

    test('unknown colour falls back to yellow; note trimmed and limited to 5000', () {
      final h = makeHighlight('hidden:1', text, 0, 5, color: 'red', note: '  ${'x' * 6000}  ')!;
      expect(h.color, 'yellow');
      expect(h.note!.length, noteLimit);
      expect(makeHighlight('hidden:1', text, 0, 5, note: '   ')!.note, isNull);
    });
  });

  group('anchor', () {
    final h = makeHighlight('hidden:1', text, 43, 58, today: 'x')!; // "Possess a pure,"

    test('uses stored offsets when the words are still there', () {
      expect(anchor(text, h), (43, 58));
    });

    test('finds the words again when the text moved', () {
      expect(anchor('Preface. $text', h), (52, 67));
    });

    test('chooses the occurrence nearest the stored offset', () {
      final r = Highlight(id: 'a', start: 20, end: 23, words: 'abc', color: 'yellow');
      expect(anchor('abc xxxxxxxxxxxxxxxxxxx abc yyyyyyyyyyyyyyyyy abc', r), (24, 27));
    });

    test('returns null when the words are gone (kept, not drawn)', () {
      expect(anchor('Completely different text.', h), isNull);
    });

    test('stored offsets past the end of a shorter text do not throw', () {
      final r = Highlight(id: 'a', start: 100, end: 110, words: 'zzz', color: 'blue');
      expect(anchor('short', r), isNull);
    });
  });

  group('addHighlight', () {
    test('a new highlight replaces the ones it overlaps in the same passage only', () {
      final a = Highlight(id: 'p', start: 0, end: 10, words: 'x', color: 'yellow');
      final b = Highlight(id: 'p', start: 20, end: 30, words: 'x', color: 'green');
      final other = Highlight(id: 'q', start: 0, end: 10, words: 'x', color: 'blue');
      final touching = Highlight(id: 'p', start: 10, end: 12, words: 'x', color: 'blue');
      final added = Highlight(id: 'p', start: 5, end: 25, words: 'x', color: 'magenta');
      expect(addHighlight([a, b, other, touching], added), [other, added]);
      final adjacent = Highlight(id: 'p', start: 30, end: 35, words: 'x', color: 'magenta');
      expect(addHighlight([b], adjacent), [b, adjacent]);
    });
  });

  group('cleanHighlights', () {
    test('keeps well-formed GTK records and drops the rest', () {
      final records = cleanHighlights([
        {'id': 'hidden:2', 'start': 10, 'end': 24, 'words': 'the quoted text', 'color': 'yellow', 'created': '2026-11-15', 'note': 'n'},
        {'id': 'hidden:2', 'start': 10, 'end': 10, 'words': 'x', 'color': 'yellow'},
        {'id': 'hidden:2', 'start': 0, 'end': 4, 'words': 'x', 'color': 'red'},
        {'id': 'hidden:2', 'start': 0, 'end': 4, 'words': '', 'color': 'blue'},
        {'id': 2, 'start': 0, 'end': 4, 'words': 'x', 'color': 'blue'},
        {'id': 'hidden:3', 'start': 0, 'end': 4, 'words': 'x', 'color': 'blue', 'note': '   '},
        'junk',
      ]);
      expect(records.length, 2);
      expect(records.first.toJson(),
          {'id': 'hidden:2', 'start': 10, 'end': 24, 'words': 'the quoted text', 'color': 'yellow', 'created': '2026-11-15', 'note': 'n'});
      expect(records.last.note, isNull);
      expect(cleanHighlights('nope'), isEmpty);
    });
  });

  group('cross-language follow', () {
    test('languageOf', () {
      expect(languageOf('hidden:2'), 1);
      expect(languageOf('aqdas:Paragraphs:6'), 1);
      expect(languageOf('4:hidden:687'), 4);
      expect(languageOf('uhj:20260227_001'), 1);
    });

    final english = {'hidden:2': 'EN hidden 2', 'prayers:1': 'EN prayer'};
    final spanish = {'4:hidden:687': 'ES hidden 2', '4:prayers:9': 'ES prayer'};
    final matches = {
      1: {'hidden:2': 'hidden:True:2'},
      4: {'4:hidden:687': 'hidden:True:2'},
    };
    Map<String, String> matchesIn(int l) => matches[l] ?? {};

    test('an English id follows to the Spanish passage and back, without rewriting ids', () {
      expect(follow('hidden:2', spanish, {'hidden:True:2': 'ES hidden 2'}, matchesIn), 'ES hidden 2');
      expect(follow('4:hidden:687', english, {'hidden:True:2': 'EN hidden 2'}, matchesIn), 'EN hidden 2');
      expect(follow('hidden:2', english, {'hidden:True:2': 'EN hidden 2'}, matchesIn), 'EN hidden 2');
    });

    test('unmatched ids stay with their own language', () {
      expect(follow('prayers:1', spanish, {'hidden:True:2': 'ES hidden 2'}, matchesIn), isNull);
      expect(follow('4:prayers:9', english, {'hidden:True:2': 'EN hidden 2'}, matchesIn), isNull);
    });
  });
}
