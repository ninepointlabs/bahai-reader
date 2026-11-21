import 'package:flutter/material.dart';

import '../../core/app/theme.dart';
import '../../core/study/study_controller.dart';
import '../../core/study/study_store.dart';
import 'study_actions.dart';
import 'study_panels.dart';

/// The one-line promise shown where books are imported.
const studyPrivacyLine =
    'Imported books are copied into the app on this device. They are never uploaded or shared, and the app includes '
    'no Ruhi Institute material.';

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
        final books = study.library;
        final removed = study.removed;
        final q = filter.trim().toLowerCase();
        final shown = [
          for (final b in books)
            if (q.isEmpty || '${b.name} ${b.doc.fileName}'.toLowerCase().contains(q)) b,
        ];
        Future<void> open(StudyBook b) async {
          await study.open(b);
          widget.onOpen?.call();
        }

        if (books.isEmpty && removed.isEmpty) return _empty(context, study);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search your books',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => filter = v),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('Import a PDF…'),
                  onPressed: () => importStudyPdf(context, study, opened: widget.onOpen),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final b in shown) _BookRow(study: study, book: b, onOpen: () => open(b)),
            if (shown.isEmpty && books.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('No books match “${filter.trim()}”.', style: TextStyle(color: p.dim)),
              ),
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
            PopupMenuItem(value: 'remove', child: Text('Remove from Study')),
          ],
        ),
      ),
    );
  }
}
