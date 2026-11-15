import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/passage.dart';
import '../../core/marks/highlight.dart';
import '../reader/reader_screen.dart';

/// Saved passages, and highlights & notes. Entries made in another language open the matching passage of this one;
/// entries with no counterpart here are listed but cannot be opened.
class MarksScreen extends StatelessWidget {
  const MarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved & highlights'),
          bottom: TabBar(tabs: [
            Tab(text: 'Saved (${state.settings.saved.length})'),
            Tab(text: 'Highlights & notes (${state.highlights.length})'),
          ]),
        ),
        body: TabBarView(children: [_SavedList(), _HighlightList()]),
      ),
    );
  }
}

void _open(BuildContext context, Passage? p) {
  final state = AppScope.read(context);
  final place = p == null ? null : state.library!.workOf(p);
  if (place == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('This passage is not in the current language’s library.')));
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(work: place.$1, index: place.$2)));
}

String _where(AppState state, String id) {
  final l = languageOf(id);
  return l == state.settings.language ? '' : ' · saved in ${state.languageInfo(l).english}';
}

class _SavedList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final ids = state.settings.saved.reversed.toList();
    if (ids.isEmpty) return const Center(child: Text('No saved passages yet. Use the bookmark button while reading.'));
    return ListView.separated(
      itemCount: ids.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final id = ids[i];
        final p = state.passageOf(id);
        return ListTile(
          leading: const Icon(Icons.bookmark),
          title: Text(p?.title ?? id, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(p == null ? 'Not in this language' : '${p.citation}${_where(state, id)}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          enabled: p != null,
          onTap: () => _open(context, p),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: () => state.removeSaved(id),
          ),
        );
      },
    );
  }
}

class _HighlightList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final records = state.highlights.reversed.toList();
    if (records.isEmpty) return const Center(child: Text('No highlights yet. Select words while reading to highlight them.'));
    return ListView.separated(
      itemCount: records.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final h = records[i];
        final p = state.passageOf(h.id);
        final own = p != null && p.id == h.id;
        final placed = own && anchor(p.text, h) != null;
        final status = p == null
            ? 'Not in this language'
            : !own
                ? 'Shown on the matching passage${_where(state, h.id)}'
                : placed
                    ? p.title
                    : 'The text changed; kept but not drawn · ${p.title}';
        return ListTile(
          leading: Icon(Icons.format_color_fill, color: swatchColor(h.color)),
          title: Text('“${excerpt(h.words, 200)}”', maxLines: 3, overflow: TextOverflow.ellipsis),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (h.note != null) Text(h.note!, maxLines: 3, overflow: TextOverflow.ellipsis),
            Text('${h.created ?? ''}  $status', maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          isThreeLine: h.note != null,
          enabled: p != null,
          onTap: () => _open(context, p),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => state.removeHighlight(h),
          ),
        );
      },
    );
  }
}
