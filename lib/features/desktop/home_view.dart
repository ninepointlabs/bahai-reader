import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/calendar/today.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import 'shell_model.dart';
import 'today_view.dart';
import 'widgets.dart';

/// Home: Continue reading (the books read most recently) and the library. With [libraryOnly], the Writings page: the
/// library alone. As the GTK app's Home, without its Today cards (not part of this experiment).
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.model, this.libraryOnly = false, this.onAction});
  final ShellModel model;
  final bool libraryOnly;

  /// Carries out a Today card's button (Home shows the date, the obligatory prayer and the passage of the day).
  final void Function(TodayRow row)? onAction;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final library = state.library;
    if (library == null) return const SizedBox.shrink();
    final children = <Widget>[];
    final c = libraryOnly ? null : state.todayContext();
    if (c != null && onAction != null) {
      final today = homeCards(c);
      children.add(LayoutBuilder(builder: (context, box) {
        final cards = [
          for (final (_, tag, rows) in today) TodayCard(rows: rows, tag: tag, onAction: onAction!, compact: true),
        ];
        if (box.maxWidth < 600) {
          return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: cards[i])],
        ]);
      }));
    }
    if (!libraryOnly) {
      final cards = _continueCards(context, state, library);
      if (cards.isNotEmpty) {
        children
          ..add(const _Title('Continue reading', size: 15, top: 0))
          ..add(LayoutBuilder(builder: (context, box) {
            final narrow = box.maxWidth < 600;
            if (narrow) return Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)]);
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: i < cards.length ? cards[i] : const SizedBox()),
                ],
              ]),
            );
          }));
      }
      children.add(const _Title('Library', size: 18, top: 16, weight: FontWeight.w800));
    }
    final authors = <String, List<Work>>{};
    for (final w in library.books) {
      authors.putIfAbsent(authorOf(w), () => []).add(w);
    }
    final order = authors.keys.toList()
      ..sort((a, b) {
        final (ra, na) = authorRank(a);
        final (rb, nb) = authorRank(b);
        return ra != rb ? ra.compareTo(rb) : na.compareTo(nb);
      });
    for (final author in order) {
      children
        ..add(_Title(author, size: 15, top: 10))
        ..add(LayoutBuilder(builder: (context, box) {
          final columns = (box.maxWidth / 270).floor().clamp(1, 4);
          final width = (box.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final w in authors[author]!) SizedBox(width: width, child: _BookCard(work: w, author: author, model: model)),
          ]);
        }));
    }
    if (library.books.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('No writings in this language’s library.', style: dimStyle(context, size: 14)),
      ));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, libraryOnly ? 16 : 20, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }

  List<Widget> _continueCards(BuildContext context, AppState state, Library library) {
    final shelf = {for (final w in library.books) w.title: w};
    final cards = <Widget>[];
    for (final title in state.settings.recent) {
      final work = shelf[title];
      final id = state.settings.positions[title];
      if (work == null || id == null) continue;
      final i = work.passages.indexWhere((p) => p.id == id);
      if (i < 0) continue;
      final item = work.passages[i];
      final (before, total) = bookProgress(work.passages, item);
      final fraction = total == 0 ? 0.0 : before / total;
      cards.add(CardButton(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        onTap: () => model.openBook(work, at: i),
        tooltip: 'Continue ${work.title}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(work.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: dimStyle(context)),
          const SizedBox(height: 4),
          Text(heading(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Bar(value: fraction),
          const SizedBox(height: 4),
          Text('${(100 * fraction).round()}% of the book', style: dimStyle(context)),
        ]),
      ));
      if (cards.length >= 3) break;
    }
    return cards;
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {required this.size, required this.top, this.weight = FontWeight.w700});
  final String text;
  final double size;
  final double top;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top + 12, bottom: 10),
        child: Text(text, style: TextStyle(fontSize: size, fontWeight: weight)),
      );
}

/// A book in the library: a gold spine, the title in the reading face, its parts and length.
class _BookCard extends StatelessWidget {
  const _BookCard({required this.work, required this.author, required this.model});
  final Work work;
  final String author;
  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    return CardButton(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
      tooltip: '${work.title}, $author',
      onTap: () => model.openBook(work),
      child: SizedBox(
        height: 98,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 4,
            decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(
                  work.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: readingFonts.first,
                    fontFamilyFallback: readingFonts.sublist(1),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              Text(work.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: dimStyle(context)),
            ]),
          ),
        ]),
      ),
    );
  }
}
