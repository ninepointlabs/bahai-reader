import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import 'study_actions.dart';
import 'study_panels.dart';
import 'study_reader.dart';
import 'study_runs.dart';

/// A Study book on a phone: the pages full screen, with the panels (contents, highlights, bookmarks, answers, notes)
/// in a sheet, a bookmark button and the export in the menu. Leaving it closes the book.
class StudyBookScreen extends StatefulWidget {
  const StudyBookScreen({super.key});

  @override
  State<StudyBookScreen> createState() => _StudyBookScreenState();
}

class _StudyBookScreenState extends State<StudyBookScreen> {
  final reader = GlobalKey<StudyReaderState>();

  @override
  Widget build(BuildContext context) {
    final study = AppScope.of(context).study!;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) study.close();
      },
      child: ListenableBuilder(
        listenable: study,
        builder: (context, _) {
          final book = study.book;
          final bookmarked = study.bookmarkOn(study.page) != null;
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book?.name ?? 'Study', maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (study.run != null) Text(study.run!.name, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              actions: [
                RunMenuButton(study: study, showName: false),
                IconButton(
                  tooltip: 'Contents, highlights, bookmarks, answers and notes',
                  icon: const Icon(Icons.toc),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (sheet) => SizedBox(
                      height: MediaQuery.of(sheet).size.height * 0.7,
                      child: StudyPanels(study: study, onPicked: () => Navigator.pop(sheet)),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: bookmarked ? 'Remove the page’s bookmark' : 'Bookmark this page',
                  icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_outline),
                  onPressed: study.readOnly ? null : () => study.toggleBookmark(study.page),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => switch (v) {
                    'search' => reader.currentState?.openSearch(),
                    'page' => reader.currentState?.goToPageDialog(),
                    'note' => newBookNote(context, study),
                    _ => exportStudyRun(context, study),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'search', child: Text('Search in this book')),
                    PopupMenuItem(value: 'page', child: Text('Go to page…')),
                    PopupMenuItem(value: 'note', child: Text('New book note…')),
                    PopupMenuItem(value: 'export', child: Text('Export to Markdown…')),
                  ],
                ),
              ],
            ),
            body: StudyReader(
              key: reader,
              study: study,
              touch: true,
              onExport: () => exportStudyRun(context, study),
              onNewNote: () => newBookNote(context, study),
            ),
          );
        },
      ),
    );
  }
}
