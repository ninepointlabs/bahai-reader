import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/library/labels.dart';
import 'shell_model.dart';
import 'widgets.dart';

/// Prayers on the desktop, as on phones: the index of topics first (with the prayer last read and the Obligatory
/// prayers above it); a topic lists its prayers; a prayer opens to read.
class PrayersView extends StatelessWidget {
  const PrayersView({super.key, required this.model});
  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final library = state.library;
    if (library == null) return const SizedBox.shrink();
    final topic = model.topic;
    final children = <Widget>[];
    Widget title(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        );
    if (topic == null) {
      final last = model.lastPrayer;
      final place = last == null ? null : library.workOf(last);
      final top = [
        if (place != null)
          IndexEntry('Continue: ${listTitle(last!)}', place.$1.title, () => model.openIn(place.$1, place.$2),
              tooltip: 'The prayer last read'),
        if (library.obligatoryGroups.isNotEmpty)
          IndexEntry('Obligatory prayers', 'with the counter', () => model.navigate(Section.obligatory),
              tooltip: 'The three prayers, their guidance, and the Alláh-u-Abhá counter'),
      ];
      if (top.isNotEmpty) children.add(IndexCard(entries: top));
      children
        ..add(title('Topics'))
        ..add(IndexCard(entries: [
          for (final cat in library.prayerCategories)
            IndexEntry(cat.title, '${cat.passages.length}', () => model.showTopic(cat),
                tooltip: '${cat.passages.length} prayer${cat.passages.length == 1 ? '' : 's'}'),
        ]));
      if (library.prayerCategories.isEmpty) {
        children.add(Text('No prayers in this language’s library.', style: dimStyle(context, size: 14)));
      }
    } else {
      final lastId = state.settings.positions[topic.title];
      children
        ..add(Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => model.showTopic(null),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('All topics'),
          ),
        ))
        ..add(const SizedBox(height: 6))
        ..add(IndexCard(entries: [
          for (final (i, p) in topic.passages.indexed)
            IndexEntry(listTitle(p), wordLabel(p), () => model.openIn(topic, i),
                tooltip: [p.title, if (p.author case final a? when a.isNotEmpty) a].join(' — '),
                selected: p.id == lastId,
                lines: 2),
        ]));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}
