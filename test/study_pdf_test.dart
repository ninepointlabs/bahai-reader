// The Study reader's page data on a real PDF: test/fixtures/worksheet.pdf, made by scripts/fixtures/make-worksheet.sh
// from scripts/fixtures/worksheet.html (our own sample text).
import 'dart:io';

import 'package:bahai_reader/core/study/page_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('br-pdfrx-').path;
    await pdfrxFlutterInitialize();
  });

  test('text lines, questions and answer lines of a workbook page', () async {
    final doc = await PdfDocument.openFile('test/fixtures/worksheet.pdf');
    addTearDown(doc.dispose);
    expect(doc.pages, hasLength(2));
    final p1 = await PageData.load(doc.pages[0]);
    expect(p1.lines.first.text, 'Study Workbook Sample');
    expect(p1.lines.first.y, lessThan(100), reason: 'top-left coordinates');
    // Q1's two underscore blanks, Q2's three ruled lines; the table's borders and the open space are not lines.
    final ys = [for (final r in p1.rules) r.y.round()];
    expect(p1.rules.length, 5, reason: '${p1.rules}');
    expect(ys.toSet().length, 4, reason: 'two blanks share Q1\'s row');
    final q1 = p1.rules.first;
    expect(p1.contextAt(q1.x + 5, q1.y), '1. The group meets every ___ to read and ___ together.');
    final ruled = p1.rules[2];
    expect(
      p1.contextAt(ruled.x + 5, ruled.y),
      '2. In your own words, what does the group do after reading the passage?',
    );
    expect(p1.fontSize, inInclusiveRange(10, 20));
    // Selection boxes: the words "study group" on one line.
    final at = p1.text.indexOf('study group');
    final boxes = p1.boxesFor(at, at + 'study group'.length);
    expect(boxes, hasLength(1));
    expect(p1.charAt(boxes.single.x + 1, boxes.single.y + boxes.single.h / 2), at);

    final p2 = await PageData.load(doc.pages[1]);
    expect(p2.rules.length, 4, reason: '${p2.rules}');
    expect(p2.contextAt(p2.rules.first.x + 5, p2.rules.first.y), '4. Name two things you learned: ___ and ___.');
  });
}
