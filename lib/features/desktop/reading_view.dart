import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/citations.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../../core/library/passage.dart';
import '../../core/marks/highlight.dart';
import '../reader/passage_text.dart';
import '../settings/collections_dialog.dart';
import 'shell_model.dart';
import '../today/said_toggle.dart';
import 'widgets.dart';

/// The reading pane, laid out as the GTK app's: the book and part as a small line, the heading in the accent colour,
/// the passage's place and reading time, the text, its citation; below, Previous, progress through the book and Next.
/// Selecting words offers four colours, a note and Copy; clicking a highlight opens its colour, note and Remove.
class ReadingView extends StatefulWidget {
  const ReadingView({super.key, required this.model});
  final ShellModel model;

  @override
  State<ReadingView> createState() => ReadingViewState();
}

class ReadingViewState extends State<ReadingView> {
  final scroll = ScrollController();
  final textKey = GlobalKey();
  final viewportKey = GlobalKey();
  TextSelection selection = const TextSelection.collapsed(offset: -1);

  /// Bumped to clear the text's selection (a new SelectableText) once it has been highlighted.
  int selectionEpoch = 0;
  int _turn = -1;
  Offset? _pointer;
  Timer? _settle;
  List<DrawnHighlight> _drawn = const [];

  ShellModel get model => widget.model;
  Passage? get passage => model.current;

  @override
  void dispose() {
    _settle?.cancel();
    scroll.dispose();
    super.dispose();
  }

  String? get selectedWords {
    final p = passage;
    if (p == null || !selection.isValid || selection.isCollapsed) return null;
    final a = selection.start.clamp(0, p.text.length), b = selection.end.clamp(0, p.text.length);
    final words = p.text.substring(a, b);
    return words.trim().isEmpty ? null : words;
  }

  /// Copies the selected words, or the whole passage, with the citation.
  void copy() {
    final p = passage;
    if (p == null) return;
    Clipboard.setData(ClipboardData(text: clipping(p, selectedWords)));
    toast(context, 'Copied with its citation');
  }

  void _clearSelection() => setState(() {
        selection = const TextSelection.collapsed(offset: -1);
        selectionEpoch++;
      });

  /// Highlights the selected words; [edit] opens the note at once (Ctrl+H, or Note… on the bar).
  Future<void> highlightSelection({String? color, bool edit = false}) async {
    final p = passage;
    if (p == null || selectedWords == null) return;
    final state = AppScope.read(context);
    final record = await state.addHighlight(p, selection.start, selection.end, color: color);
    if (!mounted) return;
    final anchor = _anchorRect();
    _clearSelection();
    if (record != null && edit) _editHighlight(record, anchor, focusNote: true);
  }

  Rect _anchorRect() {
    final at = _pointer;
    if (at != null) return Rect.fromCenter(center: at, width: 2, height: 22);
    final box = textKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Rect.zero;
    final o = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(o.dx + box.size.width / 2, o.dy, 2, 22);
  }

  void _selectionChanged(TextSelection s, SelectionChangedCause? cause) {
    setState(() => selection = s);
    _settle?.cancel();
    if (s.isCollapsed) {
      if (cause == SelectionChangedCause.tap) {
        for (final (record, a, b) in _drawn) {
          if (a <= s.baseOffset && s.baseOffset < b) {
            _editHighlight(record, _anchorRect());
            return;
          }
        }
      }
      return;
    }
    // Once the selection has settled (a drag, or Shift+arrows), not on every step of it.
    final seen = s;
    _settle = Timer(const Duration(milliseconds: 450), () {
      if (mounted && selection == seen && selectedWords != null) _showMarkBar();
    });
  }

  void _showMarkBar() {
    final state = AppScope.read(context);
    showPopoverAt<void>(context, _anchorRect(), (pop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _Swatches(onChoose: (c) {
            Navigator.pop(pop);
            highlightSelection(color: c);
          }),
          const SizedBox(width: 10),
          SizedBox(height: 24, child: VerticalDivider(width: 1, color: ReaderColors.of(context).selection)),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () {
              Navigator.pop(pop);
              highlightSelection(color: state.settings.highlightColor, edit: true);
            },
            child: const Text('Note…'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(pop);
              copy();
            },
            child: const Text('Copy'),
          ),
        ]),
      );
    });
  }

  Future<void> _editHighlight(Highlight record, Rect anchor, {bool focusNote = false}) async {
    final state = AppScope.read(context);
    final note = TextEditingController(text: record.note ?? '');
    final removed = await showPopoverAt<bool>(
      context,
      anchor,
      (pop) => _HighlightEditor(record: record, note: note, focusNote: focusNote),
    );
    if (removed == true) {
      await state.removeHighlight(record);
    } else {
      final text = note.text.trim();
      if (text != (record.note ?? '')) await state.updateHighlight(record, note: text);
    }
    note.dispose();
  }

  void _scrollToOffset(int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = textKey.currentContext?.findRenderObject() as RenderBox?;
      final view = viewportKey.currentContext?.findRenderObject() as RenderBox?;
      final p = passage;
      if (box == null || view == null || p == null || !scroll.hasClients) return;
      final editable = _findEditable(box);
      double caret = 0;
      if (editable != null) {
        caret = editable.getLocalRectForCaret(TextPosition(offset: offset.clamp(0, p.text.length))).top;
      }
      final top = box.localToGlobal(Offset.zero).dy - view.localToGlobal(Offset.zero).dy + scroll.offset;
      final target = (top + caret - view.size.height * 0.3).clamp(0.0, scroll.position.maxScrollExtent);
      scroll.jumpTo(target);
    });
  }

  RenderEditable? _findEditable(RenderObject root) {
    RenderEditable? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderEditable) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = passage;
    if (model.turn != _turn) {
      _turn = model.turn;
      selection = const TextSelection.collapsed(offset: -1);
      selectionEpoch++;
      final at = model.found?.$1 ?? model.scrollTo;
      if (at != null) {
        _scrollToOffset(at);
      } else if (scroll.hasClients) {
        scroll.jumpTo(0);
      }
    }
    return Column(children: [
      Expanded(
        child: Stack(key: viewportKey, children: [
          Positioned.fill(child: p == null ? _empty(context) : _pages(context, state, p)),
          // The text fades out just above the footer rather than running under it.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 24,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [ReaderColors.of(context).background.withValues(alpha: 0), ReaderColors.of(context).background],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
      if (!model.focusMode) _footer(context, state, p),
    ]);
  }

  Widget _empty(BuildContext context) {
    final saved = model.section == Section.saved;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(children: [
        Text(saved ? 'Press Ctrl+D or ☆ Save to keep one here.' : 'This language’s library has none here.',
            style: _eyebrow(context)),
        const SizedBox(height: 6),
        Text(saved ? 'No saved passages yet' : 'No passages found', style: _heading(context)),
      ]),
    );
  }

  TextStyle _eyebrow(BuildContext context) => TextStyle(
      fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: ReaderColors.of(context).foreground.withValues(alpha: 0.75));

  TextStyle _heading(BuildContext context) =>
      TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: ReaderColors.of(context).accentText);

  /// The book the passage belongs to (wherever it was opened from) and where it is in it.
  (Work, int)? _book(AppState state, Passage p) {
    final place = state.library?.workOf(p);
    return place != null && place.$1.kind == 'writings' ? place : null;
  }

  Widget _page(BuildContext context, AppState state, Passage p) {
    final palette = ReaderColors.of(context);
    final size = state.settings.textSize;
    final base = TextStyle(
      fontFamily: readingFace(context).fontFamily,
      fontFamilyFallback: readingFace(context).fontFamilyFallback,
      fontSize: size,
      height: 1.17 + state.settings.spacingOrDefault / size,
      color: palette.foreground,
    );
    final drawn = <DrawnHighlight>[];
    final unplaced = <Highlight>[];
    for (final h in state.highlightsOf(p)) {
      final place = anchor(p.text, h);
      if (place == null) {
        unplaced.add(h);
      } else {
        drawn.add((h, place.$1, place.$2));
        state.reanchor(h, place);
      }
    }
    _drawn = drawn;
    final followed = state.followedHighlights(p);
    final context0 = model.group?.kind == 'prayers' ? model.group!.title : null;
    final book = _book(state, p);
    final minutes = (p.wordCount / 230).round().clamp(1, 1 << 30);
    final rtl = state.language.rtl;
    return LayoutBuilder(builder: (context, box) {
      // Page margins give way once the text column would get narrower than about 360 px (GTK `fit_margins()`).
      final margin = ((box.maxWidth - 360) / 2).clamp(12.0, state.settings.marginOrDefault.toDouble());
      return SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(margin, 26, margin, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text([if (model.label != null) model.label!, subtitle(p, context0)].where((s) => s.isNotEmpty).join(' · '),
              textAlign: TextAlign.center, style: _eyebrow(context)),
          const SizedBox(height: 6),
          Text(heading(p, context0), textAlign: TextAlign.center, style: _heading(context)),
          if (book != null) ...[
            const SizedBox(height: 6),
            Text(
              'Passage ${book.$2 + 1} of ${book.$1.passages.length} · about $minutes minute${minutes == 1 ? '' : 's'}',
              textAlign: TextAlign.center,
              style: dimStyle(context),
            ),
          ],
          const SizedBox(height: 26),
          for (final h in followed)
            _MarkCard(record: h, title: 'Highlighted in ${state.languageInfo(languageOf(h.id)).english}'),
          for (final h in unplaced) _MarkCard(record: h, title: 'The text changed; this highlight is kept but not drawn'),
          Listener(
            key: textKey,
            onPointerDown: (e) => _pointer = e.position,
            onPointerUp: (e) => _pointer = e.position,
            child: SelectableText.rich(
              passageSpans(
                passage: p,
                base: base,
                palette: palette,
                muted: palette.dim,
                highlights: drawn,
                hit: model.found,
                hitColor: palette.selection,
              ),
              key: ValueKey('text-${p.id}-$selectionEpoch'),
              textDirection: rtl ? TextDirection.rtl : null,
              onSelectionChanged: _selectionChanged,
              contextMenuBuilder: (context, editable) => AdaptiveTextSelectionToolbar.buttonItems(
                anchors: editable.contextMenuAnchors,
                buttonItems: [
                  ...editable.contextMenuButtonItems,
                  ContextMenuButtonItem(
                    label: 'Highlight',
                    onPressed: () {
                      editable.hideToolbar();
                      highlightSelection(edit: true);
                    },
                  ),
                  ContextMenuButtonItem(
                    label: 'Copy with citation',
                    onPressed: () {
                      editable.hideToolbar();
                      copy();
                    },
                  ),
                ],
              ),
            ),
          ),
          if (p.citation.isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText('— ${p.citation}',
                style: base.copyWith(fontStyle: FontStyle.italic, fontSize: size * 0.85, height: 1.5)),
          ],
          if (p.references.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (id, label) in p.references)
                OutlinedButton(
                  onPressed: () {
                    final target = state.passageOf(id);
                    if (target != null) model.openPassage(target);
                  },
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      textStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13.5)),
                  child: Text(label),
                ),
            ]),
          ],
          // A saved passage: which collection it is in (GTK shows this under the passage too).
          if (state.savedKeys(p).firstOrNull case final key?) ...[
            const SizedBox(height: 18),
            FilingRow(savedKey: key),
          ],
        ]),
      );
    });
  }

  /// The passage, and beside it (below it in a narrow window) the same passage in the Side by side language.
  Widget _pages(BuildContext context, AppState state, Passage p) {
    final compare = state.settings.compare;
    if (compare == null || compare == state.settings.language) return _page(context, state, p);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final divider = ReaderColors.of(context).selection;
    final second = _SecondLanguage(passage: p, language: compare, follow: scroll);
    return Flex(
      direction: narrow ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _page(context, state, p)),
        narrow ? Divider(height: 1, color: divider) : VerticalDivider(width: 1, color: divider),
        Expanded(child: second),
      ],
    );
  }

  Widget _footer(BuildContext context, AppState state, Passage? p) {
    final palette = ReaderColors.of(context);
    final g = model.group;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    String where = '', percent = '';
    double? fraction;
    if (p != null && g != null) {
      final book = _book(state, p);
      if (book != null) {
        final (before, total) = bookProgress(book.$1.passages, p);
        final f = total == 0 ? 0.0 : before / total;
        where = '${book.$1.title} · ${book.$2 + 1} of ${book.$1.passages.length}';
        percent = '${(100 * f).round()}% of the book';
        fraction = f;
      } else if (g.passages.length > 1) {
        where = '${model.index + 1} of ${g.passages.length}';
        fraction = model.index / (g.passages.length - 1);
      }
    }
    final canBack = p != null && model.index > 0;
    final canNext = p != null && g != null && model.index + 1 < g.passages.length;
    final language = state.language;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.selection))),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          OutlinedButton(
            onPressed: canBack ? () => model.step(-1) : null,
            child: Text(narrow ? '←' : '← Previous'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: fraction == null
                ? const SizedBox()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: dimStyle(context))),
                      if (percent.isNotEmpty) Text(percent, style: dimStyle(context)),
                    ]),
                    const SizedBox(height: 6),
                    Semantics(label: percent.isEmpty ? where : percent, child: Bar(value: fraction)),
                  ]),
          ),
          if (state.saidWindow(p) case final w?) ...[
            const SizedBox(width: 12),
            SaidToggle(window: w),
          ],
          const SizedBox(width: 12),
          FilledButton(
            onPressed: canNext ? () => model.step(1) : null,
            style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
            child: Text(narrow ? '→' : 'Next →'),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 14),
          child: Text(
            '${language.name} · Available offline · Texts: BahaiPrayers.net${language.id == 1 ? ', bahai.org' : ''}',
            textAlign: TextAlign.center,
            style: dimStyle(context),
          ),
        ),
      ]),
    );
  }
}

/// The four highlight colours as round swatches, in the colours the highlights are drawn in.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.onChoose, this.chosen});
  final ValueChanged<String> onChoose;
  final String? chosen;

  static const names = {'yellow': 'Yellow', 'green': 'Green', 'blue': 'Blue', 'magenta': 'Magenta'};

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final c in highlightColors)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: names[c]!,
            child: Semantics(
              button: true,
              label: 'Highlight in ${names[c]!.toLowerCase()}',
              child: InkResponse(
                onTap: () => onChoose(c),
                radius: 16,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: p.highlight(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: c == chosen ? p.foreground : Colors.transparent, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// One highlight: its colour, its note, and Remove. The note is kept when the popover closes.
class _HighlightEditor extends StatefulWidget {
  const _HighlightEditor({required this.record, required this.note, required this.focusNote});
  final Highlight record;
  final TextEditingController note;
  final bool focusNote;

  @override
  State<_HighlightEditor> createState() => _HighlightEditorState();
}

class _HighlightEditorState extends State<_HighlightEditor> {
  late String color = widget.record.color;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final p = ReaderColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _Swatches(
              chosen: color,
              onChoose: (c) {
                setState(() => color = c);
                state.updateHighlight(widget.record, color: c);
                state.settings.highlightColor = c;
              },
            ),
          ),
          const SizedBox(height: 10),
          Text('Note', style: dimStyle(context)),
          const SizedBox(height: 4),
          TextField(
            controller: widget.note,
            autofocus: widget.focusNote,
            minLines: 4,
            maxLines: 9,
            maxLength: noteLimit,
            style: const TextStyle(fontSize: 14),
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
              '${_thousands(currentLength)} / ${_thousands(maxLength ?? noteLimit)}',
              style: dimStyle(context, size: 12),
            ),
            decoration: InputDecoration(
              fillColor: p.card,
              hintText: 'Your note (kept on this device only)',
              contentPadding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFE0605A)),
                child: const Text('Remove highlight', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Done')),
          ]),
        ]),
      ),
    );
  }
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// A highlight that cannot be drawn on this text (made in another language, or its words are gone): shown above the
/// passage with its note in full.
class _MarkCard extends StatelessWidget {
  const _MarkCard({required this.record, required this.title});
  final Highlight record;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = ReaderColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CardButton(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
                width: 4, decoration: BoxDecoration(color: p.highlight(record.color), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$title: “${excerpt(record.words, 160)}”', style: dimStyle(context, size: 13.5)),
                if (record.note != null) ...[const SizedBox(height: 4), SelectableText(record.note!)],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Side by side: the same passage in another language on this computer, paired by its numbering as BahaiPrayers.net's
/// Matrix feeds pair them (GTK `show_second()`). It keeps to the same point in the passage as the text is scrolled.
class _SecondLanguage extends StatefulWidget {
  const _SecondLanguage({required this.passage, required this.language, required this.follow});
  final Passage passage;
  final int language;
  final ScrollController follow;

  @override
  State<_SecondLanguage> createState() => _SecondLanguageState();
}

class _SecondLanguageState extends State<_SecondLanguage> {
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.follow.addListener(_follow);
  }

  @override
  void didUpdateWidget(covariant _SecondLanguage old) {
    super.didUpdateWidget(old);
    if (old.follow != widget.follow) {
      old.follow.removeListener(_follow);
      widget.follow.addListener(_follow);
    }
    if (old.passage.id != widget.passage.id && scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  void dispose() {
    widget.follow.removeListener(_follow);
    scroll.dispose();
    super.dispose();
  }

  /// Proportionally, as the GTK app does.
  void _follow() {
    if (!widget.follow.hasClients || !scroll.hasClients) return;
    final from = widget.follow.position, to = scroll.position;
    if (from.maxScrollExtent <= 0) return;
    scroll.jumpTo((from.pixels / from.maxScrollExtent * to.maxScrollExtent).clamp(0, to.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final palette = ReaderColors.of(context);
    final info = state.languageInfo(widget.language);
    final lib = state.compareLibrary;
    final match = widget.passage.match;
    final item = match == null ? null : lib?.byMatch[match];
    final size = state.settings.textSize;
    final base = TextStyle(
      fontFamily: readingFace(context).fontFamily,
      fontFamilyFallback: readingFace(context).fontFamilyFallback,
      fontSize: size,
      height: 1.17 + state.settings.spacingOrDefault / size,
      color: palette.foreground,
    );
    final note = base.copyWith(fontStyle: FontStyle.italic, fontSize: size * 0.85);
    String? message;
    if (lib == null) {
      message = 'Loading the ${info.english} library…';
    } else if (lib.passages.isEmpty) {
      message =
          'The ${info.english} library is not downloaded or could not be read. Download it in ⋮ → Languages & offline libraries.';
    } else if (match == null) {
      message =
          'Prayers, Days of Remembrance and Riḍván messages are not numbered the same way in every language, so they cannot be shown side by side.';
    } else if (item == null) {
      message = 'This passage is not in the downloaded ${info.english} library.';
    }
    return LayoutBuilder(builder: (context, box) {
      final margin = ((box.maxWidth - 360) / 2).clamp(12.0, state.settings.marginOrDefault.toDouble());
      return SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(margin, 26, margin, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            header: true,
            child: Text(info.name.toUpperCase(), style: base.copyWith(fontSize: size * 0.7, height: 1.2)),
          ),
          const SizedBox(height: 12),
          if (message != null)
            Text(message, style: note)
          else ...[
            SelectableText.rich(
              passageSpans(passage: item!, base: base, palette: palette, muted: palette.dim),
              textDirection: info.rtl ? TextDirection.rtl : TextDirection.ltr,
            ),
            if (item.citation.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText('— ${item.citation}', style: note.copyWith(height: 1.5)),
            ],
          ],
        ]),
      );
    });
  }
}
