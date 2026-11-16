import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';

/// Offers to allow reminders at the minute ("Alarms & reminders", Android 12 and later) when reminders are on but may
/// arrive up to an hour late. With [atStart], only once ever, so it doesn't ask at every start.
Future<void> offerExactTimes(BuildContext context, {bool atStart = false}) async {
  final state = AppScope.read(context);
  if (!state.remindersMayBeLate || (atStart && state.settings.askedExactTimes)) return;
  if (atStart) await state.markAskedExactTimes();
  if (!context.mounted) return;
  final allow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reminders on time'),
      content: const Text(
        'Android may hold reminders back by up to an hour, so one before a prayer’s time closes could come too late. '
        'Allow “Alarms & reminders” for this app and they arrive at the minute.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open settings')),
      ],
    ),
  );
  if (allow == true) await state.notifier.requestExactTimes();
}
