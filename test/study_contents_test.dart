// Tables of contents made from a PDF's text lines: Dogear's tests/test_contents.py, ported.
import 'package:bahai_reader/core/study/contents.dart';
import 'package:bahai_reader/core/study/rules.dart';
import 'package:flutter_test/flutter_test.dart';

TextLine line(String text, double y, {double h = 10, double x = 72}) => TextLine(text, x, y, 300, h);

List<TextLine> body(int n, [double y = 200]) => [
  for (var i = 0; i < n; i++) line('Body text line $i about photosynthesis and light.', y + i * 14),
];

List<(String, int, int, double)> rows(List<ContentsEntry> es) => [for (final e in es) (e.title, e.level, e.page, e.y)];

void main() {
  test('headings by size and numbered sections', () {
    final pages = [
      [line('Light Reactions', 60, h: 24), ...body(20)],
      [line('SECTION 1', 60), ...body(20, 80)],
      [line('Membranes', 60, h: 16), ...body(20, 80)],
      [line('The Calvin', 60, h: 24), line('Cycle', 86, h: 24), ...body(20, 120)],
      body(20),
    ];
    expect(rows(buildContents(pages, ['1', '2', '3', '4', '5'])), [
      ('Light Reactions', 0, 0, 60.0),
      ('Section 1', 2, 1, 60.0),
      ('Membranes', 1, 2, 60.0),
      ('The Calvin Cycle', 0, 3, 60.0),
    ]);
  });

  test('a printed contents page', () {
    final pages = [
      [line('Biology Workbook', 200, h: 40)],
      [
        line('Contents', 60, h: 14),
        line('Preface ............................ iii', 100),
        line('Light ................................ 1', 114),
        line('Membranes ........................ 2', 128, x: 90),
        line('Carbon ............................... 3', 142),
      ],
      [line('Preface', 60, h: 16), ...body(10)],
      [line('Light', 60, h: 30), ...body(10)],
      [line('Membranes', 60, h: 16), ...body(10)],
      [line('Carbon', 60, h: 30), line('SECTION 1', 300), ...body(10)],
    ];
    expect(
      [
        for (final e in buildContents(pages, ['i', 'ii', 'iv', '1', '2', '3'])) (e.title, e.level, e.page),
      ],
      [('Preface', 0, 2), ('Light', 0, 3), ('Membranes', 1, 4), ('Carbon', 0, 5), ('Section 1', 2, 5)],
    );
  });

  test('running headers and forms are not headings', () {
    final pages = [
      for (var i = 0; i < 12; i++) [line('Unit Notes', 20, h: 16), ...body(10, 60)],
    ];
    expect(buildContents(pages, [for (var i = 0; i < 12; i++) '${i + 1}']), isEmpty);
    final form = [
      for (var p = 0; p < 3; p++)
        [for (var i = 0; i < 8; i++) line('Field $i', 60.0 + i * 30, h: 14), ...body(10, 400)],
    ];
    expect(buildContents(form, ['1', '2', '3']), isEmpty);
  });

  test('sentences are not headings', () {
    final pages = [
      [
        line('Light Reactions', 60, h: 24),
        line('– You tell yourself the answer.', 100, h: 14),
        line('and then carry on', 120, h: 14),
        line('Section 3 of this unit is about light.', 140),
        ...body(10, 200),
      ],
      [line('Carbon Fixing', 60, h: 24), ...body(10)],
    ];
    expect(
      [
        for (final e in buildContents(pages, ['1', '2'])) e.title,
      ],
      ['Light Reactions', 'Carbon Fixing'],
    );
  });

  test('nothing found', () {
    expect(buildContents([body(10), body(10)], ['1', '2']), isEmpty);
    expect(buildContents([], []), isEmpty);
  });
}
