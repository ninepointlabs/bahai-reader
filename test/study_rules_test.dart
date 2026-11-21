// Answer-line detection on synthetic page images: Dogear's tests/test_rules.py, ported.
import 'dart:typed_data';

import 'package:bahai_reader/core/study/rules.dart';
import 'package:flutter_test/flutter_test.dart';

const scale = 2.0;

/// A white grayscale page, sized and drawn in PDF points.
class Page {
  Page([double wPt = 300, double hPt = 300]) : w = (wPt * scale).toInt(), h = (hPt * scale).toInt() {
    px = Uint8List(w * h)..fillRange(0, w * h, 255);
  }
  final int w, h;
  late final Uint8List px;

  void fill(double x, double y, double fw, double fh, [int value = 0]) {
    for (var r = (y * scale).toInt(); r < ((y + fh) * scale).toInt(); r++) {
      for (var c = (x * scale).toInt(); c < ((x + fw) * scale).toInt(); c++) {
        px[r * w + c] = value;
      }
    }
  }

  void line(double x, double y, double lw, {double thick = 0.8}) => fill(x, y - thick / 2, lw, thick);

  /// Glyph-like ink: short vertical strokes, as text renders.
  void text(double x, double y, double tw, {double size = 10}) {
    for (var i = 0; i < (tw / 3).toInt(); i++) {
      fill(x + i * 3, y - size * 0.7, 1.2, size * 0.7);
    }
  }

  /// Letters standing on the baseline, with serif feet along it.
  void serifWord(double x, double y, double ww, {double size = 10}) {
    text(x, y, ww, size: size);
    for (var i = 0; i < (ww / 3).toInt(); i++) {
      fill(x + i * 3 - 0.5, y - 1, 2.4, 1);
    }
  }

  List<Rule> rules() => findRules(px, w, h, w, scale);
}

List<Rule> rows(List<List<double>> rs) => [for (final r in rs) Rule(r[0], r[1], r[2], r[3])];

void main() {
  group('findRules', () {
    test('a single line', () {
      final page = Page()..line(50, 100, 200);
      final rules = page.rules();
      expect(rules, hasLength(1));
      expect(rules[0].x, closeTo(50, 0.6));
      expect(rules[0].y, closeTo(100, 0.6));
      expect(rules[0].w, closeTo(200, 1));
      expect(rules[0].space, greaterThan(30));
    });

    test('text is not a line', () => expect((Page()..text(20, 60, 260)).rules(), isEmpty));

    test('a blank with a word close after it', () {
      final page = Page()
        ..line(50, 100, 100, thick: 1)
        ..serifWord(152, 100.5, 18)
        ..line(176, 100, 60, thick: 1);
      final rules = page.rules();
      expect(rules, hasLength(2), reason: '$rules');
      expect(rules[0].x, closeTo(50, 0.6));
      expect(rules[0].w, closeTo(100, 1.5));
    });

    test('a dot leader into a title is not a blank', () {
      final page = Page()..serifWord(30, 100.5, 60);
      for (var i = 0; i < 40; i++) {
        page.fill(91 + i * 4, 99.2, 1.5, 1.5);
      }
      expect(page.rules(), isEmpty);
    });

    test('a hyphen is not a line', () => expect((Page()..line(50, 100, 8)).rules(), isEmpty));

    test('a short blank before a sentence', () {
      final rules =
          (Page()
                ..line(50, 100, 22)
                ..text(80, 100, 150))
              .rules();
      expect(rules, hasLength(1));
      expect(rules[0].w, closeTo(22, 1));
    });

    test('letter crossbars are not lines', () {
      final page = Page()..fill(50, 92, 20, 0.8);
      for (final x in [50.0, 58.0, 69.0]) {
        page.fill(x, 92, 1, 8);
      }
      expect(page.rules(), isEmpty);
    });

    test('an em dash between words is not a line', () {
      final page = Page()
        ..text(20, 100, 60)
        ..line(80.5, 96, 16)
        ..text(97, 100, 60);
      expect(page.rules(), isEmpty);
    });

    test('underlined text is not a blank', () {
      expect(
        (Page()
              ..text(50, 98, 200)
              ..line(50, 100, 200))
            .rules(),
        isEmpty,
      );
    });

    test('a thick bar is not a line', () => expect((Page()..fill(50, 100, 200, 8)).rules(), isEmpty));

    test('box edges are not lines', () {
      final page = Page()
        ..line(40, 60, 220)
        ..line(40, 200, 220)
        ..fill(40, 60, 0.8, 140)
        ..fill(259.2, 60, 0.8, 140);
      expect(page.rules(), isEmpty);
    });

    test('a dotted line', () {
      final page = Page();
      for (var i = 0; i < 40; i++) {
        page.fill(50 + i * 4, 100, 1.5, 1);
      }
      expect(page.rules(), hasLength(1));
    });

    test('a label beside a line', () {
      final rules =
          (Page()
                ..text(20, 100, 60)
                ..line(90, 100, 180))
              .rules();
      expect(rules, hasLength(1));
      expect(rules[0].x, closeTo(90, 1));
    });

    test('the space stops at text above', () {
      final rules =
          (Page()
                ..text(50, 80, 200)
                ..line(50, 100, 200))
              .rules();
      expect(rules, hasLength(1));
      expect(rules[0].space, closeTo(20, 2));
    });

    test('sorted top to bottom, left to right', () {
      final rules =
          (Page()
                ..line(160, 150, 100)
                ..line(30, 150, 100)
                ..line(30, 80, 100))
              .rules();
      expect([for (final r in rules) (r.x.round(), r.y.round())], [(30, 80), (30, 150), (160, 150)]);
    });
  });

  group('slots', () {
    test('a ruled block is grouped', () {
      final rules = rows([
        [50, 100, 400, 30],
        [50, 124, 400, 22],
        [50, 148, 400, 22],
        [50, 230, 400, 60],
      ]);
      final slot = slotFrom(rules, 0);
      expect((slot.lines, slot.pitch, slot.w), (3, 24.0, 400.0));
      expect(slot.size, lessThanOrEqualTo(12));
      expect(slotFrom(rules, 1).lines, 2, reason: 'starting on the second line keeps the rest of the block');
    });

    test('blanks in sentences stay separate', () {
      final rules = rows([
        [200, 100, 250, 20],
        [90, 118, 360, 15],
        [90, 136, 120, 15],
        [260, 136, 190, 15],
      ]);
      expect(slotFrom(rules, 0).lines, 1);
      expect(slotFrom(rules, 1).lines, 1);
    });

    test('a blank ending the question starts the ruled lines', () {
      final rules = rows([
        [314, 575.25, 199.5, 12.5],
        [136, 593.25, 377.5, 17.5],
        [136, 611.25, 377.5, 17.5],
        [427, 637.75, 86.5, 26],
      ]);
      final slot = slotFrom(rules, 0);
      expect((slot.x, slot.y, slot.w), (136.0, 575.25, 377.5));
      expect((slot.lines, slot.pitch, slot.indent), (3, 18.0, 178.0));
      expect(slotFrom(rules, 3).lines, 1);
      expect(slotFrom(rules, 1).indent, 0);
      final short = rows([
        [483.5, 100, 30, 12],
        [136, 118, 377.5, 17.5],
      ]);
      expect((slotFrom(short, 0).lines, slotFrom(short, 0).indent), (2, 347.5));
    });

    test('stacked short blanks stay separate', () {
      final rules = rows([
        [100, 100, 24, 20],
        [100, 130, 24, 20],
        [100, 160, 24, 20],
      ]);
      expect(slotFrom(rules, 0).lines, 1);
    });

    test('a single line takes its size from the space', () {
      final slot = slotFrom(
        rows([
          [50, 100, 200, 14],
        ]),
        0,
      );
      expect(slot.pitch, 0);
      expect(slot.size, closeTo(14 * 0.55, 0.01));
    });

    test('the size follows the page text', () {
      final rules = rows([
        [50, 100, 200, 40],
        [50, 200, 200, 12],
      ]);
      expect(slotFrom(rules, 0, 10.5).size, closeTo(10.5, 0.001));
      expect(slotFrom(rules, 1, 10.5).size, closeTo(12 * 0.8, 0.001));
      final lines = [
        for (final (y, h) in [(10.0, 10.0), (30.0, 10.0), (50.0, 20.0), (70.0, 1.0)]) TextLine('t', 0, y, 100, h),
      ];
      expect(textSize(lines), closeTo(10.5, 0.001));
      expect(textSize([]), 0);
    });

    test('ruleAt', () {
      final rules = rows([
        [50, 100, 200, 30],
        [50, 130, 200, 22],
      ]);
      expect(ruleAt(rules, 100, 95), 0);
      expect(ruleAt(rules, 100, 101), 0);
      expect(ruleAt(rules, 100, 120), 1);
      expect(ruleAt(rules, 10, 95), -1);
      expect(ruleAt(rules, 100, 60), -1);
    });
  });

  group('context', () {
    const lines = [
      TextLine('Review questions', 72, 400, 120, 14),
      TextLine('1. Name of the process:', 72, 452, 130, 11),
      TextLine('2. Explain the Calvin cycle in', 72, 492, 300, 11),
      TextLine('your own words.', 72, 506, 120, 11),
      TextLine('3. Plants absorb ________ and ________ light.', 72, 612, 300, 11),
    ];

    test('a label on the same row', () => expect(contextFor(lines, 210, 464), '1. Name of the process:'));
    test(
      'a question above ruled lines',
      () => expect(contextFor(lines, 90, 532), '2. Explain the Calvin cycle in your own words.'),
    );
    test(
      'underscore blanks collapse',
      () => expect(contextFor(lines, 160, 623), '3. Plants absorb ___ and ___ light.'),
    );

    test('drawn blanks and a wrapped question', () {
      const ls = [
        TextLine('1. The pigment is , and it absorbs mostly', 97, 126, 300, 11),
        TextLine('and light.', 218, 152, 160, 11),
        TextLine('2. Next question', 97, 195, 200, 11),
      ];
      final rules = [Rule(190, 134, 24, 0), Rule(108, 160, 100, 0), Rule(241.5, 160, 100, 0)];
      List<double> charLefts(int i) {
        final text = ls[i].text;
        var x = ls[i].x;
        final out = <double>[];
        for (var k = 0; k < text.length; k++) {
          out.add(x);
          x += 5.0;
          if (i == 0 && out.length == '1. The pigment is '.length) x = 212.0;
          if (i == 1 && out.length == 'and '.length) x = 345.0;
        }
        return out;
      }

      const want = '1. The pigment is ___, and it absorbs mostly ___ and ___ light.';
      for (final blank in rules) {
        expect(contextFor(ls, blank.x + 5, blank.y, rules: rules, charLefts: charLefts), want);
      }
      expect(contextFor(ls, 110, 160, rules: rules), '1. The pigment is, and it absorbs mostly and light.');
    });

    test('nothing near', () {
      expect(contextFor(lines, 90, 760), '');
      expect(contextFor([], 90, 100), '');
    });
  });
}
