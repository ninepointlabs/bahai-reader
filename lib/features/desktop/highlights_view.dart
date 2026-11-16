import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../../core/marks/highlight.dart';
import 'shell_model.dart';
import 'widgets.dart';

/// Saved → Highlights & notes: every highlight, newest first, each opening its passage at the highlight.
class HighlightsView extends StatelessWidget {
  const HighlightsView({super.key, required this.model});
  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = ReaderColors.of(context);
    final records = state.highlights.reversed.toList();
    final notes = records.where((r) => r.note != null).length;
    final size = state.settings.textSize;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Highlights & notes', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.accentText)),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                records.isEmpty
                    ? 'No highlights yet. Select words in a passage to highlight them in a colour or add a note; Ctrl+H highlights the selection.'
                    : '${records.length} highlight${records.length == 1 ? '' : 's'}, $notes with a note',
                style: dimStyle(context),
              ),
            ),
            for (final r in records) ...[
              _card(context, state, r, size),
              const SizedBox(height: 10),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, AppState state, Highlight r, double size) {
    final p = ReaderColors.of(context);
    final item = state.passageOf(r.id);
    var place = item == null
        ? 'This passage is not in the current library.'
        : [bookOf(item) ?? (item.tags.isNotEmpty ? item.tags.first : null), heading(item)].whereType<String>().join(' · ');
    if (item != null && item.id != r.id) place += ' · highlighted in ${state.languageInfo(languageOf(r.id)).english}';
    return Opacity(
      opacity: item == null ? 0.6 : 1,
      child: CardButton(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: item == null
            ? null
            : () {
                final at = item.id == r.id ? anchor(item.text, r)?.$1 : null;
                model.openPassage(item, scrollTo: at);
              },
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, decoration: BoxDecoration(color: p.highlight(r.color), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  excerpt(r.words, 300),
                  style: TextStyle(
                    fontFamily: readingFace(context).fontFamily,
                    fontFamilyFallback: readingFace(context).fontFamilyFallback,
                    fontSize: (size - 4).clamp(15, 40),
                  ),
                ),
                const SizedBox(height: 4),
                Text(place, style: dimStyle(context)),
                if (r.note != null) ...[
                  const SizedBox(height: 6),
                  Text(r.note!, maxLines: 8, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
