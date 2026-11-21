/// What the Study reader needs from one PDF page, in PDF points from the page's top-left corner (pdfrx gives
/// bottom-left coordinates; everything stored is converted to top-left, as Dogear stores it).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'rules.dart';

/// A box in points from the page's top-left corner.
class Box {
  const Box(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
  double get right => x + w;
  double get bottom => y + h;

  List<double> toJson() => [_r(x), _r(y), _r(w), _r(h)];
  static Box? fromJson(Object? v) => v is List && v.length == 4 && v.every((e) => e is num)
      ? Box((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble(), (v[3] as num).toDouble())
      : null;

  static double _r(double v) => (v * 100).round() / 100;

  @override
  bool operator ==(Object other) => other is Box && other.x == x && other.y == y && other.w == w && other.h == h;
  @override
  int get hashCode => Object.hash(x, y, w, h);
  @override
  String toString() => 'Box($x, $y, $w, $h)';
}

/// One page's text (with a box per character), its text lines and its answer lines.
class PageData {
  PageData({
    required this.number,
    required this.width,
    required this.height,
    required this.text,
    required this.chars,
    required this.lines,
    required this.lineStarts,
    required this.rules,
  });

  /// 1-based page number.
  final int number;
  final double width, height;

  /// The page's text, and a box per character of it (zero-size for line breaks).
  final String text;
  final List<Box> chars;

  /// Text lines in reading order, and where each starts in [text].
  final List<TextLine> lines;
  final List<int> lineStarts;
  final List<Rule> rules;

  late final double fontSize = textSize(lines);

  /// The left edge of each character of `lines[i]`.
  List<double> charLefts(int i) {
    final start = lineStarts[i];
    return [for (var k = 0; k < lines[i].text.length; k++) chars[start + k].x];
  }

  /// The printed question around an answer line at ([x], [y]).
  String contextAt(double x, double y) => contextFor(lines, x, y, rules: rules, charLefts: charLefts);

  /// The character nearest to a point (for selection), or -1 when the page has no text.
  int charAt(double x, double y) {
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (c.w <= 0 && c.h <= 0) continue;
      final dx = x < c.x ? c.x - x : (x > c.right ? x - c.right : 0.0);
      final dy = y < c.y ? c.y - y : (y > c.bottom ? y - c.bottom : 0.0);
      final d = dy * 4 + dx; // the same line first
      if (d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  /// Boxes covering characters [start] to before [end], one per line.
  List<Box> boxesFor(int start, int end) {
    final out = <Box>[];
    double? x0, y0, x1, y1;
    void flush() {
      if (x0 != null) out.add(Box(x0!, y0!, x1! - x0!, y1! - y0!));
      x0 = y0 = x1 = y1 = null;
    }

    for (var i = math.max(0, start); i < math.min(end, chars.length); i++) {
      final c = chars[i];
      if (text[i] == '\n' || (c.w <= 0 && c.h <= 0)) {
        flush();
        continue;
      }
      if (x0 != null && (c.y > y1! || c.bottom < y0! || c.x < x0! - 1)) flush();
      x0 = x0 == null ? c.x : math.min(x0!, c.x);
      y0 = y0 == null ? c.y : math.min(y0!, c.y);
      x1 = x1 == null ? c.right : math.max(x1!, c.right);
      y1 = y1 == null ? c.bottom : math.max(y1!, c.bottom);
    }
    flush();
    return out;
  }

  /// Builds a page's data from its text and a grayscale rendering at [scale] pixels per point.
  static PageData build({
    required int number,
    required double width,
    required double height,
    required String text,
    required List<Box> chars,
    Uint8List? gray,
    int grayWidth = 0,
    int grayHeight = 0,
    double scale = 2,
  }) {
    final lines = <TextLine>[];
    final starts = <int>[];
    var start = 0;
    void line(int end) {
      if (end > start) {
        final cs = [
          for (var i = start; i < end; i++)
            if (chars[i].w > 0 || chars[i].h > 0) chars[i],
        ];
        final content = text.substring(start, end);
        if (cs.isNotEmpty && content.trim().isNotEmpty) {
          final x0 = cs.map((c) => c.x).reduce(math.min), y0 = cs.map((c) => c.y).reduce(math.min);
          final x1 = cs.map((c) => c.right).reduce(math.max), y1 = cs.map((c) => c.bottom).reduce(math.max);
          lines.add(TextLine(content, x0, y0, x1 - x0, y1 - y0));
          starts.add(start);
        }
      }
    }

    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\n' || text[i] == '\r') {
        line(i);
        start = i + 1;
      }
    }
    line(text.length);
    final rules = gray == null ? <Rule>[] : findRules(gray, grayWidth, grayHeight, grayWidth, scale);
    return PageData(
      number: number,
      width: width,
      height: height,
      text: text,
      chars: chars,
      lines: lines,
      lineStarts: starts,
      rules: rules,
    );
  }

  /// Reads a pdfrx page: its text with character boxes, and its answer lines from a rendering at up to 2 px/pt.
  static Future<PageData> load(PdfPage page) async {
    final w = page.width, h = page.height;
    final raw = await page.loadText();
    final text = raw?.fullText ?? '';
    final chars = <Box>[
      for (var i = 0; i < text.length; i++)
        if (raw != null && i < raw.charRects.length)
          Box(raw.charRects[i].left, h - raw.charRects[i].top, raw.charRects[i].width, raw.charRects[i].height)
        else
          const Box(0, 0, 0, 0),
    ];
    final scale = math.min(2.0, 2400 / math.max(w, h));
    final pw = (w * scale).round(), ph = (h * scale).round();
    final image = await page.render(fullWidth: pw.toDouble(), fullHeight: ph.toDouble(), width: pw, height: ph);
    Uint8List? gray;
    if (image != null) {
      // BGRA, possibly transparent where the page has no background: put it on white.
      final px = image.pixels;
      gray = Uint8List(pw * ph);
      for (var i = 0, j = 0; i < gray.length; i++, j += 4) {
        final a = px[j + 3];
        final lum = (px[j + 2] * 299 + px[j + 1] * 587 + px[j] * 114) ~/ 1000;
        gray[i] = 255 - ((255 - lum) * a ~/ 255);
      }
      image.dispose();
    }
    return build(
      number: page.pageNumber,
      width: w,
      height: h,
      text: text,
      chars: chars,
      gray: gray,
      grayWidth: pw,
      grayHeight: ph,
      scale: scale,
    );
  }
}
