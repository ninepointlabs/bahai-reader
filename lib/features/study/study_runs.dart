import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/study/study_controller.dart';
import '../../core/study/study_store.dart';
import 'study_actions.dart';
import 'study_panels.dart' show askName;

String _date(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// "Started 3 Mar 2025 · finished 20 Nov 2026".
String runDates(StudyRun r) => [
  if (r.startedAt != null) 'started ${_date(r.startedAt)}',
  if (r.finishedAt != null) 'finished ${_date(r.finishedAt)}',
].join(' · ');

/// Asks for the new run's name (prefilled "2nd time, Nov 2026") and starts it: empty, with the current run finished
/// and locked.
Future<void> startNewRunDialog(BuildContext context, StudyController study) async {
  final book = study.book;
  if (book == null) return;
  final next = study.runs.map((r) => r.ordinal).fold(0, (a, b) => a > b ? a : b) + 1;
  final name = TextEditingController(text: runName(next, DateTime.now()));
  final current = study.store.currentRun(book);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Start a new time through'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The new time through starts with no highlights, notes, bookmarks or answers. '
              '“${current.name}” is kept as it is, finished and locked; you can still read it, show it beside the new '
              'one, and unlock it if you need to change something.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => Navigator.pop(d, true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Start')),
      ],
    ),
  );
  if (ok == true) study.startNewRun(name: name.text);
  name.dispose();
}

Future<void> renameRunDialog(BuildContext context, StudyController study, StudyRun run) async {
  final name = await askName(context, 'Name this time through', run.name);
  if (name != null && name.trim().isNotEmpty) study.renameRun(run, name);
}

Future<void> deleteRunDialog(BuildContext context, StudyController study, StudyRun run) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('Delete “${run.name}”?'),
      content: const Text(
        'Its highlights, notes, bookmarks and answers are deleted. Other times through are not touched.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok == true) study.deleteRun(run);
}

/// The times through a book: switch to one, start a new one, name, compare, delete, export them all.
class RunMenuButton extends StatelessWidget {
  const RunMenuButton({super.key, required this.study, this.showName = true});
  final StudyController study;

  /// Desktop header: the run's name on the button; phones: an icon.
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final shown = study.run;
    final book = study.book;
    if (shown == null || book == null) return const SizedBox.shrink();
    final current = study.store.currentRun(book);
    final runs = study.runs;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Times through this book (Ctrl+Shift+N starts a new one)',
      position: PopupMenuPosition.under,
      onSelected: (f) => f(),
      itemBuilder: (_) => [
        for (final r in runs.reversed)
          PopupMenuItem(
            value: () => study.viewRun(r),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                r.id == shown.id ? Icons.check : (study.store.editable(r) ? Icons.edit_outlined : Icons.lock_outline),
                size: 18,
              ),
              title: Text(r.id == current.id ? '${r.name} (current)' : r.name),
              subtitle: Text(runDates(r)),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(value: () => startNewRunDialog(context, study), child: const Text('Start a new time through…')),
        PopupMenuItem(value: () => renameRunDialog(context, study, shown), child: Text('Rename “${shown.name}”…')),
        if (runs.length > 1) ...[
          for (final r in runs.reversed)
            if (r.id != shown.id)
              PopupMenuItem(
                value: () => study.setCompare(study.compare?.id == r.id ? null : r),
                child: Text(study.compare?.id == r.id ? 'Stop comparing with “${r.name}”' : 'Compare with “${r.name}”'),
              ),
          PopupMenuItem(value: () => exportAllRuns(context, study), child: const Text('Export all times through…')),
        ],
        if (shown.id != current.id)
          PopupMenuItem(value: () => deleteRunDialog(context, study, shown), child: Text('Delete “${shown.name}”…')),
        if (Platform.isLinux)
          PopupMenuItem(
            value: () => offerDogear(context, study, book, asked: true),
            child: const Text('Bring in Dogear marks…'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(study.readOnly ? Icons.lock_outline : Icons.history, size: 18),
            if (showName) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(shown.name, overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// One question's answers in every time through, oldest first, with a way to bring an earlier answer into this run.
Future<void> showAnswerHistory(BuildContext context, StudyController study, String slotKey) {
  final rows = study.history(slotKey);
  final shown = study.run;
  final context0 = rows.map((e) => e.$2.context).firstWhere((c) => c.isNotEmpty, orElse: () => '');
  return showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('This answer, each time through'),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (context0.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(context0, style: Theme.of(d).textTheme.bodySmall),
              ),
            for (final (run, a) in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(run.id == shown?.id ? '${run.name} (on show)' : run.name),
                subtitle: Text(a.text),
                trailing: run.id == shown?.id || study.readOnly
                    ? null
                    : TextButton(
                        onPressed: () {
                          study.store.putAnswer(
                            shown!.id,
                            study.book!.docId,
                            a.place,
                            a.text,
                            context: a.context,
                            ordinal: int.tryParse(a.slotKey.split('#').last) ?? 0,
                          );
                          study.viewRun(shown);
                          Navigator.pop(d);
                        },
                        child: const Text('Use in this run'),
                      ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
    ),
  );
}

/// Marks brought from another edition that could not be found in this one: copy a highlight's words to mark them
/// again, place an answer on its line, or bookmark the page on show instead; or let them go.
Future<void> showUnplaced(BuildContext context, StudyController study) => showDialog<void>(
  context: context,
  builder: (d) => ListenableBuilder(
    listenable: study,
    builder: (d, _) {
      final u = study.unplaced;
      return AlertDialog(
        title: const Text('Not placed yet'),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'These were not found in this edition. Highlight the words again where they are now, place each answer '
                'on its line, or remove what you no longer need.',
              ),
              const SizedBox(height: 8),
              for (final h in u.highlights)
                ListTile(
                  leading: const Icon(Icons.border_color_outlined),
                  title: Text(h.quote, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text([if (h.note != null) h.note!, 'was on p. ${h.page}'].join(' · ')),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Copy the words',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => Clipboard.setData(ClipboardData(text: h.quote)),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => study.dropUnplaced('doc_highlight', h.id),
                      ),
                    ],
                  ),
                ),
              for (final a in u.answers)
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text(a.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text([if (a.context.isNotEmpty) a.context, 'was on p. ${a.page}'].join(' · ')),
                  trailing: Wrap(
                    children: [
                      TextButton(
                        onPressed: study.readOnly
                            ? null
                            : () {
                                study.startPlacing(a);
                                Navigator.pop(d);
                              },
                        child: const Text('Place…'),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => study.dropUnplaced('answer', a.id),
                      ),
                    ],
                  ),
                ),
              for (final m in u.bookmarks)
                ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(m.name.isEmpty ? 'Page ${m.page}' : m.name),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => study.dropUnplaced('doc_bookmark', m.id),
                  ),
                ),
              if (u.highlights.isEmpty && u.answers.isEmpty && u.bookmarks.isEmpty) const Text('Everything is placed.'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
      );
    },
  ),
);
