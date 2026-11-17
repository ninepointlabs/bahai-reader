import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../reader/reader_screen.dart';

/// A book's or a prayer category's contents on phones and tablets, before choosing a passage to read: its parts as
/// headings, each passage's opening words and length, and where reading left off (also offered at the top).
class ContentsScreen extends StatelessWidget {
  const ContentsScreen({super.key, required this.work});
  final Work work;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall;
    final last = state.settings.positions[work.title];
    final at = last == null ? -1 : work.passages.indexWhere((p) => p.id == last);
    final prayers = work.passages.isNotEmpty && work.passages.first.isPrayer;
    void open(int i) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(work: work, index: i)));

    final rows = <Widget>[
      if (at > 0)
        ListTile(
          leading: const Icon(Icons.play_arrow_rounded),
          title: const Text('Continue reading', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(listTitle(work.passages[at]), maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
          onTap: () => open(at),
        ),
    ];
    for (final (group, indexes) in contentsOf(work)) {
      if (group != null) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text(group, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ));
      } else if (rows.isNotEmpty) {
        rows.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
      for (final i in indexes) {
        final p = work.passages[i];
        final details = [
          wordLabel(p),
          if (prayers && p.author != null && p.author!.isNotEmpty) p.author!,
          if (i == at) 'last read',
        ];
        rows.add(ListTile(
          dense: !prayers,
          selected: i == at,
          title: Text(listTitle(p), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(details.join(' · '), style: dim),
          onTap: () => open(i),
        ));
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(work.title)),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: rows),
    );
  }
}
