import 'package:flutter/material.dart';

import '../../core/app/theme.dart';
import '../../core/study/study_controller.dart';
import '../../core/study/study_store.dart';
import '../marks/highlight_sheet.dart' show editNote;

/// The open book's panels: its contents, and the run's highlights, bookmarks, answers and book notes. In the desktop
/// sidebar, and in a sheet on phones.
class StudyPanels extends StatelessWidget {
  const StudyPanels({super.key, required this.study, this.onPicked});
  final StudyController study;

  /// After jumping to something (a phone closes its sheet).
  final VoidCallback? onPicked;

  static const labels = {
    StudyPanel.contents: ('Contents', Icons.toc),
    StudyPanel.highlights: ('Highlights', Icons.border_color_outlined),
    StudyPanel.bookmarks: ('Bookmarks', Icons.bookmark_outline),
    StudyPanel.answers: ('Answers', Icons.edit_note),
    StudyPanel.notes: ('Notes', Icons.sticky_note_2_outlined),
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: study,
    builder: (context, _) {
      // Its own transparent Material, so the rows show their hover and ink over the sidebar's colour.
      return Material(type: MaterialType.transparency, child: _panels(context));
    },
  );

  Widget _panels(BuildContext context) {
    {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final (i, MapEntry(key: panel, value: (label, icon))) in labels.entries.indexed)
                  Tooltip(
                    message: '$label (Ctrl+${i + 1})',
                    child: ChoiceChip(
                      avatar: Icon(icon, size: 16),
                      label: Text(label),
                      selected: study.panel == panel,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => study.setPanel(panel),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _list(context)),
        ],
      );
    }
  }

  void _go(int page, [double y = 0]) {
    study.goTo?.call(page, y: y);
    onPicked?.call();
  }

  Widget _empty(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(text, style: TextStyle(color: ReaderColors.of(context).dim)),
  );

  Widget _list(BuildContext context) {
    final p = ReaderColors.of(context);
    final locked = study.readOnly;
    switch (study.panel) {
      case StudyPanel.contents:
        final entries = study.outline;
        if (entries.isEmpty) return _empty(context, 'This PDF has no table of contents.');
        return ListView(
          children: [
            for (final e in entries)
              ListTile(
                dense: true,
                selected: e.page == study.page,
                contentPadding: EdgeInsets.only(left: 12.0 + e.depth * 14, right: 12),
                title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text('${e.page}', style: TextStyle(color: p.dim, fontSize: 12)),
                onTap: () => _go(e.page),
              ),
          ],
        );
      case StudyPanel.highlights:
        final hs = study.highlights;
        if (hs.isEmpty) return _empty(context, 'Select words on the page and pick a colour to highlight them.');
        return ListView(
          children: [
            for (final h in hs)
              ListTile(
                dense: true,
                leading: Container(width: 4, height: 32, color: p.swatch(h.color)),
                title: Text(h.quote, maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [if (h.note != null) h.note!, 'p. ${h.page}'].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _go(h.page, h.order.$2),
                trailing: locked
                    ? null
                    : IconButton(
                        tooltip: h.note == null ? 'Add a note' : 'Edit the note',
                        icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                        onPressed: () async {
                          final text = await editNote(context, h.note);
                          if (text != null) study.setNote(h, text);
                        },
                      ),
              ),
          ],
        );
      case StudyPanel.bookmarks:
        final bs = study.bookmarks;
        if (bs.isEmpty) return _empty(context, 'Press b (or Ctrl+D) to bookmark the page you are on.');
        return ListView(
          children: [
            for (final b in bs)
              ListTile(
                dense: true,
                leading: const Icon(Icons.bookmark, size: 18),
                title: Text(b.name.isEmpty ? 'Page ${b.page}' : b.name),
                subtitle: Text('p. ${b.page}'),
                onTap: () => _go(b.page, b.y),
                trailing: locked
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Rename or remove',
                        icon: const Icon(Icons.more_vert, size: 18),
                        onSelected: (v) async {
                          if (v == 'remove') return study.removeBookmark(b);
                          final name = await _ask(context, 'Rename bookmark', b.name);
                          if (name != null && name.trim().isNotEmpty) study.renameBookmark(b, name);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename…')),
                          PopupMenuItem(value: 'remove', child: Text('Remove')),
                        ],
                      ),
              ),
          ],
        );
      case StudyPanel.answers:
        final as = study.answers;
        if (as.isEmpty) {
          return _empty(
            context,
            'Click a blank line on the page and type. Long-press (or right-click) an empty space to write there.',
          );
        }
        return ListView(
          children: [
            for (final a in as)
              ListTile(
                dense: true,
                title: Text(
                  a.context.isEmpty ? 'p. ${a.page}' : a.context,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(a.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                onTap: () => _go(a.page, a.place.y),
              ),
          ],
        );
      case StudyPanel.notes:
        final ns = study.notes;
        return ListView(
          children: [
            if (!locked)
              ListTile(
                dense: true,
                leading: const Icon(Icons.add),
                title: const Text('New note (Ctrl+N)'),
                onTap: () => newBookNote(context, study),
              ),
            if (ns.isEmpty) _empty(context, 'Notes about the whole book, for this time through it.'),
            for (final n in ns)
              ListTile(
                dense: true,
                title: Text(n.text, maxLines: 6, overflow: TextOverflow.ellipsis),
                onTap: locked
                    ? null
                    : () async {
                        final text = await editNote(context, n.text);
                        if (text != null) study.updateNote(n, text);
                      },
                trailing: locked
                    ? null
                    : IconButton(
                        tooltip: 'Delete the note',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => study.removeNote(n),
                      ),
              ),
          ],
        );
    }
  }
}

Future<void> newBookNote(BuildContext context, StudyController study) async {
  if (study.readOnly || study.book == null) return;
  final text = await editNote(context, null);
  if (text != null && text.trim().isNotEmpty) {
    study.addNote(text);
    study.setPanel(StudyPanel.notes);
  }
}

Future<String?> _ask(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
      ],
    ),
  ).whenComplete(c.dispose);
}

/// Asks for a name; null if cancelled.
Future<String?> askName(BuildContext context, String title, String initial) => _ask(context, title, initial);

/// The run's counts in a few words: "12 highlights · 3 answers".
String marksSummary(({int highlights, int notes, int answers, int bookmarks}) c) {
  String n(int v, String one) => '$v $one${v == 1 ? '' : 's'}';
  final parts = [
    if (c.highlights > 0) n(c.highlights, 'highlight'),
    if (c.notes > 0) n(c.notes, 'note'),
    if (c.answers > 0) n(c.answers, 'answer'),
    if (c.bookmarks > 0) n(c.bookmarks, 'bookmark'),
  ];
  return parts.isEmpty ? 'No marks yet' : parts.join(' · ');
}

/// For the library: the book's current run and its marks.
String bookSummary(StudyStore store, StudyBook b) {
  final run = store.currentRun(b);
  return '${run.name} · ${marksSummary(store.counts(run.id))}';
}
