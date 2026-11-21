/// A table of contents for PDFs that don't have one. A port of Dogear's `contents.py`.
///
/// The text layer gives lines with their boxes but no fonts, so headings are recognized by what can be seen: a printed
/// Contents page ("Life's Springtime ........ 1"), lines set clearly larger than the body text, and lines like
/// "SECTION 2" or "Chapter 4: Light" on their own.
library;

import 'dart:math' as math;

import 'rules.dart' show TextLine;

/// An entry: its title, level (0 is the top), page (0-based, as in Dogear) and the top of the heading in points.
class ContentsEntry {
  const ContentsEntry(this.title, this.level, this.page, this.y);
  final String title;
  final int level, page;
  final double y;

  @override
  String toString() => '($title, $level, $page, $y)';
}

/// Bump when the detection changes, so saved tables are built again.
const contentsVersion = 1;

const _contentsPages = 15;
const _headingRatio = 1.2;
const _maxSizeLevels = 3;
const _maxPerPage = 1.5;

final _entry = RegExp(
  r'^(?<title>.*?\S)\s*(?:(?:\.\s*){3,}|…+|\s{3,})\s*(?<page>\d{1,4}|[ivxlcdm]{1,7})$',
  caseSensitive: false,
);
final _numbered = RegExp(
  r'^(?:section|chapter|unit|part|lesson|module)\s+(?:\d{1,3}|[ivxlc]{1,6}|[a-z])\b\s*(?:[.:–—-]\s*)?(?<rest>.*)$',
  caseSensitive: false,
);
final _contentsTitle = RegExp(r'^(table of )?contents$', caseSensitive: false);

/// The table of contents of a document whose text lines are [pages] (each page's lines in reading order) and page
/// labels [labels]. Empty when nothing looks like headings.
List<ContentsEntry> buildContents(List<List<TextLine>> pages, List<String> labels) {
  final heights = [
    for (final lines in pages)
      for (final l in lines)
        if (l.h > 2) l.h,
  ]..sort();
  if (heights.isEmpty) return const [];
  final body = heights[heights.length ~/ 2];
  final printed = _printed(pages, labels);
  List<ContentsEntry> out;
  if (printed.isNotEmpty) {
    // Headings before the first printed entry are the title pages and the Contents itself.
    final first = printed.map((e) => e.page).reduce(math.min);
    final deeper = printed.map((e) => e.level).reduce(math.max) + 1;
    final extra = [
      for (final h in _headings(pages, body, first))
        if (!printed.any((e) => _same(h, e))) ContentsEntry(h.title, deeper, h.page, h.y),
    ];
    out = [...printed, ...extra];
  } else {
    // The cover and title pages set the title in sizes used nowhere else.
    out = _headings(pages, body, pages.length > 10 ? 3 : 0);
  }
  out.sort((a, b) => a.page != b.page ? a.page.compareTo(b.page) : a.y.compareTo(b.y));
  return out.length >= 2 ? out : const [];
}

String _norm(String text) => text.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

bool _same(ContentsEntry heading, ContentsEntry entry) {
  if ((heading.page - entry.page).abs() > 1) return false;
  final a = _norm(heading.title), b = _norm(entry.title);
  return a.isNotEmpty && b.isNotEmpty && (a == b || a.startsWith(b) || b.startsWith(a));
}

/// Spaces collapsed; SHOUTED headings in normal case.
String _tidy(String text) {
  text = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (text == text.toUpperCase() && text != text.toLowerCase() && text.length > 3) {
    text = [for (final w in text.split(' ')) w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()].join(' ');
  }
  return text;
}

// ----- the printed Contents page -----

List<ContentsEntry> _printed(List<List<TextLine>> pages, List<String> labels) {
  final byLabel = <String, int>{};
  for (var i = 0; i < labels.length; i++) {
    byLabel.putIfAbsent(labels[i].trim().toLowerCase(), () => i);
  }
  var best = <(String, String, double, int)>[];
  for (var p = 0; p < math.min(pages.length, _contentsPages); p++) {
    final entries = <(String, String, double, int)>[];
    var pending = '';
    for (final l in pages[p]) {
      final text = l.text.trim();
      final m = _entry.firstMatch(text);
      if (m != null && RegExp('[A-Za-z]').hasMatch(m.namedGroup('title')!)) {
        final t = m.namedGroup('title')!;
        final title = pending.isNotEmpty ? '$pending $t'.trim() : t;
        entries.add((title.replaceAll(RegExp(r'[ .]+$'), ''), m.namedGroup('page')!.toLowerCase(), l.x, p));
        pending = '';
      } else if (entries.isNotEmpty && !_contentsTitle.hasMatch(text) && text.length < 80) {
        pending = text;
      } else {
        pending = '';
      }
    }
    // The Contents may run on to the next page.
    if (best.isNotEmpty && entries.isNotEmpty && best.last.$4 == p - 1) {
      best = [...best, ...entries];
    } else if (entries.length >= 3 && entries.length > best.length) {
      best = entries;
    }
  }
  if (best.length < 3) return const [];
  final contentsPage = best.last.$4;
  final lefts = {for (final e in best) e.$3.round()}.toList()..sort();
  final levels = <int, int>{};
  for (final x in lefts) {
    // Indents a few points apart are the same level.
    final prev = levels.keys.where((k) => (k - x).abs() <= 6).firstOrNull;
    levels[x] = prev != null ? levels[prev]! : levels.values.toSet().length;
  }
  final out = <ContentsEntry>[];
  for (final (title, label, x, _) in best) {
    var page = byLabel[label];
    final found = _findTitle(pages, title, contentsPage);
    // The printed numbers can differ from the PDF's own page labels: where the title is printed wins.
    if (found != null && (page == null || page <= contentsPage || _titleY(pages[page], title) == 0)) page = found.$1;
    if (page == null && RegExp(r'^\d+$').hasMatch(label)) page = int.parse(label) - 1;
    if (page == null || page < 0 || page >= pages.length) continue;
    final y = found != null && found.$1 == page ? found.$2 : _titleY(pages[page], title);
    out.add(ContentsEntry(_tidy(title), math.min(levels[x.round()]!, 2), page, y));
  }
  return out.length >= 3 ? out : const [];
}

double _titleY(List<TextLine> lines, String title) {
  final n = _norm(title);
  final want = n.length > 30 ? n.substring(0, 30) : n;
  for (final l in lines) {
    if (want.isNotEmpty && _norm(l.text).startsWith(want)) return l.y;
  }
  return 0;
}

/// The page where a printed entry's title appears largest, after the Contents page.
(int, double)? _findTitle(List<List<TextLine>> pages, String title, int after) {
  final n = _norm(title);
  final want = n.length > 30 ? n.substring(0, 30) : n;
  (int, double, double)? best;
  for (var p = after + 1; p < pages.length; p++) {
    for (final l in pages[p]) {
      if (want.isNotEmpty && _norm(l.text).startsWith(want) && (best == null || l.h > best.$3)) best = (p, l.y, l.h);
    }
  }
  return best == null ? null : (best.$1, best.$2);
}

// ----- headings in the text -----

List<ContentsEntry> _headings(List<List<TextLine>> pages, double body, int start) {
  // Running headers and footers repeat on many pages: not headings.
  final seen = <String, int>{};
  for (final lines in pages) {
    for (final t in {for (final l in lines) _norm(l.text)}) {
      seen[t] = (seen[t] ?? 0) + 1;
    }
  }
  final repeated = {
    for (final e in seen.entries)
      if (e.value > math.max(3, pages.length ~/ 10)) e.key,
  };
  bool usable(String text) {
    final n = _norm(text);
    return text.length >= 2 &&
        text.length <= 100 &&
        !repeated.contains(n) &&
        RegExp('[A-Za-z]{2}').hasMatch(text) &&
        !_entry.hasMatch(text) &&
        !RegExp(r'[$@]|:$').hasMatch(text);
  }

  final found = <(int, int, double, String)>[]; // (size, or 0 for "Section 2" lines; page; y; title)
  for (var p = 0; p < pages.length; p++) {
    if (p < start) continue;
    final lines = pages[p];
    var i = 0;
    while (i < lines.length) {
      final l = lines[i];
      final text = l.text.trim();
      final h = l.h;
      // Headings start with a capital or a number and aren't sentences.
      if (h >= body * _headingRatio &&
          usable(text) &&
          RegExp('^[A-Z0-9]').hasMatch(text) &&
          !RegExp(r'[.,;]$').hasMatch(text)) {
        // A heading set on two or three lines is one entry.
        var title = text;
        var last = l;
        while (i + 1 < lines.length &&
            title.length < 100 &&
            (lines[i + 1].h - h).abs() <= math.max(1.0, h * 0.08) &&
            lines[i + 1].y - last.y >= 0 &&
            lines[i + 1].y - last.y <= h * 1.6 &&
            usable(lines[i + 1].text.trim())) {
          i++;
          last = lines[i];
          title += ' ${last.text.trim()}';
        }
        found.add((h.round(), p, l.y, title));
      } else if (text.length <= 60 && _numbered.hasMatch(text) && !RegExp(r'[.,;]$').hasMatch(text) && usable(text)) {
        found.add((0, p, l.y, text));
      }
      i++;
    }
  }
  // The biggest sizes are the top levels; "Section 2" lines go below them.
  final sizes = {
    for (final f in found)
      if (f.$1 != 0) f.$1,
  }.toList()..sort((a, b) => b.compareTo(a));
  final rank = <int, int>{};
  for (final s in sizes) {
    // Sizes within a point or two are one level.
    final prev = rank.keys.where((k) => (k - s).abs() <= math.max(1, k * 0.08)).firstOrNull;
    rank[s] = prev != null ? rank[prev]! : rank.values.toSet().length;
  }
  // Headings are few: a size on every other line is a table or a form.
  final perLevel = <int, int>{};
  for (final f in found) {
    if (f.$1 != 0) perLevel[rank[f.$1]!] = (perLevel[rank[f.$1]!] ?? 0) + 1;
  }
  final scanned = math.max(1, pages.length - start);
  final kept = ([
    for (final e in perLevel.entries)
      if (e.value <= scanned * _maxPerPage) e.key,
  ]..sort()).take(_maxSizeLevels).toList();
  final out = <ContentsEntry>[];
  for (final (s, p, y, title) in found) {
    if (s == 0 || kept.contains(rank[s])) {
      out.add(ContentsEntry(_tidy(title), s != 0 ? kept.indexOf(rank[s]!) : kept.length, p, y));
    }
  }
  // Levels without gaps: 0, 1, 2.
  final used = {for (final e in out) e.level}.toList()..sort();
  return [
    for (final e in out) ContentsEntry(e.title, math.min(used.indexOf(e.level), _maxSizeLevels - 1), e.page, e.y),
  ];
}
