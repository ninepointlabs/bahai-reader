import 'package:flutter/material.dart';

import '../../core/app/theme.dart';
import '../../core/study/study_controller.dart';
import '../../core/study/study_search.dart';
import '../../core/study/study_store.dart';
import 'study_actions.dart';
import 'study_panels.dart';

/// The one-line promise shown where books are imported.
const studyPrivacyLine =
    'Imported books are copied into the app on this device (and, if you sync through a folder, into that folder for '
    'your other devices). They are never uploaded anywhere else, and the app includes no Ruhi Institute material.';

const studyNotAffiliated = 'Bahá’í Reader is not affiliated with or endorsed by the Ruhi Institute.';

/// Study's library: the imported books, newest first, with their current run and marks; books taken out of it; and
/// the Import button.
class StudyLibraryView extends StatefulWidget {
  const StudyLibraryView({super.key, required this.study, this.onOpen});
  final StudyController? study;

  /// After a book is opened (a phone pushes the reader).
  final VoidCallback? onOpen;

  @override
  State<StudyLibraryView> createState() => _StudyLibraryViewState();
}

class _StudyLibraryViewState extends State<StudyLibraryView> {
  String filter = '';
  bool showRemoved = false;

  @override
  Widget build(BuildContext context) {
    final study = widget.study;
    final p = ReaderColors.of(context);
    if (study == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Study needs the app’s notes store, which could not be opened this time. Your highlights and notes are '
            'safe in the settings file; try closing and opening the app again.',
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: study,
      builder: (context, _) {
        final all = study.library;
        final removed = study.removed;
        final fold = study.fold ?? (String s) => s.toLowerCase();
        final q = fold(filter.trim());
        final cats = study.categories;
        final filterId = study.categoryFilter;
        final shown = [
          for (final b in all)
            if (_inCategory(study, b, filterId) &&
                (q.isEmpty ||
                    fold('${b.name} ${b.doc.fileName} ${study.categoriesOf(b).map((c) => c.name).join(' ')}')
                        .contains(q)))
              b,
        ];
        final hits = q.isEmpty ? const <MarkHit>[] : study.search(filter);
        Future<void> open(StudyBook b) async {
          await study.open(b);
          widget.onOpen?.call();
        }

        if (all.isEmpty && removed.isEmpty) return _empty(context, study);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search your books, highlights, notes and answers',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => filter = v),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<StudySort>(
                  tooltip: 'Sort',
                  initialValue: study.sort,
                  onSelected: study.setSort,
                  itemBuilder: (_) => [for (final (s, label) in _sorts) PopupMenuItem(value: s, child: Text(label))],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort, size: 20),
                        const SizedBox(width: 4),
                        Text(_sorts.firstWhere((e) => e.$1 == study.sort).$2),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('Import a PDF…'),
                  onPressed: () => importStudyPdf(context, study, opened: widget.onOpen),
                ),
              ],
            ),
            if (cats.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: filterId == null,
                    onSelected: (_) => study.setCategoryFilter(null),
                  ),
                  for (final c in cats)
                    ChoiceChip(
                      label: Text(c.name),
                      selected: filterId == c.id,
                      onSelected: (_) => study.setCategoryFilter(filterId == c.id ? null : c.id),
                    ),
                  ChoiceChip(
                    label: const Text('Uncategorized'),
                    selected: filterId == '',
                    onSelected: (_) => study.setCategoryFilter(filterId == '' ? null : ''),
                  ),
                  TextButton(onPressed: () => manageCategories(context, study), child: const Text('Manage…')),
                ],
              ),
            ],
            const SizedBox(height: 12),
            for (final b in shown) _BookRow(study: study, book: b, onOpen: () => open(b)),
            if (shown.isEmpty && all.isNotEmpty && hits.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  q.isEmpty ? 'No books in this category.' : 'Nothing matches “${filter.trim()}”.',
                  style: TextStyle(color: p.dim),
                ),
              ),
            if (hits.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  'Found in your marks (${hits.length})',
                  style: TextStyle(fontWeight: FontWeight.w600, color: p.accentText),
                ),
              ),
              for (final h in hits.take(100))
                ListTile(
                  dense: true,
                  leading: Icon(_kindIcon[h.kind], size: 18),
                  title: Text(h.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      if (h.detail.isNotEmpty) h.detail,
                      [h.book.name, h.run.name, if (h.page > 0) 'p. ${h.page}'].join(' · '),
                    ].join('\n'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    await study.openAt(h.book, run: h.run, page: h.page, y: h.y);
                    widget.onOpen?.call();
                  },
                ),
            ],
            if (removed.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                icon: Icon(showRemoved ? Icons.expand_more : Icons.chevron_right),
                label: Text('Removed (${removed.length})'),
                onPressed: () => setState(() => showRemoved = !showRemoved),
              ),
              if (showRemoved)
                for (final b in removed)
                  ListTile(
                    title: Text(b.name),
                    subtitle: Text(b.doc.fileName),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(onPressed: () => study.restore(b), child: const Text('Put back')),
                        TextButton(
                          onPressed: () => _deleteForever(context, study, b),
                          child: const Text('Delete for good…'),
                        ),
                      ],
                    ),
                  ),
            ],
            const SizedBox(height: 16),
            Text(studyPrivacyLine, style: TextStyle(color: p.dim, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(studyNotAffiliated, style: TextStyle(color: p.dim, fontSize: 12.5)),
          ],
        );
      },
    );
  }

  static const _sorts = [
    (StudySort.recent, 'Recent'),
    (StudySort.title, 'Title'),
    (StudySort.marked, 'Most marked'),
    (StudySort.added, 'Added'),
  ];

  static const _kindIcon = {
    'highlight': Icons.border_color_outlined,
    'answer': Icons.edit_note,
    'bookmark': Icons.bookmark_outline,
    'note': Icons.sticky_note_2_outlined,
  };

  static bool _inCategory(StudyController study, StudyBook b, String? id) {
    if (id == null) return true;
    final cs = study.categoriesOf(b);
    return id.isEmpty ? cs.isEmpty : cs.any((c) => c.id == id);
  }

  Widget _empty(BuildContext context, StudyController study) {
    final p = ReaderColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 48, color: p.dim),
              const SizedBox(height: 12),
              Text('Study', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'Import your own copies of Ruhi Institute books (or any workbook PDF) to highlight, take notes, '
                'bookmark pages and write your answers on the blank lines.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('Import a PDF…'),
                onPressed: () => importStudyPdf(context, study, opened: widget.onOpen),
              ),
              const SizedBox(height: 16),
              Text(
                studyPrivacyLine,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.dim, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              Text(
                studyNotAffiliated,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.dim, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteForever(BuildContext context, StudyController study, StudyBook b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete “${b.name}” for good?'),
        content: const Text(
          'Its highlights, notes, bookmarks and answers, from every time through, are deleted, and so is the app’s '
          'copy of the PDF. Your own PDF file is not touched.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await study.deleteForever(b);
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.study, required this.book, required this.onOpen});
  final StudyController study;
  final StudyBook book;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    final sub = [
      if (book.label.isNotEmpty) book.doc.fileName,
      if (book.doc.pageCount > 0) '${book.doc.pageCount} pages',
      for (final c in study.categoriesOf(book)) '#${c.name}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: p.card,
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined),
        title: Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [if (sub.isNotEmpty) sub, bookSummary(study.store, book)].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: sub.isNotEmpty,
        onTap: onOpen,
        trailing: PopupMenuButton<String>(
          tooltip: 'Rename or remove',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) async {
            switch (v) {
              case 'rename':
                final name = await askName(context, 'Name this book', book.label.isEmpty ? book.name : book.label);
                if (name != null) study.rename(book, name);
              case 'categories':
                await chooseCategories(context, study, book);
              case 'remove':
                await study.remove(book);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('“${book.name}” was taken out of Study. Its marks are kept under Removed.'),
                      action: SnackBarAction(label: 'Undo', onPressed: () => study.restore(book)),
                    ),
                  );
                }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename…')),
            PopupMenuItem(value: 'categories', child: Text('Categories…')),
            PopupMenuItem(value: 'remove', child: Text('Remove from Study')),
          ],
        ),
      ),
    );
  }
}

/// Files a book in categories: tick the ones it belongs to, or type a new one.
Future<void> chooseCategories(BuildContext context, StudyController study, StudyBook book) async {
  final chosen = {for (final c in study.categoriesOf(book)) c.id};
  final add = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setLocal) {
        final cats = study.categories;
        void create() {
          final name = add.text.trim();
          if (name.isEmpty) return;
          final c = study.addCategory(name);
          setLocal(() {
            chosen.add(c.id);
            add.clear();
          });
        }

        return AlertDialog(
          title: Text('Categories for “${book.name}”'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in cats)
                  CheckboxListTile(
                    dense: true,
                    title: Text(c.name),
                    value: chosen.contains(c.id),
                    onChanged: (v) => setLocal(() => v == true ? chosen.add(c.id) : chosen.remove(c.id)),
                  ),
                TextField(
                  controller: add,
                  autofocus: cats.isEmpty,
                  decoration: InputDecoration(
                    hintText: 'New category (e.g. Book 1, Tutor training)',
                    suffixIcon: IconButton(icon: const Icon(Icons.add), tooltip: 'Add', onPressed: create),
                  ),
                  onSubmitted: (_) => create(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (add.text.trim().isNotEmpty) create();
                study.setCategories(book, [
                  for (final c in study.categories)
                    if (chosen.contains(c.id)) c,
                ]);
                Navigator.pop(d);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  add.dispose();
}

/// Renames (onto an existing name merges the two) and deletes categories; deleting keeps the books.
Future<void> manageCategories(BuildContext context, StudyController study) => showDialog<void>(
  context: context,
  builder: (d) => ListenableBuilder(
    listenable: study,
    builder: (d, _) => AlertDialog(
      title: const Text('Categories'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (study.categories.isEmpty) const Text('No categories yet. Use a book’s ⋮ → Categories… to make one.'),
            for (final c in study.categories)
              ListTile(
                dense: true,
                title: Text(c.name),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Rename (onto another name merges them)',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () async {
                        final name = await askName(d, 'Rename category', c.name);
                        if (name != null) study.renameCategory(c, name);
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete (its books stay)',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => study.deleteCategory(c),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Done'))],
    ),
  ),
);
