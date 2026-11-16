import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../reader/reader_screen.dart';

/// A prayer category's contents on phones and tablets: each prayer's opening words and length, the one last read
/// marked, before choosing one to read. (The desktop's sidebar lists them the same way.)
class ContentsScreen extends StatelessWidget {
  const ContentsScreen({super.key, required this.work});
  final Work work;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final last = state.settings.positions[work.title];
    final dim = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text(work.title)),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: work.passages.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final p = work.passages[i];
          final details = [wordLabel(p), if (p.author case final a? when a.isNotEmpty) a, if (p.id == last) 'last read'];
          return ListTile(
            selected: p.id == last,
            title: Text(listTitle(p), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(details.join(' · '), style: dim),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => ReaderScreen(work: work, index: i)),
            ),
          );
        },
      ),
    );
  }
}
