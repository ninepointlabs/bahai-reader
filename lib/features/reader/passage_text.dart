import 'package:flutter/material.dart';

import '../../core/app/theme.dart';
import '../../core/library/passage.dart';
import '../../core/marks/highlight.dart';

/// A highlight as drawn: the stored record and where it is in the text now.
typedef DrawnHighlight = (Highlight record, int start, int end);

/// Builds the passage's text as styled spans. The spans concatenate to exactly `passage.text`, so selection offsets
/// are offsets into the passage text: the same numbers highlights are stored with.
TextSpan passageSpans({
  required Passage passage,
  required TextStyle base,
  required Palette palette,
  required Color muted,
  List<DrawnHighlight> highlights = const [],
  (int, int)? hit,
  Color? hitColor,
}) {
  final text = passage.text;
  final cuts = <int>{0, text.length};
  for (final s in passage.spans) {
    cuts..add(s.start.clamp(0, text.length))..add(s.end.clamp(0, text.length));
  }
  for (final (a, b) in passage.directions) {
    cuts..add(a.clamp(0, text.length))..add(b.clamp(0, text.length));
  }
  for (final (_, a, b) in highlights) {
    cuts..add(a)..add(b);
  }
  if (hit != null) cuts..add(hit.$1)..add(hit.$2);
  final points = cuts.toList()..sort();
  final children = <TextSpan>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i], b = points[i + 1];
    if (a >= b) continue;
    var style = base;
    // An obligatory prayer's directions are in italics, so the prayer itself stands out.
    if (passage.directions.any((d) => d.$1 <= a && b <= d.$2)) style = style.copyWith(fontStyle: FontStyle.italic);
    for (final s in passage.spans) {
      if (s.start <= a && b <= s.end) {
        style = switch (s.kind) {
          'i' => style.copyWith(fontStyle: FontStyle.italic),
          'b' => style.copyWith(fontWeight: FontWeight.w700),
          'u' => style.copyWith(decoration: TextDecoration.underline, decorationThickness: 0.8),
          'heading' => style.copyWith(fontWeight: FontWeight.w700, fontSize: (base.fontSize ?? 20) * 1.1),
          'num' => style.copyWith(color: muted, fontSize: (base.fontSize ?? 20) * 0.7),
          'quote' => style.copyWith(color: Color.lerp(base.color, muted, 0.35), fontSize: (base.fontSize ?? 20) * 0.95),
          _ => style,
        };
      }
    }
    for (final (record, ha, hb) in highlights) {
      if (ha <= a && b <= hb) {
        style = style.copyWith(backgroundColor: palette.highlight(record.color));
        if (record.note != null) {
          // A highlight with a note is underlined, as in the GTK app.
          style = style.copyWith(
              decoration: TextDecoration.combine([if (style.decoration != null) style.decoration!, TextDecoration.underline]));
        }
      }
    }
    if (hit != null && hit.$1 <= a && b <= hit.$2) {
      style = style.copyWith(backgroundColor: hitColor, fontWeight: FontWeight.w600);
    }
    children.add(TextSpan(text: text.substring(a, b), style: style));
  }
  return TextSpan(style: base, children: children);
}
