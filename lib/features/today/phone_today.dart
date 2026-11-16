import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/calendar/badi.dart';
import '../../core/calendar/today.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../../core/library/passage.dart';
import '../reader/reader_screen.dart';
import 'counter_view.dart';
import 'location_dialog.dart';

/// Today and the obligatory prayers in the phone layout: the same cards and settings as the desktop's, opened as pages.

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// The Obligatory prayers group holding [p], so Next and Previous stay among them (else its own book).
(Work, int)? obligatoryPlace(Library library, Passage p) {
  for (final g in library.obligatoryGroups) {
    final i = g.passages.indexWhere((x) => x.id == p.id);
    if (i >= 0) return (g, i);
  }
  return library.workOf(p);
}

/// Opens the chosen obligatory prayer (`short`, `medium`, `long`), e.g. from a reminder.
void openObligatoryPrayer(BuildContext context, String name) {
  final state = AppScope.read(context);
  final item = prayerNames.containsKey(name) ? state.todayContext()?.prayerItem(name) : null;
  final place = item == null ? null : obligatoryPlace(state.library!, item);
  if (place != null) _push(context, ReaderScreen(work: place.$1, index: place.$2));
}

/// Carries out a button on a Today card. [showToday] brings the Today tab forward.
void actOnPhone(BuildContext context, TodayRow row, {required VoidCallback showToday}) {
  final state = AppScope.read(context);
  final library = state.library;
  if (library == null) return;
  switch (row.action) {
    case OpenToday():
      showToday();
    case OpenLocation():
      showLocationPage(context);
    case OpenCounter():
      _push(context, const CounterScreen());
    case OpenObligatory(:final passage):
      if (obligatoryPlace(library, passage) case final place?) _push(context, ReaderScreen(work: place.$1, index: place.$2));
    case OpenPassage(:final passage):
      if (library.workOf(passage) case final place?) _push(context, ReaderScreen(work: place.$1, index: place.$2));
    case OpenGroup(:final passages, :final label):
      _push(context, ReaderScreen(work: Work(title: label, kind: passages.first.isPrayer ? 'prayers' : 'readings', passages: passages)));
    case MarkSaid(:final key, :final long):
      long ? state.markLong(!row.active) : state.markSaid(key, !row.active);
    case MarkFasted(:final key):
      state.markFasted(key, !row.active);
    case null:
      break;
  }
}

/// The Alláh-u-Abhá counter as a page.
class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Alláh-u-Abhá counter')),
        body: CounterView(onBack: () => Navigator.of(context).maybePop()),
      );
}

/// The Obligatory prayers section: the counter, the three prayers and the Kitáb-i-Aqdas guidance on them.
class ObligatoryScreen extends StatelessWidget {
  const ObligatoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final groups = state.library?.obligatoryGroups ?? const <Work>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Obligatory prayers')),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        ListTile(
          leading: const Icon(Icons.exposure_plus_1),
          title: const Text('Alláh-u-Abhá counter'),
          onTap: () => _push(context, const CounterScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.place_outlined),
          title: const Text('Location & reminders'),
          subtitle: Text(state.settings.prayer == null ? 'Choose which prayer you say' : 'Your prayer, its times and reminders'),
          onTap: () => showLocationPage(context),
        ),
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(g.title, style: Theme.of(context).textTheme.titleSmall),
          ),
          for (var i = 0; i < g.passages.length; i++)
            ListTile(
              dense: true,
              title: Text(listTitle(g.passages[i]), maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => _push(context, ReaderScreen(work: g, index: i)),
            ),
        ],
      ]),
    );
  }
}
