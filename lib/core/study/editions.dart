/// Other copies and editions of a book, and finding marks again in them.
///
/// * [sameName] / [isCopyOf]: Dogear's rules (`library.py`): the same PDF document id, or the same title or file name
///   apart from version numbers and dates (`…_2.1.1…_20210325` and `…_2.2.1…_20210930`) with page counts within about
///   5%. "Lecture 1" and "Lecture 2" differ.
/// * [findQuote]: a highlight's words in another edition, by its text and the text either side of it.
/// * [findSlot]: an answer's blank in another edition, by its printed question and which blank of it it was.
library;

import 'dart:math' as math;

import 'page_data.dart';
import 'rules.dart';

final _versionish = RegExp(r'^(v?\d+(\.\d+)+[a-z.]*|\d{6,8}|v\d+|rev\d*|final|draft)$', caseSensitive: false);
final _split = RegExp(r'[\s_\-()\[\],]+');

List<String> _tokens(String name) {
  final lower = name.toLowerCase();
  final base = lower.endsWith('.pdf') || lower.endsWith('.epub') ? lower.substring(0, lower.lastIndexOf('.')) : lower;
  return [
    for (final t in base.split(_split))
      if (t.isNotEmpty) t,
  ];
}

/// Whether two titles or file names name the same book, ignoring version numbers and dates.
bool sameName(String a, String b) {
  final ta = _tokens(a), tb = _tokens(b);
  if (ta.isEmpty || tb.isEmpty || ta.length != tb.length) return false;
  var shared = 0;
  for (var i = 0; i < ta.length; i++) {
    final x = ta[i], y = tb[i];
    if (x == y) {
      if (!_versionish.hasMatch(x)) shared++;
    } else if (!(_versionish.hasMatch(x) && _versionish.hasMatch(y))) {
      return false;
    }
  }
  return shared > 0;
}

bool closePageCount(int a, int b) => (a - b).abs() <= math.max(2, (0.05 * math.max(a, b)).round());

/// What is known about a file for recognizing other copies of it.
class FileFacts {
  const FileFacts({required this.sha256, this.fileName = '', this.title = '', this.pageCount = 0, this.pdfDocId});
  final String sha256, fileName, title;
  final int pageCount;
  final String? pdfDocId;
}

/// Whether [other] looks like another copy or edition of [doc] (never the same file).
bool isCopyOf(FileFacts doc, FileFacts other) {
  if (other.sha256 == doc.sha256) return false;
  final id = doc.pdfDocId;
  if (id != null && id.isNotEmpty && id == other.pdfDocId) return true;
  if (doc.pageCount <= 0 || other.pageCount <= 0 || !closePageCount(doc.pageCount, other.pageCount)) return false;
  final names = [doc.title, doc.fileName].where((n) => n.isNotEmpty);
  final others = [other.title, other.fileName].where((n) => n.isNotEmpty);
  return names.any((a) => others.any((b) => sameName(a, b)));
}

// ----- finding text again -----

/// Text reduced for matching across editions (case, spacing, hyphenation at line ends, quote marks), with the index in
/// the original text each character came from.
class Folded {
  Folded(String text) {
    final out = StringBuffer();
    var lastSpace = true;
    for (var i = 0; i < text.length; i++) {
      var c = text[i];
      if (c == '­') continue;
      // "hyphen-\nated": drop the hyphen and the break.
      if (c == '-' && i + 1 < text.length && (text[i + 1] == '\n' || text[i + 1] == '\r')) {
        var j = i + 1;
        while (j < text.length && text[j].trim().isEmpty) {
          j++;
        }
        i = j - 1;
        continue;
      }
      if (c.trim().isEmpty) {
        if (lastSpace) continue;
        c = ' ';
        lastSpace = true;
      } else {
        lastSpace = false;
        c = switch (c) {
          '‘' || '’' || 'ʼ' => "'",
          '“' || '”' => '"',
          '–' || '—' => '-',
          _ => c.toLowerCase(),
        };
      }
      out.write(c);
      at.add(i);
    }
    folded = out.toString();
  }
  late final String folded;

  /// For each character of [folded], its index in the original text.
  final List<int> at = [];

  /// The original span of folded characters [start]..[end].
  (int, int) original(int start, int end) => (at[start], at[end - 1] + 1);
}

/// How well the text either side of a place matches: the length of the common end of [before] and [prefix], plus the
/// common start of [after] and [suffix].
int _contextScore(String before, String after, String prefix, String suffix) {
  var n = 0;
  for (var i = 1; i <= math.min(before.length, prefix.length); i++) {
    if (before[before.length - i] != prefix[prefix.length - i]) break;
    n++;
  }
  for (var i = 0; i < math.min(after.length, suffix.length); i++) {
    if (after[i] != suffix[i]) break;
    n++;
  }
  return n;
}

/// Where a highlight's [quote] is in [pages] (any order), as (page number, start, end) in that page's text: the
/// occurrence whose surrounding text best matches [prefix] and [suffix], nearest to [hintPage] on a tie. Null when the
/// words are not there.
(int, int, int)? findQuote(
  List<PageData> pages,
  String quote, {
  String prefix = '',
  String suffix = '',
  int hintPage = 1,
}) {
  final q = Folded(quote).folded.trim();
  if (q.isEmpty) return null;
  final pre = Folded(prefix).folded, suf = Folded(suffix).folded;
  (int, int, int)? best;
  var bestScore = -1;
  var bestDistance = 1 << 30;
  for (final p in pages) {
    final f = Folded(p.text);
    for (var at = f.folded.indexOf(q); at >= 0; at = f.folded.indexOf(q, at + 1)) {
      final score = _contextScore(
        f.folded.substring(math.max(0, at - pre.length), at),
        f.folded.substring(at + q.length, math.min(f.folded.length, at + q.length + suf.length)),
        pre,
        suf,
      );
      final distance = (p.number - hintPage).abs();
      if (score > bestScore || (score == bestScore && distance < bestDistance)) {
        final (s, e) = f.original(at, at + q.length);
        best = (p.number, s, e);
        bestScore = score;
        bestDistance = distance;
      }
    }
  }
  return best;
}

String _foldContext(String s) => Folded(s).folded.replaceAll(RegExp(r'[^\p{L}\p{N}_]+', unicode: true), ' ').trim();

/// Where an answer's blank is in [pages]: the answer line whose printed question matches [context] (ignoring case,
/// spacing and punctuation), the [ordinal]-th blank of it, nearest to [hintPage]. Returns (page number, index into
/// that page's rules), or null. Pages need their answer lines ([PageData.rules]).
(int, int)? findSlot(
  List<PageData> pages,
  String context, {
  int ordinal = 0,
  int hintPage = 1,
  double? hintY,
  bool loose = false,
}) {
  final exact = _findSlotExact(pages, context, ordinal: ordinal, hintPage: hintPage, hintY: hintY);
  if (exact != null || !loose) return exact;
  return _findSlotLoose(pages, context, hintPage: hintPage, hintY: hintY);
}

Set<String> _words(String s) => {
  for (final w in _foldContext(s).split(' '))
    if (w.length > 2) w,
};

/// When the question text differs a little (another program's reading of the page joined the lines of a list
/// differently): the line within two pages of [hintPage] whose question shares most words with [context] (at least
/// 80% of the shorter one's, and 4 words), the nearest to [hintPage] and then to [hintY].
(int, int)? _findSlotLoose(List<PageData> pages, String context, {int hintPage = 1, double? hintY}) {
  final want = _words(context);
  if (want.length < 4) return null;
  (int, int)? best;
  var bestScore = 0.0;
  var bestDistance = double.infinity;
  for (final p in pages) {
    if ((p.number - hintPage).abs() > 2) continue;
    for (var i = 0; i < p.rules.length; i++) {
      final r = p.rules[i];
      final have = _words(p.contextAt(r.x + 5, r.y));
      final shared = want.intersection(have).length;
      if (shared < 4 || have.isEmpty) continue;
      final score = shared / math.min(want.length, have.length);
      if (score < 0.8) continue;
      final double distance = (p.number - hintPage).abs() * 10000.0 + (hintY == null ? 0.0 : (r.y - hintY).abs());
      // Over the threshold, the nearest wins: a list's items share most of their words.
      if (distance < bestDistance || (distance == bestDistance && score > bestScore)) {
        best = (p.number, i);
        bestScore = score;
        bestDistance = distance;
      }
    }
  }
  return best;
}

/// [ordinal] < 0: any blank of the question, the nearest to [hintPage] and [hintY] (for marks counted another way, such
/// as Dogear's, one per answer rather than one per ruled line).
(int, int)? _findSlotExact(List<PageData> pages, String context, {int ordinal = 0, int hintPage = 1, double? hintY}) {
  final want = _foldContext(context);
  if (want.isEmpty) return null;
  (int, int)? best;
  var bestDistance = double.infinity;
  for (final p in pages) {
    var n = 0;
    for (var i = 0; i < p.rules.length; i++) {
      final r = p.rules[i];
      if (_foldContext(p.contextAt(r.x + 5, r.y)) != want) continue;
      if (ordinal >= 0 && n++ != ordinal) continue;
      final double distance = (p.number - hintPage).abs() * 10000.0 + (hintY == null ? 0.0 : (r.y - hintY).abs());
      if (distance < bestDistance) {
        best = (p.number, i);
        bestDistance = distance;
      }
    }
  }
  return best;
}

/// The page whose contents entry is called [name] (the outline of the other edition), or null.
int? pageNamed(List<(String, int)> outline, String name) {
  final want = _foldContext(name);
  if (want.isEmpty) return null;
  for (final (title, page) in outline) {
    if (_foldContext(title) == want) return page;
  }
  return null;
}

/// The writing area of the rule at [index] (with the ruled lines below it), as [slotFrom] gives it.
Slot slotAt(PageData p, int index) => slotFrom(p.rules, index, p.fontSize);
