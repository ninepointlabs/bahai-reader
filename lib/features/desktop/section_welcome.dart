import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/labels.dart';
import 'shell_model.dart';
import 'widgets.dart';

/// A section's page on the desktop before anything in it is chosen: its index is the sidebar, so the page shows a
/// quiet title piece (a nine-pointed star), what the section holds, and a shortcut or two.
class SectionWelcome extends StatelessWidget {
  const SectionWelcome({super.key, required this.title, required this.lines, this.actions = const []});
  final String title;
  final List<String> lines;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    final serif = TextStyle(fontFamily: readingFonts.first, fontFamilyFallback: readingFonts.sublist(1));
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ExcludeSemantics(child: CustomPaint(size: const Size.square(150), painter: NineStar(p.accent))),
            const SizedBox(height: 28),
            Text(title, style: serif.copyWith(fontSize: 34, fontWeight: FontWeight.w700, color: p.accentText)),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, textAlign: TextAlign.center, style: dimStyle(context, size: 15)),
              ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: actions),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Prayers before a prayer is chosen: the topics are in the sidebar.
class PrayersView extends StatelessWidget {
  const PrayersView({super.key, required this.model});
  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    if (library == null) return const SizedBox.shrink();
    final cats = library.prayerCategories;
    final count = library.passages.where((x) => x.isPrayer).length;
    final last = model.lastPrayer;
    final place = last == null ? null : library.workOf(last);
    return SectionWelcome(
      title: 'Prayers',
      lines: cats.isEmpty
          ? ['No prayers in this language’s library.']
          : ['$count prayers in ${cats.length} topics', 'Choose a topic in the list to see its prayers.'],
      actions: [
        if (place != null)
          FilledButton.tonalIcon(
            onPressed: () => model.openIn(place.$1, place.$2),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text('Continue: ${listTitle(last!)}', overflow: TextOverflow.ellipsis),
          ),
        if (library.obligatoryGroups.isNotEmpty)
          OutlinedButton(onPressed: () => model.navigate(Section.obligatory), child: const Text('Obligatory prayers')),
      ],
    );
  }
}

/// Writings before a book is chosen: the books, under their authors, are in the sidebar.
class WritingsView extends StatelessWidget {
  const WritingsView({super.key, required this.model});
  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final library = state.library;
    if (library == null) return const SizedBox.shrink();
    final books = library.books;
    final authors = booksByAuthor(books).length;
    final shelf = {for (final w in books) w.title: w};
    final recent = [
      for (final t in state.settings.recent)
        if (shelf[t] case final w? when state.settings.positions[t] != null) w,
    ].firstOrNull;
    return SectionWelcome(
      title: 'Writings',
      lines: books.isEmpty
          ? ['No writings in this language’s library.']
          : [
              '${books.length} book${books.length == 1 ? '' : 's'} by $authors author${authors == 1 ? '' : 's'}',
              'Choose a book in the list to read it.',
            ],
      actions: [
        if (recent != null)
          FilledButton.tonalIcon(
            onPressed: () => model.openBook(recent),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text('Continue: ${recent.title}', overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

/// A nine-pointed star, drawn as two lines: the outline, and a fainter star turned within it.
class NineStar extends CustomPainter {
  const NineStar(this.color);
  final Color color;

  Path _star(Offset c, double outer, double inner, double turn) {
    final path = Path();
    for (var i = 0; i < 18; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + turn + i * math.pi / 9;
      final pt = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.85);
    canvas.drawPath(_star(c, r, r * 0.72, 0), Paint()..color = color.withValues(alpha: 0.08));
    canvas.drawPath(_star(c, r, r * 0.72, 0), line);
    canvas.drawPath(_star(c, r * 0.55, r * 0.40, math.pi / 9), line..color = color.withValues(alpha: 0.45));
    canvas.drawCircle(c, r * 0.12, Paint()..color = color.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(NineStar old) => old.color != color;
}
