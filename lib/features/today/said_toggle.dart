import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/calendar/badi.dart';

/// "Said today" (or this morning, at noon, this evening) for the obligatory prayer being read: the same mark as on Today.
class SaidToggle extends StatelessWidget {
  const SaidToggle({super.key, required this.window});
  final Window window;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = ReaderColors.of(context);
    final said = state.settings.said.contains(window.key);
    final label = saidLabel(window);
    return TextButton(
      onPressed: () => window.prayer == 'long' ? state.markLong(!said) : state.markSaid(window.key, !said),
      style: TextButton.styleFrom(
        backgroundColor: said ? p.selection : p.foreground.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Text(said ? '✓ $label' : label),
    );
  }
}
