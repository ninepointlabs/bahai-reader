/// Answer lines on a workbook page: printed rules, underscores, dotted lines. A port of Dogear's `rules.py`.
///
/// Worksheets leave space for answers as horizontal lines, drawn in every way: rules, runs of underscores, dot
/// leaders. They are found in the rendered page image rather than the text layer. The detector works on 8-bit grayscale
/// pixels and is unit tested on synthetic images.
///
/// Positions are PDF points from the page's top-left corner.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A line found on a page: its left end [x], vertical centre [y], length [w], and the blank height [space] above it,
/// where the answer is written.
class Rule {
  Rule(this.x, this.y, this.w, this.space);
  double x, y, w, space;

  @override
  String toString() => 'Rule(x: $x, y: $y, w: $w, space: $space)';
}

/// The writing area that starts at a line: [y] is the first line, [pitch] the distance between ruled lines (0 for one
/// line), [lines] how many, [indent] how far right of [x] the first line starts, [size] a font size in points.
class Slot {
  const Slot({
    required this.x,
    required this.y,
    required this.w,
    required this.pitch,
    required this.lines,
    required this.indent,
    required this.size,
  });
  final double x, y, w, pitch, indent, size;
  final int lines;
}

/// A line of text on the page, in reading order, with its box in points from the top-left: [x], [y] (top), [w], [h].
class TextLine {
  const TextLine(this.text, this.x, this.y, this.w, this.h);
  final String text;
  final double x, y, w, h;
}

const dark = 200; // gray level below which a pixel counts as ink
const minLengthPt = 14.0; // shorter strokes are hyphens and dashes, not answer lines
const shortPt = 28.0; // below this a line needs clear space at both ends (not a dash)
const sideGapPt = 1.5;
const groupMinPt = 120.0; // lines at least this long can form a ruled block
const maxThicknessPt = 3.0; // thicker is a filled bar or a picture
const minSpacePt = 7.0; // less room above means underlined text, not a blank
const maxSpacePt = 40.0; // stop measuring the blank above at this height
const gapPt = 2.5; // dots and dashes closer than this join into one line
const minFill = 0.3; // share of a line's length that must be ink (dotted ok)

double _r2(double v) => (v * 100).round() / 100;

/// The page image as ink (1) or paper (0), one byte per pixel.
class _Ink {
  _Ink(Uint8List gray, this.width, this.height, int stride) : ink = Uint8List(width * height) {
    for (var r = 0; r < height; r++) {
      final src = r * stride, dst = r * width;
      for (var c = 0; c < width; c++) {
        ink[dst + c] = gray[src + c] < dark ? 1 : 0;
      }
    }
  }
  final int width, height;
  final Uint8List ink;

  bool at(int r, int c) => ink[r * width + c] == 1;

  /// Ink pixels in row [r] from [x0] to before [x1] (clamped).
  int count(int r, int x0, int x1) {
    x0 = math.max(0, x0);
    x1 = math.min(width, x1);
    var n = 0;
    final base = r * width;
    for (var c = x0; c < x1; c++) {
      n += ink[base + c];
    }
    return n;
  }

  bool any(int r, int x0, int x1) => count(r, x0, x1) > 0;
}

/// Horizontal answer lines in a grayscale image of a page. [scale] is pixels per PDF point. Sorted top to bottom,
/// then left to right.
List<Rule> findRules(Uint8List gray, int width, int height, int stride, double scale) {
  if (width <= 0 || height <= 0 || scale <= 0) return [];
  final img = _Ink(gray, width, height, stride);
  final gap = math.max(1, (gapPt * scale).round());
  final minLen = minLengthPt * scale;

  // 1. Long, mostly-ink horizontal runs on each row (ink joined across gaps of up to [gap] pixels).
  final runs = <(int, int, int)>[];
  for (var r = 0; r < height; r++) {
    if (img.count(r, 0, width) < minLen * minFill) continue;
    var c = 0;
    while (c < width) {
      if (!img.at(r, c)) {
        c++;
        continue;
      }
      final x0 = c;
      var last = c;
      c++;
      while (c < width && c - last - 1 <= gap) {
        if (img.at(r, c)) last = c;
        c++;
      }
      final x1 = last + 1;
      c = x1;
      if (x1 - x0 >= minLen && img.count(r, x0, x1) >= (x1 - x0) * minFill) runs.add((r, x0, x1));
    }
  }

  // 2. Stack runs on neighbouring rows into bands (a line is 1-6 px thick).
  final bands = <List<int>>[]; // [top, bottom, x0, x1]
  var open = <List<int>>[];
  for (final (r, x0, x1) in runs) {
    List<int>? joined;
    for (final band in open) {
      // Rows of one line are about as long as each other; a word sitting on the end of a line is not part of it.
      final a = x1 - x0, b = band[3] - band[2];
      final short = math.min(a, b), long = math.max(a, b);
      if (band[1] >= r - 1 && math.min(x1, band[3]) - math.max(x0, band[2]) > 0.6 * short && short >= 0.5 * long) {
        band[1] = r;
        band[2] = math.min(band[2], x0);
        band[3] = math.max(band[3], x1);
        joined = band;
        break;
      }
    }
    if (joined == null) {
      final band = [r, r, x0, x1];
      bands.add(band);
      open.add(band);
    }
    open = [
      for (final b in open)
        if (b[1] >= r - 1) b,
    ];
  }

  final maxThick = math.max(1, (maxThicknessPt * scale).round());
  final probe = math.max(2, (1.0 * scale).round());
  final maxSpace = (maxSpacePt * scale).round();
  final rules = <Rule>[];
  for (final [top, bottom, bx0, bx1] in bands) {
    var x0 = bx0, x1 = bx1;
    if (bottom - top + 1 > maxThick) continue;
    var span = x1 - x0;

    // 3. Rows just below must be mostly blank. Text has strokes that run on vertically; a line does not.
    final below = bottom + probe;
    if (below < height && img.count(below, x0, x1) > 0.25 * span) continue;

    // 4. A line with vertical strokes at both ends is the edge of a box or a table, not something to write on.
    if (_verticalAt(img, x0, top, bottom, probe, scale) && _verticalAt(img, x1 - probe, top, bottom, probe, scale)) {
      continue;
    }

    // 5. A blank drawn on the baseline picks up the feet of the word right after it ("____ and"). Letters rise from
    // the line; a blank doesn't: trim them off its ends.
    final (t0, t1) = _trimLetters(img, top, bottom, x0, x1, scale);
    if (t0 != x0 || t1 != x1) {
      // A dotted line running into a word is a dot leader in a table of contents, not a blank.
      var solid = 0;
      for (var r = top; r <= bottom; r++) {
        solid = math.max(solid, img.count(r, t0, t1));
      }
      if (solid < 0.7 * (t1 - t0)) continue;
    }
    x0 = t0;
    x1 = t1;
    span = x1 - x0;
    if (span < minLen) continue;
    final inner0 = x0 + probe, inner1 = x1 - probe;

    // 6. A short line is only a blank with space at both ends (an em dash looks the same but touches the letters
    // beside it)...
    if (span < shortPt * scale &&
        !(_clearBeside(img, x0, top, bottom, scale, -1) && _clearBeside(img, x1, top, bottom, scale, 1))) {
      continue;
    }
    // ...and nothing right under it: the crossbar of an "H" or the top of a "7" has its stems below.
    if (span < shortPt * scale) {
      var stems = false;
      for (var r = bottom + 1; r < math.min(height, bottom + 1 + (2.5 * scale).round()); r++) {
        if (img.count(r, x0, x1) > 1) {
          stems = true;
          break;
        }
      }
      if (stems) continue;
    }

    // 7. Measure the blank room above, where the answer is written. Ignore a few stray pixels.
    var r = top - 1;
    final allowed = math.max(2, (0.03 * span).round());
    while (r >= 0 && top - r <= maxSpace && img.count(r, inner0, inner1) <= allowed) {
      r--;
    }
    final space = (top - 1 - r) / scale;
    if (space < minSpacePt) continue;
    rules.add(Rule(_r2(x0 / scale), _r2((top + bottom + 1) / 2 / scale), _r2(span / scale), _r2(space)));
  }
  rules.sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
  return _mergeSplit(rules);
}

(int, int) _trimLetters(_Ink img, int top, int bottom, int x0, int x1, double scale) {
  final int aboveTop = math.max(0, top - math.max(2, (1.5 * scale).round()));
  if (aboveTop >= top) return (x0, x1);
  bool letter(int x) {
    for (var r = aboveTop; r < top; r++) {
      if (img.at(r, x)) return true;
    }
    return false;
  }

  bool bare(int x) {
    for (var r = top; r <= bottom; r++) {
      if (img.at(r, x)) return false;
    }
    return true;
  }

  final pieces = <List<int>>[];
  var x = x0;
  while (x < x1) {
    if (bare(x)) {
      x++;
      continue;
    }
    final start = x;
    while (x < x1 && !bare(x)) {
      x++;
    }
    pieces.add([start, x]);
  }
  bool lettered(List<int> p) {
    for (var c = p[0]; c < p[1]; c++) {
      if (letter(c)) return true;
    }
    return false;
  }

  while (pieces.length > 1 && lettered(pieces.last)) {
    pieces.removeLast();
  }
  while (pieces.length > 1 && lettered(pieces.first)) {
    pieces.removeAt(0);
  }
  return pieces.isEmpty ? (x0, x1) : (pieces.first[0], pieces.last[1]);
}

bool _clearBeside(_Ink img, int x, int top, int bottom, double scale, int side) {
  final gap = math.max(2, (sideGapPt * scale).round());
  var (c0, c1) = side < 0 ? (x - gap, x) : (x + 1, x + 1 + gap);
  c0 = math.max(0, c0);
  c1 = math.min(img.width, c1);
  if (c1 <= c0) return true;
  final r0 = math.max(0, top - (6.0 * scale).round());
  for (var r = r0; r <= bottom; r++) {
    if (img.any(r, c0, c1)) return false;
  }
  return true;
}

bool _verticalAt(_Ink img, int x, int top, int bottom, int probe, double scale) {
  final reach = (6.0 * scale).round();
  bool solid(int r0, int r1) {
    if (r0 < 0 || r1 > img.height) return false;
    for (var r = r0; r < r1; r++) {
      if (!img.any(r, math.max(0, x - 1), x + probe + 1)) return false;
    }
    return true;
  }

  return solid(bottom + 1, bottom + 1 + reach) || solid(top - reach, top);
}

/// Joins pieces of one line that a crossing border split in two.
List<Rule> _mergeSplit(List<Rule> rules) {
  final out = <Rule>[];
  for (final rule in rules) {
    final prev = out.lastOrNull;
    if (prev != null && (prev.y - rule.y).abs() < 1.0) {
      final gap = rule.x - (prev.x + prev.w);
      if (gap >= 0 && gap < 3.0) {
        prev.w = _r2(rule.x + rule.w - prev.x);
        prev.space = math.min(prev.space, rule.space);
        continue;
      }
    }
    out.add(Rule(rule.x, rule.y, rule.w, rule.space));
  }
  return out;
}

/// The page's usual font size in points, from its text line heights (0 when the page has no text).
double textSize(List<TextLine> lines) {
  final heights = [
    for (final l in lines)
      if (l.h > 2) l.h,
  ]..sort();
  if (heights.isEmpty) return 0;
  return heights[heights.length ~/ 2] * 1.05;
}

/// Whether [rule] is the first ruled line under a blank that ends the question's own line: wide, starting further
/// left and ending at the same place, one row down.
bool _continues(Rule first, Rule rule) =>
    rule.w >= groupMinPt &&
    rule.x < first.x - 4.0 &&
    (rule.x + rule.w - first.x - first.w).abs() <= 4.0 &&
    rule.y - first.y >= 9.0 &&
    rule.y - first.y <= 40.0;

/// The writing area that starts at `rules[index]`: that line plus the evenly spaced lines right below it with the same
/// left and right ends, like ruled paper under a question. A blank at the end of the question's line ("2. Why? ____")
/// starts the ruled lines below it. [size] is the page's text size, if known.
Slot slotFrom(List<Rule> rules, int index, [double size = 0]) {
  final first = rules[index];
  final rest = rules.sublist(index + 1);
  final lead = rest.isNotEmpty && _continues(first, rest.first) ? rest.first : first;
  var group = identical(lead, first) ? [first] : [first, lead];
  var pitch = lead.y - first.y;
  Rule? stop;
  // Short blanks stacked in a column (one per sentence) are separate answers; ruled lines for writing are wide.
  if (lead.w >= groupMinPt) {
    for (final rule in rest.sublist(group.length - 1)) {
      final last = group.last;
      final d = rule.y - last.y;
      if (d < 1.0) continue; // another blank further along the same row
      if ((rule.x - lead.x).abs() > 4.0 ||
          (rule.x + rule.w - lead.x - lead.w).abs() > 4.0 ||
          d < 9.0 ||
          d > 40.0 ||
          (pitch != 0 && (d - pitch).abs() > 0.15 * pitch)) {
        stop = rule;
        break;
      }
      if (pitch == 0) pitch = d;
      group.add(rule);
    }
  }
  var leadRule = lead;
  if (!identical(lead, first) && stop != null && (stop.y - group.last.y - pitch).abs() <= 0.15 * pitch) {
    // More blanks in the same rhythm: a sentence with blanks in it that wraps, not ruled lines under a question.
    group = [first];
    leadRule = first;
    pitch = 0;
  }
  final room = pitch != 0 ? math.min(first.space, pitch) : first.space;
  final s = math.max(6.0, math.min(math.min(size != 0 ? size : 12.0, 13.0), room * (size != 0 ? 0.8 : 0.55)));
  return Slot(
    x: leadRule.x,
    y: first.y,
    w: _r2(group.map((r) => r.x + r.w).reduce(math.min) - leadRule.x),
    pitch: _r2(pitch),
    lines: group.length,
    indent: _r2(first.x - leadRule.x),
    size: _r2(s),
  );
}

/// Index of the line whose writing area contains ([x], [y]), or -1. The area is the blank above the line (up to
/// 24 pt) plus a little below it, so clicking on the line itself works too.
int ruleAt(List<Rule> rules, double x, double y) {
  var best = -1;
  var bestD = double.infinity;
  for (var i = 0; i < rules.length; i++) {
    final rule = rules[i];
    if (x < rule.x - 2 || x > rule.x + rule.w + 2) continue;
    final above = math.min(rule.space, 24.0);
    if (rule.y - above <= y && y <= rule.y + 4.0) {
      final d = (rule.y - y).abs();
      if (d < bestD) {
        best = i;
        bestD = d;
      }
    }
  }
  return best;
}

final _item = RegExp(r'^\s*(?:\(?[0-9]{1,3}[.)]|\(?[a-zA-Z][.)]|[ivxIVX]{1,4}[.)]|[•·\-–])\s');
final _blank = RegExp(r'_{2,}|(?:\.\s?){4,}');
final _spaces = RegExp(r'\s+');
final _hyphenBreak = RegExp(r'(\w)-\s*\r?\n\s*(\w)');

/// Text copied out of a PDF as one readable paragraph: lines joined, hyphenation at line ends undone.
String cleanPdfText(String text) {
  text = text.replaceAll('­', '');
  text = text.replaceAllMapped(_hyphenBreak, (m) => '${m[1]}${m[2]}');
  return text.replaceAll(_spaces, ' ').trim();
}

/// The printed text that goes with an answer line at ([x], [y]): the text on the line's row and the other lines of
/// the same item (the question). Blanks printed as underscores or dots come out as "___". Blanks drawn as lines leave
/// no text; given the page's [rules] and [charLefts] (the left edge of each character of `lines[i]`), they come out
/// as "___" too.
String contextFor(
  List<TextLine> lines,
  double x,
  double y, {
  int maxLines = 4,
  List<Rule> rules = const [],
  List<double> Function(int)? charLefts,
}) {
  List<Rule> onRow(int i) {
    final l = lines[i];
    return [
      for (final b in rules)
        if (l.y <= b.y && b.y <= l.y + l.h + 6.0) b,
    ]..sort((a, b) => a.x.compareTo(b.x));
  }

  double left(int i) => [lines[i].x, for (final b in onRow(i)) b.x].reduce(math.min);

  bool joins(int a, int b) {
    final ra = lines[a], rb = lines[b];
    final d = rb.y - (ra.y + ra.h);
    return d >= 0 && d <= math.max(ra.h, rb.h) + 6.0 && (left(a) - left(b)).abs() <= 60.0;
  }

  double overlap(TextLine l) => math.min(l.y + l.h, y + 1.0) - math.max(l.y, y - 12.0);

  if (lines.isEmpty) return '';
  var row = 0;
  for (var i = 1; i < lines.length; i++) {
    if (overlap(lines[i]) > overlap(lines[row])) row = i;
  }
  if (overlap(lines[row]) <= 0) {
    // The line has a row of its own: the question is the text above it.
    final above = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].y + lines[i].h <= y) i,
    ];
    if (above.isEmpty) return '';
    row = above.reduce((a, b) => lines[b].y + lines[b].h > lines[a].y + lines[a].h ? b : a);
    if (y - (lines[row].y + lines[row].h) > 60.0) return '';
  }
  final picked = [row];
  while (picked.length < maxLines && !_item.hasMatch(lines[picked.first].text)) {
    final prev = picked.first - 1;
    if (prev < 0 || !joins(prev, picked.first)) break;
    picked.insert(0, prev);
  }
  // A question that wraps: its next lines, up to the next item.
  while (picked.length < maxLines) {
    final next = picked.last + 1;
    if (next >= lines.length || _item.hasMatch(lines[next].text) || !joins(picked.last, next)) break;
    picked.add(next);
  }

  String withBlanks(int i) {
    var text = lines[i].text;
    final drawn = onRow(i);
    // Blanks typed as underscores or dots are in the text already.
    if (drawn.isEmpty || charLefts == null || _blank.hasMatch(text)) return text;
    final xs = charLefts(i);
    for (final blank in drawn.reversed) {
      // Characters well inside it: not a gap in the text. (The word after a blank can start right at its end.)
      if (xs.any((cx) => blank.x + 2 < cx && cx < blank.x + blank.w - 2)) continue;
      final k = math.min(text.length, xs.where((cx) => cx < blank.x).length);
      text = '${text.substring(0, k)} ___ ${text.substring(k)}';
    }
    return text;
  }

  // Glyphs with no text behind them come out as U+FFFD.
  var text = cleanPdfText([for (final i in picked) withBlanks(i)].join('\n').replaceAll('�', ''));
  text = text.replaceAll(_spaces, ' ').replaceAllMapped(RegExp(r' ([,.;:?!])'), (m) => m[1]!);
  text = text.replaceAll(_blank, '___').replaceAll(_spaces, ' ').trim();
  // "Name of the process: ___" is a label; its blank adds nothing.
  text = text.replaceAll(RegExp(r':\s*___$'), ':');
  return text.length <= 300 ? text : '…${text.substring(text.length - 299)}';
}
