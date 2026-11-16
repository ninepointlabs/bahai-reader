import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/labels.dart';
import 'shell_model.dart';
import 'widgets.dart';

/// Prayers on the desktop before a prayer is chosen: the topics are the sidebar's index, so the page itself shows a
/// quiet title piece (a nine-pointed star), how many prayers there are, and the prayer last read and the Obligatory
/// prayers as shortcuts.
class PrayersView extends StatelessWidget {
  const PrayersView({super.key, required this.model});
  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final library = state.library;
    if (library == null) return const SizedBox.shrink();
    final p = ReaderColors.of(context);
    final cats = library.prayerCategories;
    final count = library.passages.where((x) => x.isPrayer).length;
    final last = model.lastPrayer;
    final place = last == null ? null : library.workOf(last);
    final serif = TextStyle(fontFamily: readingFonts.first, fontFamilyFallback: readingFonts.sublist(1));
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ExcludeSemantics(
              child: CustomPaint(size: const Size.square(150), painter: NineStar(p.accent)),
            ),
            const SizedBox(height: 28),
            Text('Prayers', style: serif.copyWith(fontSize: 34, fontWeight: FontWeight.w700, color: p.accentText)),
            const SizedBox(height: 8),
            Text(
              cats.isEmpty ? 'No prayers in this language’s library.' : '$count prayers in ${cats.length} topics',
              style: dimStyle(context, size: 15),
            ),
            if (cats.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Choose a topic in the list to see its prayers.', style: dimStyle(context, size: 15)),
            ],
            const SizedBox(height: 28),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              if (place != null)
                FilledButton.tonalIcon(
                  onPressed: () => model.openIn(place.$1, place.$2),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text('Continue: ${listTitle(last!)}', overflow: TextOverflow.ellipsis),
                ),
              if (library.obligatoryGroups.isNotEmpty)
                OutlinedButton(
                  onPressed: () => model.navigate(Section.obligatory),
                  child: const Text('Obligatory prayers'),
                ),
            ]),
          ]),
        ),
      ),
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
