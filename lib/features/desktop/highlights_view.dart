import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../../core/marks/highlight.dart';
import '../study/study_marks_list.dart';
import '../marks/marks_actions.dart';
import 'shell_model.dart';
import 'widgets.dart';

/// Saved → Highlights & notes: everything you have marked, newest first: in the writings and prayers (each opening its
/// passage at the highlight), in Study (each opening its book at its place), or both. Searchable; the writings'
/// highlights can be exported to Markdown.
class HighlightsView extends StatefulWidget {
  const HighlightsView({super.key, required this.model});
  final ShellModel model;

  @override
  State<HighlightsView> createState() => _HighlightsViewState();
}

enum _Scope { writings, study, all }

class _HighlightsViewState extends State<HighlightsView> {
  _Scope scope = _Scope.writings;
  String query = '';

  ShellModel get model => widget.model;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = ReaderColors.of(context);
    final study = state.study;
    final fold = state.folder?.fold ?? (String s) => s.toLowerCase();
    final q = fold(query.trim());
    bool matches(Highlight r) {
      if (q.isEmpty) return true;
      final item = state.passageOf(r.id);
      return fold('${r.words} ${r.note ?? ''} ${item == null ? '' : placeOf(item)}').contains(q);
    }

    final records = [
      for (final r in state.highlights.reversed)
        if (matches(r)) r,
    ];
    final notes = records.where((r) => r.note != null).length;
    final size = state.settings.textSize;
    final showWritings = scope != _Scope.study;
    final showStudy = study != null && scope != _Scope.writings;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Highlights & notes',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.accentText),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (study != null)
                    SegmentedButton<_Scope>(
                      segments: const [
                        ButtonSegment(value: _Scope.writings, label: Text('Writings & prayers')),
                        ButtonSegment(value: _Scope.study, label: Text('Study')),
                        ButtonSegment(value: _Scope.all, label: Text('Everything')),
                      ],
                      selected: {scope},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() => scope = v.first),
                    ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search highlights and notes',
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                  ),
                  if (showWritings)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Export to Markdown…'),
                      onPressed: records.isEmpty ? null : () => exportHighlights(context, state, records),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (showWritings) ...[
                if (scope == _Scope.all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Writings & prayers',
                      style: TextStyle(fontWeight: FontWeight.w600, color: p.accentText),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    state.highlights.isEmpty
                        ? 'No highlights yet. Select words in a passage to highlight them in a colour or add a note; Ctrl+H highlights the selection.'
                        : records.isEmpty
                        ? 'No highlights match “${query.trim()}”.'
                        : '${records.length} highlight${records.length == 1 ? '' : 's'}, $notes with a note',
                    style: dimStyle(context),
                  ),
                ),
                for (final r in records) ...[_card(context, state, r, size), const SizedBox(height: 10)],
              ],
              if (showStudy) ...[
                if (scope == _Scope.all)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      'Study',
                      style: TextStyle(fontWeight: FontWeight.w600, color: p.accentText),
                    ),
                  ),
                StudyMarksList(
                  study: study,
                  query: query,
                  shrink: true,
                  onOpen: (h) => model.openStudyAt(h.book, run: h.run, page: h.page, y: h.y),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, AppState state, Highlight r, double size) {
    final p = ReaderColors.of(context);
    final item = state.passageOf(r.id);
    var place = item == null
        ? 'This passage is not in the current library.'
        : [
            bookOf(item) ?? (item.tags.isNotEmpty ? item.tags.first : null),
            heading(item),
          ].whereType<String>().join(' · ');
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(color: p.highlight(r.color), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
