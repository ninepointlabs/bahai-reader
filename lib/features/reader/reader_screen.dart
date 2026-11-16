import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/citations.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../../core/library/passage.dart';
import '../../core/marks/highlight.dart';
import '../marks/highlight_sheet.dart';
import '../today/said_toggle.dart';
import 'passage_text.dart';

/// Reads a work passage by passage, with its contents beside the text (wide windows) or in a drawer (narrow ones).
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.work, this.index = 0, this.query});
  final Work work;
  final int index;

  /// A search to mark in the text, if the reader was opened from search.
  final String? query;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int index = widget.index.clamp(0, widget.work.passages.length - 1);
  final scroll = ScrollController();
  TextSelection selection = const TextSelection.collapsed(offset: -1);
  String? query;

  Passage get passage => widget.work.passages[index];

  @override
  void initState() {
    super.initState();
    query = widget.query;
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.read(context).rememberPosition(widget.work, passage));
  }

  void go(int to) {
    if (to < 0 || to >= widget.work.passages.length) return;
    setState(() {
      index = to;
      selection = const TextSelection.collapsed(offset: -1);
      query = null;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    AppScope.read(context).rememberPosition(widget.work, passage);
  }

  void openPassage(String id) {
    final state = AppScope.read(context);
    final target = state.passageOf(id);
    final place = target == null ? null : state.library!.workOf(target);
    if (place == null) return;
    if (place.$1 == widget.work) {
      go(place.$2);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(work: place.$1, index: place.$2)));
    }
  }

  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied with citation')));
  }

  String? get selectedText => selection.isValid && !selection.isCollapsed
      ? passage.text.substring(selection.start.clamp(0, passage.text.length), selection.end.clamp(0, passage.text.length))
      : null;

  Future<void> highlightSelection({String? color, bool withNote = false}) async {
    final state = AppScope.read(context);
    if (!selection.isValid || selection.isCollapsed) return;
    String? note;
    if (withNote) {
      note = await editNote(context, null);
      if (note == null) return;
    }
    await state.addHighlight(passage, selection.start, selection.end, color: color, note: note);
    setState(() => selection = const TextSelection.collapsed(offset: -1));
  }

  /// A tap (collapsed selection) inside a drawn highlight opens that highlight.
  void selectionChanged(TextSelection s, SelectionChangedCause? cause, List<DrawnHighlight> drawn) {
    setState(() => selection = s);
    if (s.isCollapsed && cause == SelectionChangedCause.tap) {
      for (final (record, a, b) in drawn) {
        if (a <= s.baseOffset && s.baseOffset < b) {
          showHighlightSheet(context, record, passage);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final saved = state.isSaved(passage);
    final contents = _Contents(work: widget.work, current: index, onPick: (i) {
      if (!wide) Navigator.of(context).pop();
      go(i);
    });
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => go(index + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => go(index - 1),
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () => go(index + 1),
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () => go(index - 1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.work.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: saved ? 'Remove from saved' : 'Save passage',
                icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () => state.toggleSaved(passage),
              ),
              IconButton(
                tooltip: 'Copy passage with citation',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () => copy(clipping(passage)),
              ),
              IconButton(
                tooltip: 'Smaller text',
                icon: const Icon(Icons.text_decrease),
                onPressed: () => state.setTextSize(state.settings.textSize - 1),
              ),
              IconButton(
                tooltip: 'Larger text',
                icon: const Icon(Icons.text_increase),
                onPressed: () => state.setTextSize(state.settings.textSize + 1),
              ),
            ],
          ),
          drawer: wide ? null : Drawer(width: 340, child: SafeArea(child: contents)),
          body: Row(children: [
            if (wide) SizedBox(width: 320, child: contents),
            if (wide) const VerticalDivider(width: 1),
            Expanded(child: _page(context, state)),
          ]),
          bottomNavigationBar: _bar(context),
        ),
      ),
    );
  }

  Widget? _bar(BuildContext context) {
    final words = selectedText;
    if (words == null || words.trim().isEmpty) return null;
    return BottomAppBar(
      height: 64,
      child: Row(children: [
        for (final c in highlightColors)
          IconButton(
            tooltip: 'Highlight $c',
            icon: Icon(Icons.circle, color: ReaderColors.of(context).swatch(c)),
            onPressed: () => highlightSelection(color: c),
          ),
        IconButton(
          tooltip: 'Highlight with a note',
          icon: const Icon(Icons.sticky_note_2_outlined),
          onPressed: () => highlightSelection(withNote: true),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Copy with citation',
          icon: const Icon(Icons.copy),
          onPressed: () => copy(clipping(passage, words)),
        ),
      ]),
    );
  }

  Widget _page(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final base = TextStyle(
      fontFamily: readingFonts.first,
      fontFamilyFallback: readingFonts.sublist(1),
      fontSize: state.settings.textSize,
      height: 1.6,
      color: theme.colorScheme.onSurface,
    );
    final drawn = <DrawnHighlight>[];
    final unplaced = <Highlight>[];
    for (final h in state.highlightsOf(passage)) {
      final place = anchor(passage.text, h);
      if (place == null) {
        unplaced.add(h);
      } else {
        drawn.add((h, place.$1, place.$2));
        state.reanchor(h, place);
      }
    }
    final followed = state.followedHighlights(passage);
    final q = query;
    final hit = q == null || state.folder == null ? null : state.folder!.find(passage.text, state.folder!.fold(q.trim()));
    final language = state.language;
    return SelectionArea(
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (passage.subgroup != null)
                  Text(passage.subgroup!, style: theme.textTheme.labelLarge?.copyWith(color: muted)),
                if (phoneHeading(passage) case final heading?)
                  Text(
                    heading,
                    style: theme.textTheme.titleLarge,
                    textDirection: language.rtl ? TextDirection.rtl : null,
                  ),
                if (passage.author != null) Text(passage.author!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: 16),
                for (final h in followed) _MarkCard(record: h, title: 'Highlighted in ${state.languageInfo(languageOf(h.id)).english}'),
                for (final h in unplaced) _MarkCard(record: h, title: 'The text changed; this highlight could not be placed'),
                SelectionContainer.disabled(
                  child: SelectableText.rich(
                    passageSpans(
                      passage: passage,
                      base: base,
                      palette: ReaderColors.of(context),
                      muted: muted,
                      highlights: drawn,
                      hit: hit,
                      hitColor: theme.colorScheme.tertiaryContainer,
                    ),
                    textDirection: language.rtl ? TextDirection.rtl : null,
                    onSelectionChanged: (s, cause) => selectionChanged(s, cause, drawn),
                    contextMenuBuilder: (context, editable) => AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editable.contextMenuAnchors,
                      buttonItems: [
                        ...editable.contextMenuButtonItems,
                        ContextMenuButtonItem(
                          label: 'Highlight',
                          onPressed: () {
                            editable.hideToolbar();
                            highlightSelection();
                          },
                        ),
                        ContextMenuButtonItem(
                          label: 'Copy with citation',
                          onPressed: () {
                            editable.hideToolbar();
                            final w = selectedText;
                            if (w != null) copy(clipping(passage, w));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (passage.citation.isNotEmpty)
                  Text('— ${passage.citation}', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                if (passage.references.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (id, label) in passage.references)
                      ActionChip(label: Text(label), onPressed: () => openPassage(id)),
                  ]),
                ],
                // "Said today" for an obligatory prayer: the same mark as on Today.
                if (state.saidWindow(passage) case final w?) ...[
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerLeft, child: SaidToggle(window: w)),
                ],
                const SizedBox(height: 24),
                Row(children: [
                  if (index > 0)
                    OutlinedButton.icon(
                        onPressed: () => go(index - 1), icon: const Icon(Icons.chevron_left), label: const Text('Previous')),
                  const Spacer(),
                  Text('${index + 1} of ${widget.work.passages.length}', style: theme.textTheme.bodySmall),
                  const Spacer(),
                  if (index + 1 < widget.work.passages.length)
                    FilledButton.tonalIcon(
                        onPressed: () => go(index + 1), icon: const Icon(Icons.chevron_right), label: const Text('Next')),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// The heading above a passage. Titles made from the passage's opening words (cut short for the contents list) are not
/// repeated over the full text: only their number is kept, if any.

/// A highlight that cannot be drawn on this text: made in another language, or its words are no longer there.
/// Shown above the passage as a passage-level marker, with the note in full.
class _MarkCard extends StatelessWidget {
  const _MarkCard({required this.record, required this.title});
  final Highlight record;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: ReaderColors.of(context).swatch(record.color)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$title: “${excerpt(record.words, 160)}”',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                if (record.note != null) ...[const SizedBox(height: 6), Text(record.note!)],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Contents extends StatelessWidget {
  const _Contents({required this.work, required this.current, required this.onPick});
  final Work work;
  final int current;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (final (group, indexes) in work.contents) {
      if (group != null) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(group, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ));
      }
      for (final i in indexes) {
        rows.add(ListTile(
          dense: true,
          selected: i == current,
          title: Text(work.passages[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => onPick(i),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Contents', style: theme.textTheme.titleMedium),
      ),
      Expanded(child: ListView(children: rows)),
    ]);
  }
}
