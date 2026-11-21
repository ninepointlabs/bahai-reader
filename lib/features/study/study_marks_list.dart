import 'package:flutter/material.dart';

import '../../core/app/theme.dart';
import '../../core/study/study_controller.dart';
import '../../core/study/study_search.dart';

/// Everything written in Study (highlights, answers, book notes), newest first, or what matches [query]; each opens its
/// book at its place, in its time through.
class StudyMarksList extends StatelessWidget {
  const StudyMarksList({
    super.key,
    required this.study,
    required this.query,
    required this.onOpen,
    this.shrink = false,
  });
  final StudyController study;
  final String query;
  final void Function(MarkHit hit) onOpen;

  /// Laid out inside another scrolling list.
  final bool shrink;

  static const icons = {
    'highlight': Icons.border_color_outlined,
    'answer': Icons.edit_note,
    'bookmark': Icons.bookmark_outline,
    'note': Icons.sticky_note_2_outlined,
  };

  static List<MarkHit> marks(StudyController study, String query) {
    final q = query.trim();
    final hits = q.isEmpty
        ? [
            for (final h in searchMarks(study.store, '', all: true))
              if (h.kind != 'bookmark') h,
          ]
        : study.search(q);
    hits.sort((a, b) => b.at.compareTo(a.at));
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    final hits = marks(study, query);
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          query.trim().isEmpty
              ? 'Nothing written in Study yet. Import a PDF of your own in Study to highlight it and write your answers.'
              : 'Nothing in Study matches “${query.trim()}”.',
          style: TextStyle(color: p.dim),
        ),
      );
    }
    final rows = [
      for (final h in hits.take(500))
        ListTile(
          leading: h.color == null
              ? Icon(icons[h.kind], size: 20)
              : Container(width: 4, height: 36, color: p.swatch(h.color!)),
          title: Text(h.text, maxLines: 4, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (h.detail.isNotEmpty) h.detail,
              [h.book.name, h.run.name, if (h.page > 0) 'p. ${h.page}'].join(' · '),
            ].join('\n'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onOpen(h),
        ),
    ];
    return shrink ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows) : ListView(children: rows);
  }
}
