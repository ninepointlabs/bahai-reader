/// Searching what was written in Study: highlights (their words and notes), answers (and their questions), bookmark
/// names and book notes, in every book and every time through. Matching ignores case, accents, apostrophes and hyphens
/// when given the app's [fold] (as the texts' search does).
library;

import 'study_store.dart';

class MarkHit {
  const MarkHit({
    required this.book,
    required this.run,
    required this.kind,
    required this.text,
    required this.page,
    this.y = 0,
    this.detail = '',
    this.at = 0,
    this.color,
  });

  /// When it was made (Unix ms), for newest-first lists.
  final int at;

  /// A highlight's colour.
  final String? color;
  final StudyBook book;
  final StudyRun run;

  /// `highlight`, `answer`, `bookmark` or `note` (a book note).
  final String kind;

  /// What was written (a highlight's words, an answer, a bookmark's name, a note).
  final String text;

  /// A highlight's note or an answer's question.
  final String detail;
  final int page;
  final double y;
}

String _plain(String s) => s.toLowerCase();

/// Every mark whose text (or note, or question) contains [query]; in library order, then page order. With [all], every
/// mark (bookmarks too), whatever the query.
List<MarkHit> searchMarks(StudyStore store, String query, {String Function(String)? fold, bool all = false}) {
  final f = fold ?? _plain;
  final q = f(query.trim());
  if (q.isEmpty && !all) return const [];
  bool has(String? s) => all || (s != null && s.isNotEmpty && f(s).contains(q));
  final out = <MarkHit>[];
  for (final b in store.books) {
    for (final r in store.runsOf(b)) {
      for (final h in store.highlights(r.id)) {
        if (has(h.quote) || has(h.note)) {
          out.add(
            MarkHit(
              book: b,
              run: r,
              kind: 'highlight',
              text: h.quote,
              detail: h.note ?? '',
              page: h.page,
              y: h.order.$2,
              at: h.createdAt,
              color: h.color,
            ),
          );
        }
      }
      for (final a in store.answers(r.id)) {
        if (has(a.text) || has(a.context)) {
          out.add(
            MarkHit(
              book: b,
              run: r,
              kind: 'answer',
              text: a.text,
              detail: a.context,
              page: a.page,
              y: a.place.y,
              at: a.createdAt,
            ),
          );
        }
      }
      for (final m in store.bookmarks(r.id)) {
        if (has(m.name)) out.add(MarkHit(book: b, run: r, kind: 'bookmark', text: m.name, page: m.page, y: m.y));
      }
      for (final n in store.notes(r.id)) {
        if (has(n.text)) out.add(MarkHit(book: b, run: r, kind: 'note', text: n.text, page: 0, at: n.createdAt));
      }
    }
  }
  return out;
}

/// Library order: how the Study library can be sorted.
enum StudySort { recent, title, marked, added }

/// The books in [order]; Recent is the last read first, Most marked counts every time through.
List<StudyBook> sortBooks(StudyStore store, List<StudyBook> books, StudySort order) {
  final list = [...books];
  switch (order) {
    case StudySort.recent:
      final at = {for (final b in list) b.id: store.lastRead(b)};
      list.sort((a, b) => at[b.id]!.compareTo(at[a.id]!));
    case StudySort.title:
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case StudySort.marked:
      final n = {for (final b in list) b.id: store.markCount(b)};
      list.sort((a, b) => n[b.id]!.compareTo(n[a.id]!));
    case StudySort.added:
      list.sort((a, b) => b.sort.compareTo(a.sort));
  }
  return list;
}
