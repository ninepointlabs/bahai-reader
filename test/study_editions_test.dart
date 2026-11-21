// Other copies and editions: Dogear's name rules, and finding highlights and answer blanks again in a revised edition
// (test/fixtures/worksheet-2.pdf: a paragraph added at the top moves everything down).
import 'dart:io';

import 'package:bahai_reader/core/study/editions.dart';
import 'package:bahai_reader/core/study/page_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  group('names (Dogear tests/test_library.py)', () {
    test('editions of the same book match', () {
      expect(
        sameName(
          'RUHI0110_CC1_BK3_EN_2.1.1.PE_FullText_20210325.pdf',
          'RUHI0110_CC1_BK3_EN_2.2.1.PE_FullText_20210930.pdf',
        ),
        isTrue,
      );
      expect(sameName('Biology notes v2.pdf', 'biology notes v3'), isTrue);
      expect(sameName('Biology 101.pdf', 'Biology 101.pdf'), isTrue);
    });
    test('different books do not', () {
      expect(sameName('Lecture 1.pdf', 'Lecture 2.pdf'), isFalse);
      expect(sameName('Ruhi Book 12.1', 'Ruhi Book 4'), isFalse);
      expect(sameName('2020.pdf', '2021.pdf'), isFalse, reason: 'nothing but versions');
      expect(sameName('Biology.pdf', 'Chemistry.pdf'), isFalse);
      expect(sameName('', 'x'), isFalse);
    });
    test('copies: close page counts, or the same PDF id', () {
      const a = FileFacts(sha256: 'a', fileName: 'Bio 101.pdf', pageCount: 200);
      expect(isCopyOf(a, const FileFacts(sha256: 'b', fileName: 'Bio 101.pdf', pageCount: 204)), isTrue);
      expect(isCopyOf(a, const FileFacts(sha256: 'b', fileName: 'Bio 101.pdf', pageCount: 150)), isFalse);
      expect(
        isCopyOf(a, const FileFacts(sha256: 'b', fileName: 'Bio 101.pdf')),
        isFalse,
        reason: 'pages unknown',
      );
      expect(isCopyOf(a, const FileFacts(sha256: 'a', fileName: 'Bio 101.pdf', pageCount: 200)), isFalse);
      const x = FileFacts(sha256: 'a', fileName: 'download.pdf', pdfDocId: 'ABC');
      expect(isCopyOf(x, const FileFacts(sha256: 'b', fileName: 'Bio 101.pdf', pdfDocId: 'ABC')), isTrue);
      expect(isCopyOf(x, const FileFacts(sha256: 'b', fileName: 'Bio 101.pdf', pdfDocId: 'DEF')), isFalse);
    });
  });

  group('finding marks in another edition', () {
    late List<PageData> one, two;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('br-pdfrx-').path;
      await pdfrxFlutterInitialize();
      Future<List<PageData>> load(String f) async {
        final doc = await PdfDocument.openFile(f);
        final pages = [for (final p in doc.pages) await PageData.load(p)];
        await doc.dispose();
        return pages;
      }

      one = await load('test/fixtures/worksheet.pdf');
      two = await load('test/fixtures/worksheet-2.pdf');
    });

    test('a highlight is found by its words and the text around them, wherever they moved', () {
      final p1 = one.first;
      final at = p1.text.indexOf('talk about what it');
      final quote = p1.text.substring(at, at + 'talk about what it'.length);
      final found = findQuote(
        two,
        quote,
        prefix: p1.text.substring(at - 32, at),
        suffix: p1.text.substring(at + quote.length, at + quote.length + 32),
        hintPage: 1,
      )!;
      final (page, s, e) = found;
      expect(two[page - 1].text.substring(s, e).replaceAll(RegExp(r'\s+'), ' '), 'talk about what it');
      final oldBox = p1.boxesFor(at, at + quote.length).first, newBox = two[page - 1].boxesFor(s, e).first;
      expect(newBox.y, greaterThan(oldBox.y + 20), reason: 'it moved down');
      expect(findQuote(two, 'words in no edition at all'), isNull);
    });

    test('of two equal phrases, the one with the same text around it wins', () {
      // "the group" appears more than once; the context picks the right one.
      final p1 = one.first;
      final at = p1.text.indexOf('the group do after');
      final found = findQuote(
        two,
        'the group',
        prefix: p1.text.substring(at - 20, at),
        suffix: p1.text.substring(at + 9, at + 30),
      )!;
      final t = two[found.$1 - 1].text;
      expect(t.substring(found.$2, found.$2 + 30).replaceAll(RegExp(r'\s+'), ' '), startsWith('the group do after'));
    });

    test('an answer blank is found by its question and which blank of it it is', () {
      String ctx(PageData p, int i) => p.contextAt(p.rules[i].x + 5, p.rules[i].y);
      final q1 = ctx(one.first, 0);
      final a = findSlot(two, q1, ordinal: 0)!, b = findSlot(two, q1, ordinal: 1)!;
      expect(ctx(two[a.$1 - 1], a.$2), q1);
      expect(two[b.$1 - 1].rules[b.$2].x, greaterThan(two[a.$1 - 1].rules[a.$2].x), reason: 'the second blank');
      final q4 = ctx(one[1], 0);
      final c = findSlot(two, q4, hintPage: 2)!;
      expect(ctx(two[c.$1 - 1], c.$2), q4);
      expect(findSlot(two, 'A question that is not there'), isNull);
      expect(
        pageNamed([('Section 1: Reading together', 1), ('Section 2: Looking back', 2)], 'section 2 — looking back'),
        2,
      );
    });
  });
}
