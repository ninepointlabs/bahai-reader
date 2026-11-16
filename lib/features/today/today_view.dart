import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/calendar/today.dart';
import '../desktop/widgets.dart';

/// Today: the Badí‘ date, the sun, the obligatory prayer, the counter, the next Feast and Holy Day, the Fast and the
/// passage of the day, in one calm column (GTK `today.py`). Redrawn every 30 seconds, so "Open now" stays true.
class TodayView extends StatefulWidget {
  const TodayView({super.key, required this.onAction});
  final void Function(TodayRow row) onAction;

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = state.todayContext();
    if (c == null) return const SizedBox.shrink();
    final cards = todayContent(c);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final key in const ['date', 'sun', 'prayer', 'counter', 'events', 'fast', 'passage'])
              if (cards[key] case final rows?)
                Padding(padding: const EdgeInsets.only(bottom: 14), child: TodayCard(rows: rows, onAction: widget.onAction)),
          ]),
        ),
      ),
    );
  }
}

/// One card of Today or Home: its rows as labels, with neighbouring buttons sharing a line that wraps.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.rows, required this.onAction, this.tag, this.compact = false});
  final List<TodayRow> rows;
  final void Function(TodayRow row) onAction;

  /// A small capitalised label at the top (Home's cards), and titles shown the same way.
  final String? tag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = ReaderColors.of(context);
    final size = state.settings.textSize;
    final serif = TextStyle(fontFamily: readingFonts.first, fontFamilyFallback: readingFonts.sublist(1));
    final tagStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: p.accentText);
    final children = <Widget>[];
    if (tag != null) children.add(Text(tag!.toUpperCase(), style: tagStyle));
    List<Widget>? actions;
    for (final row in rows) {
      if (row.kind == RowKind.button || row.kind == RowKind.toggle) {
        if (actions == null) {
          actions = [];
          children.add(Padding(
            padding: const EdgeInsets.only(top: 6),
            // Home's narrow cards stack their buttons, each as wide as the card at most, so long labels wrap.
            child: compact
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: actions)
                : Wrap(spacing: 8, runSpacing: 8, children: actions),
          ));
        }
        actions.add(_action(context, row));
        continue;
      }
      actions = null;
      children.add(switch (row.kind) {
        RowKind.title => compact
            ? Text(row.text.toUpperCase(), style: tagStyle)
            : Text(row.text, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.accentText)),
        RowKind.large => Text(row.text, style: serif.copyWith(fontSize: size + 4, color: p.accentText)),
        RowKind.reading => Text(row.text,
            maxLines: compact ? 4 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: serif.copyWith(fontSize: (size - 4).clamp(15, 40))),
        RowKind.dim => Text(row.text, style: dimStyle(context, size: 13.5)),
        _ => Text(row.text),
      });
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.foreground.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 6), child: c)],
      ),
    );
  }

  Widget _action(BuildContext context, TodayRow row) {
    final p = ReaderColors.of(context);
    if (row.kind == RowKind.toggle) {
      return TextButton(
        onPressed: () => onAction(row),
        style: TextButton.styleFrom(
          backgroundColor: row.active ? p.selection : p.foreground.withValues(alpha: 0.07),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        child: Text(row.active ? '✓ ${row.text}' : row.text),
      );
    }
    return TextButton(
      onPressed: () => onAction(row),
      style: TextButton.styleFrom(
        backgroundColor: p.foreground.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(row.text, textAlign: TextAlign.left),
    );
  }
}
