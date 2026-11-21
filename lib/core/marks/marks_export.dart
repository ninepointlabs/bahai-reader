/// Markdown export of the highlights and notes made in the writings and prayers (for a notes vault such as Obsidian):
/// grouped by book (or prayer category), each quoted with its citation and followed by its note.
library;

import '../library/citations.dart';
import '../library/passage.dart';
import 'highlight.dart';

/// One highlight with the passage it is on (null when that passage is not in the current library) and where it is
/// ("Gleanings · CXXXVIII"), and the group it is listed under (its book, or Prayers).
typedef HighlightPlace = ({Highlight highlight, Passage? passage, String group, String place});

String renderHighlightsMarkdown(List<HighlightPlace> items, {DateTime? exportedAt}) {
  final stamp = (exportedAt ?? DateTime.now()).toIso8601String().split('.').first;
  final out = <String>[
    '---',
    'title: "Highlights and notes"',
    'generator: bahai-reader',
    'exported: $stamp',
    'highlights: ${items.length}',
    'tags: [bahai-reader, highlights]',
    '---',
    '',
    '# Highlights and notes',
    '',
    '*From Bahá’í Reader. This file is made again on every export, so keep your own edits elsewhere. The texts keep '
        'their own copyright, given with each.*',
    '',
  ];
  final groups = <String, List<HighlightPlace>>{};
  for (final i in items) {
    (groups[i.group] ??= []).add(i);
  }
  for (final MapEntry(key: group, value: list) in groups.entries) {
    out.addAll(['## $group', '']);
    for (final i in list) {
      final p = i.passage;
      final words = i.highlight.words.trim();
      final quoted = p == null ? words : clipping(p, words);
      for (final line in quoted.split('\n')) {
        out.add('> $line'.trimRight());
      }
      if (i.place.isNotEmpty) out.add('> ${p == null ? '— ' : ''}*${i.place}*');
      out.add('');
      if (i.highlight.note?.trim() case final note? when note.isNotEmpty) out.addAll([note, '']);
    }
  }
  if (items.isEmpty) out.addAll(['*No highlights yet.*', '']);
  return '${out.join('\n').replaceAll(RegExp(r'\n+$'), '')}\n';
}
