import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../settings/collections_dialog.dart';
import '../../core/app/theme.dart';
import '../../core/calendar/badi.dart' show unpublished;
import '../../core/calendar/today.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../../core/library/passage.dart';
import '../study/study_actions.dart';
import '../study/study_panels.dart';
import 'shell_model.dart';
import 'widgets.dart';

/// The sidebar: Home, Prayers, Writings and Saved, then the open section's contents with its own search.
/// When a book is open the sections give way to the book's title and a Back button, as in the GTK app.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.model, required this.onSearch, required this.onAction});
  final ShellModel model;
  final VoidCallback onSearch;

  /// Carries out a Today calendar row's action (its readings or prayers).
  final void Function(TodayRow row) onAction;

  static const rows = [
    (Section.home, 'Home', Icons.home_outlined),
    (Section.prayers, 'Prayers', Icons.local_florist_outlined),
    (Section.writings, 'Writings', Icons.menu_book_outlined),
    (Section.study, 'Study', Icons.school_outlined),
    (Section.saved, 'Saved', Icons.star_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = ReaderColors.of(context);
    final book = model.inBook ? model.book : null;
    final inBook = model.inBook;
    final library = state.library;
    final obligatory = Work(
        title: 'Obligatory prayers',
        kind: 'obligatory',
        passages: [for (final g in library?.obligatoryGroups ?? const <Work>[]) ...g.passages]);
    final counts = {
      Section.prayers: library == null ? '' : '${library.passages.where((x) => x.isPrayer).length}',
      Section.writings: library == null ? '' : '${library.books.length} books',
      Section.saved: state.settings.saved.isEmpty ? '' : '${state.settings.saved.length}',
      Section.study: (state.study?.library.length ?? 0) == 0 ? '' : '${state.study!.library.length}',
    };
    final studyBook = model.section == Section.study && inBook ? state.study?.book : null;
    final showContents = model.section != Section.home;
    final nav = navOf(model.section);
    return ColoredBox(
      color: p.sidebar,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HeaderBar(
          color: p.sidebar,
          start: [
            if (inBook) HeaderButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: 'Back', onPressed: model.leaveBook),
          ],
          title: studyBook != null
              ? WindowTitle(title: studyBook.name, subtitle: state.study?.run?.name ?? '')
              : book != null
              ? WindowTitle(title: book.title, subtitle: '${authorOf(book)} · ${book.summary}')
              : inBook
                  ? WindowTitle(title: 'Obligatory prayers', subtitle: obligatory.summary)
                  : const WindowTitle(title: 'Bahá’í Reader'),
          end: [HeaderButton(icon: Icons.search, tooltip: 'Search the texts (Ctrl+K)', onPressed: onSearch)],
        ),
        if (!inBook)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Column(children: [
              for (final (section, label, icon) in rows)
                SideRow(
                  selected: nav == section,
                  onTap: () => model.navigate(section),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(children: [
                    Icon(icon, size: 19),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
                    if (counts[section] case final c? when c.isNotEmpty) Text(c, style: dimStyle(context)),
                  ]),
                ),
            ]),
          ),
        if (model.section == Section.study)
          Expanded(child: _StudySide(model: model))
        else if (showContents)
          Expanded(child: _Contents(model: model, onAction: onAction)),
      ]),
    );
  }
}

/// The open section's contents: a search field, how many passages match, and the tree of groups and passages.
class _Contents extends StatefulWidget {
  const _Contents({required this.model, required this.onAction});
  final ShellModel model;
  final void Function(TodayRow row) onAction;

  @override
  State<_Contents> createState() => _ContentsState();
}

class _ContentsState extends State<_Contents> {
  final search = TextEditingController();
  final currentKey = GlobalKey();
  final scroll = ScrollController();

  /// Groups the reader opened or closed by hand: {path: expanded}, kept in the settings (GTK `expanded`). Otherwise a
  /// group is open when it holds the passage on show (or while searching).
  Map<String, bool> get expanded => AppScope.read(context).settings.expanded;

  /// Groups closed by hand while the passage on show is in them: they stay closed until another passage is shown.
  final Set<String> _closedHere = {};
  String? _closedFor;

  void _toggle(String path, bool open) => setState(() {
        AppScope.read(context).setExpanded(path, !open);
        open ? _closedHere.add(path) : _closedHere.remove(path);
      });
  static final Map<String, String> _folded = {};
  String? _scrolledTo;

  ShellModel get model => widget.model;

  @override
  void initState() {
    super.initState();
    search.text = model.filter;
  }

  @override
  void didUpdateWidget(covariant _Contents old) {
    super.didUpdateWidget(old);
    if (search.text != model.filter) search.text = model.filter;
  }

  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool matches(AppState state, Passage p, String q) {
    if (q.isEmpty) return true;
    final f = state.folder;
    if (f == null) return true;
    final folded = _folded.putIfAbsent(p.id, () => f.fold('${p.title} ${p.text} ${p.tags.join(' ')}'));
    return folded.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final library = state.library;
    final q = state.folder?.fold(model.filter.trim()) ?? '';
    final current = model.current;
    if (current?.id != _closedFor) {
      _closedFor = current?.id;
      _closedHere.clear();
    }
    final rows = <Widget>[];
    // Passages that match, counted once even when listed under two categories.
    final shownIds = <String>{};
    final shelf = model.section == Section.writings && model.book == null; // the list of books, under their authors
    final unit = shelf
        ? 'book'
        : model.section == Section.prayers
            ? 'prayer'
            : model.section == Section.today
                ? 'date'
                : 'passage';
    String units(int n, [String u = 'passage']) => '$n $u${n == 1 ? '' : 's'}';

    Widget passageRow(Work work, int i) {
      final p = work.passages[i];
      final isCurrent = current != null && current.id == p.id && model.group?.title == work.title;
      return Padding(
        key: isCurrent ? currentKey : null,
        padding: const EdgeInsets.only(bottom: 2),
        child: SideRow(
          selected: isCurrent,
          tooltip: p.isPrayer ? '${p.title} — ${wordLabel(p)}' : p.title,
          onTap: () => model.openIn(work, i),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(listTitle(p), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
            if (p.isPrayer) Text(wordLabel(p), style: dimStyle(context)),
          ]),
        ),
      );
    }

    void branch(String path, String title, Work work, List<int> indexes, {String u = 'passage'}) {
      final visible = [for (final i in indexes) if (matches(state, work.passages[i], q)) i];
      if (visible.isEmpty) return;
      shownIds.addAll(visible.map((i) => work.passages[i].id));
      final holdsCurrent = current != null && model.group?.title == work.title && visible.contains(model.index);
      // The obligatory prayers' groups start open, as in the GTK app; elsewhere the group holding the passage on show.
      // As in the GTK app: the group holding the passage on show opens (without remembering that as a choice); others
      // are as they were left; the obligatory prayers' groups start open.
      final open = q.isNotEmpty ||
          (holdsCurrent && !_closedHere.contains(path)) ||
          (expanded[path] ?? model.section == Section.obligatory);
      rows.add(_Branch(
        title: title,
        count: units(visible.length, u),
        open: open,
        onToggle: () => _toggle(path, open),
      ));
      if (open) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 14, top: 4, bottom: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final i in visible) passageRow(work, i)]),
        ));
      }
    }

    if (library != null) {
      switch (model.section) {
        case Section.prayers:
          // The obligatory prayers are the first entry of Prayers, opening a section of their own.
          if (library.obligatoryGroups.isNotEmpty && q.isEmpty) {
            rows.add(Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SideRow(
                tooltip: 'The three obligatory prayers, their guidance, and the Alláh-u-Abhá counter',
                onTap: () => model.navigate(Section.obligatory),
                child: const Row(children: [Expanded(child: Text('Obligatory prayers')), Icon(Icons.chevron_right, size: 20)]),
              ),
            ));
          }
          for (final cat in library.prayerCategories) {
            branch('prayers/${cat.title}', cat.title, cat, [for (var i = 0; i < cat.passages.length; i++) i], u: 'prayer');
          }
        case Section.writings:
          final book = model.book;
          if (book == null) {
            // The books, under their authors (the page shows a welcome until one is chosen).
            for (final (author, books) in booksByAuthor(library.books)) {
              final visible = [
                for (final w in books)
                  if (q.isEmpty || state.folder!.fold('${w.title} $author').contains(q)) w,
              ];
              if (visible.isEmpty) continue;
              shownIds.addAll(visible.map((w) => 'book/${w.title}'));
              // Each author folds open to their books, like the prayers' topics; all open while searching.
              final path = 'authors/$author';
              final open = q.isNotEmpty || (expanded[path] ?? false);
              rows.add(_Branch(
                title: author,
                count: units(visible.length, 'book'),
                open: open,
                onToggle: () => _toggle(path, open),
              ));
              if (!open) continue;
              rows.add(Padding(
                padding: const EdgeInsets.only(left: 14, top: 4, bottom: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final w in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SideRow(
                        tooltip: '${w.title} — ${w.summary}',
                        onTap: () => model.openBook(w),
                        child: Text(w.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ]),
              ));
            }
          } else {
            for (final (name, indexes) in contentsOf(book)) {
              if (name != null) {
                branch('writings/${book.title}/$name', name, book, indexes);
              } else {
                for (final i in indexes) {
                  if (!matches(state, book.passages[i], q)) continue;
                  shownIds.add(book.passages[i].id);
                  rows.add(passageRow(book, i));
                }
              }
            }
          }
        case Section.saved:
          final count = state.highlights.length;
          if (q.isEmpty) {
            rows.add(Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SideRow(
                tooltip: 'Create, rename and delete collections',
                onTap: () => showCollections(context),
                child: const Row(children: [Expanded(child: Text('Manage collections…')), Icon(Icons.folder_outlined, size: 18)]),
              ),
            ));
          }
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SideRow(
              selected: model.pane == Pane.highlights,
              tooltip: 'Every highlight and note',
              onTap: model.showHighlights,
              child: Row(children: [
                Expanded(child: Text(count > 0 ? 'Highlights & notes · $count' : 'Highlights & notes')),
                const Icon(Icons.chevron_right, size: 20),
              ]),
            ),
          ));
          // A personal prayerbook: the collections in their own order, then whatever is not filed yet.
          for (final g in model.savedGroups()) {
            branch('saved/${g.title}', g.title, g, [for (var i = 0; i < g.passages.length; i++) i]);
          }
        case Section.obligatory:
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SideRow(
              selected: model.pane == Pane.counter,
              onTap: model.showCounter,
              child: const Text('Alláh-u-Abhá counter'),
            ),
          ));
          for (final g in library.obligatoryGroups) {
            branch('obligatory/${g.title}', g.title, g, [for (var i = 0; i < g.passages.length; i++) i]);
          }
        case Section.today:
          final c = state.todayContext();
          final entries = c == null ? const <CalendarRow>[] : calendarRows(c);
          if (entries.isEmpty) rows.add(Text(unpublished, style: dimStyle(context)));
          for (final group in {for (final e in entries) e.group}) {
            final visible = [
              for (final e in entries)
                if (e.group == group && (q.isEmpty || state.folder!.fold('${e.name} ${e.detail}').contains(q))) e,
            ];
            if (visible.isEmpty) continue;
            shownIds.addAll(visible.map((e) => '${e.group}/${e.name}'));
            final path = 'today/${group.split(',').first}';
            final open = q.isNotEmpty || (expanded[path] ?? true);
            rows.add(_Branch(
              title: group,
              count: units(visible.length, 'date'),
              open: open,
              onToggle: () => _toggle(path, open),
            ));
            if (!open) continue;
            rows.add(Padding(
              padding: const EdgeInsets.only(left: 14, top: 4, bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final e in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: SideRow(
                      onTap: e.action == null ? null : () => widget.onAction(TodayRow(RowKind.button, e.name, action: e.action)),
                      tooltip: e.name,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.name),
                        Text(e.detail, style: dimStyle(context)),
                      ]),
                    ),
                  ),
              ]),
            ));
          }
        case Section.home || Section.study:
          break;
      }
    }
    if (q.isNotEmpty && shownIds.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.all(8),
        child: Text('No ${unit}s match “${model.filter.trim()}”.', style: dimStyle(context)),
      ));
    }

    // Keep the passage on show in view in the contents (once per passage, not on every rebuild).
    final key = current == null ? null : '${model.group?.title}/${current.id}';
    if (key != null && key != _scrolledTo) {
      _scrolledTo = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = currentKey.currentContext;
        if (c != null && c.mounted) Scrollable.ensureVisible(c, alignment: 0.4, duration: const Duration(milliseconds: 150));
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: search,
          focusNode: model.filterFocus,
          onChanged: model.setFilter,
          decoration: const InputDecoration(
            hintText: 'Search this section…',
            prefixIcon: Icon(Icons.search, size: 20),
            prefixIconConstraints: BoxConstraints(minWidth: 36),
            contentPadding: EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(units(shownIds.length, unit == 'date' || unit == 'book' ? unit : 'passage'), style: dimStyle(context)),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
          ),
        ),
      ]),
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({required this.title, required this.count, required this.open, required this.onToggle});
  final String title;
  final String count;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Tooltip(
            message: title,
            waitDuration: const Duration(seconds: 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18),
                const SizedBox(width: 2),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Padding(padding: const EdgeInsets.only(right: 12), child: Text(count, style: dimStyle(context))),
              ]),
            ),
          ),
        ),
      );
}

/// Study in the sidebar: the open book's panels (contents, highlights, bookmarks, answers, notes), or the books.
class _StudySide extends StatelessWidget {
  const _StudySide({required this.model});
  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final study = AppScope.of(context).study;
    if (study == null) return const SizedBox.shrink();
    if (model.inBook && study.book != null) return StudyPanels(study: study);
    return ListenableBuilder(
      listenable: study,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          SideRow(
            tooltip: 'Copy a PDF of your own into Study (Ctrl+O)',
            onTap: () => importStudyPdf(context, study, opened: model.showStudyReader),
            child: const Row(children: [Expanded(child: Text('Import a PDF…')), Icon(Icons.file_open_outlined, size: 18)]),
          ),
          const SizedBox(height: 6),
          for (final b in study.library)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SideRow(
                tooltip: b.name,
                onTap: () async {
                  await study.open(b);
                  model.showStudyReader();
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(study.store.currentRun(b).name, style: dimStyle(context)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
