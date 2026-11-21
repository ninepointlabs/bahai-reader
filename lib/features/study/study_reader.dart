import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/app/theme.dart';
import '../../core/study/page_data.dart';
import '../../core/study/rules.dart';
import '../../core/study/study_controller.dart';
import '../../core/study/study_store.dart';
import '../marks/highlight_sheet.dart' show editNote;

/// The ink answers are written in: blue, so they read as filled in rather than printed (as in Dogear).
const answerInk = Color(0xFF1F4FA8);

/// A Study book's pages, with the run's highlights, bookmarks and answers drawn on them.
///
/// Desktop keys (when the page has focus, not while typing): 1–5 highlight the selection in that colour, `a` (or
/// Ctrl+H) highlights it and asks for a note, `b` (or Ctrl+D) bookmarks the page, `i` answers the first empty line in
/// view, `j`/`k` scroll, `J`/`K` and Alt+→/Alt+← turn pages, `g`/`G` go to the first or last page, `+`/`-`/`0` zoom,
/// Ctrl+G goes to a page, Ctrl+F or `/` searches.
class StudyReader extends StatefulWidget {
  const StudyReader({super.key, required this.study, this.touch = false, this.onExport, this.onNewNote});
  final StudyController study;

  /// Phones and tablets: no hover, long-press selection, and the colour bar is the way to highlight.
  final bool touch;
  final VoidCallback? onExport;
  final VoidCallback? onNewNote;

  @override
  State<StudyReader> createState() => StudyReaderState();
}

class StudyReaderState extends State<StudyReader> {
  final pdf = PdfViewerController();
  late final searcher = PdfTextSearcher(pdf)..addListener(_searchChanged);
  final focus = FocusNode(debugLabel: 'study page');
  final search = TextEditingController();
  final searchFocus = FocusNode();
  bool searching = false;

  /// The empty answer line under the pointer (desktop), to light up.
  (int, Rule)? hovered;

  /// The answer being typed.
  final answer = TextEditingController();
  final answerFocus = FocusNode(debugLabel: 'answer');
  Timer? _keep;

  StudyController get study => widget.study;

  @override
  void initState() {
    super.initState();
    study.goTo = _goTo;
    answer.addListener(_typed);
    answerFocus.addListener(() {
      // Clicking elsewhere is "done".
      if (!answerFocus.hasFocus && study.editing != null) _finishAnswer();
    });
  }

  @override
  void dispose() {
    _keep?.cancel();
    if (study.editing != null) study.finishAnswer(answer.text);
    if (study.goTo == _goTo) study.goTo = null;
    searcher.removeListener(_searchChanged);
    searcher.dispose();
    focus.dispose();
    search.dispose();
    searchFocus.dispose();
    answer.dispose();
    answerFocus.dispose();
    super.dispose();
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  void _typed() {
    _keep?.cancel();
    _keep = Timer(const Duration(milliseconds: 800), () => study.keepAnswer(answer.text));
  }

  // ----- places -----

  /// A page's place in the viewer: where it is and how many pixels a point is.
  static double _scale(Rect pageRect, PdfPage page) => pageRect.width / page.width;

  /// The page and the point on it (top-left points) under a document position.
  (PdfPage, Offset)? _hit(Offset documentPosition) {
    final r = pdf.getPdfPageHitTestResult(documentPosition, useDocumentLayoutCoordinates: true);
    if (r == null) return null;
    return (r.page, Offset(r.offset.x, r.page.height - r.offset.y));
  }

  void _goTo(int page, {double y = 0}) {
    if (!pdf.isReady) return;
    if (y <= 0) {
      pdf.goToPage(pageNumber: page, anchor: PdfPageAnchor.top);
      return;
    }
    final p = pdf.pages[page - 1];
    final top = (y - 40).clamp(0.0, p.height);
    pdf.goToRectInsidePage(
      pageNumber: page,
      rect: PdfRect(0, p.height - top, p.width, math.max(0, p.height - top - 200)),
      anchor: PdfPageAnchor.top,
    );
  }

  // ----- highlighting -----

  /// Highlights the selected text in [color] (the last colour used if null); with [note], asks for a note too.
  Future<void> highlightSelection({String? color, bool note = false}) async {
    if (study.readOnly) return;
    final delegate = pdf.textSelectionDelegate;
    if (!delegate.hasSelectedText) return;
    final ranges = await delegate.getSelectedTextRanges();
    DocHighlight? last;
    for (final r in ranges) {
      final data = await study.pageData(r.pageNumber);
      if (data == null) continue;
      last = study.highlight(data, r.start, r.end, color: color) ?? last;
    }
    await delegate.clearTextSelection();
    if (note && last != null && mounted) {
      final text = await editNote(context, last.note);
      if (text != null) study.setNote(last, text);
    }
    focus.requestFocus();
  }

  /// Change a highlight's colour, its note, copy its words, or remove it.
  Future<void> _highlightMenu(DocHighlight h) async {
    final locked = study.readOnly;
    final p = ReaderColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('“${h.quote}”', maxLines: 6, overflow: TextOverflow.ellipsis),
              if (h.note != null) ...[
                const SizedBox(height: 8),
                Text(h.note!, maxLines: 6, overflow: TextOverflow.ellipsis, style: Theme.of(sheet).textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!locked)
                    for (final c in studyColors)
                      IconButton(
                        tooltip: c,
                        isSelected: c == h.color,
                        icon: Icon(c == h.color ? Icons.check_circle : Icons.circle, color: p.swatch(c)),
                        onPressed: () {
                          Navigator.pop(sheet);
                          study.recolor(h, c);
                        },
                      ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: h.quote));
                      Navigator.pop(sheet);
                    },
                  ),
                  if (!locked) ...[
                    IconButton(
                      tooltip: h.note == null ? 'Add a note' : 'Edit the note',
                      icon: const Icon(Icons.sticky_note_2_outlined),
                      onPressed: () async {
                        Navigator.pop(sheet);
                        final text = await editNote(context, h.note);
                        if (text != null) study.setNote(h, text);
                      },
                    ),
                    IconButton(
                      tooltip: 'Remove the highlight',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        Navigator.pop(sheet);
                        study.unhighlight(h);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    focus.requestFocus();
  }

  // ----- answers -----

  /// The blank of the printed question this line is, counting the page's lines with the same question before it.
  int _ordinal(PageData data, Rule rule, String context) {
    var n = 0;
    for (final r in data.rules) {
      if (identical(r, rule)) break;
      if (data.contextAt(r.x + 5, r.y) == context) n++;
    }
    return n;
  }

  /// Starts typing on the answer line [index] of [data] (with the ruled lines below it), or in [box].
  void _startAnswer(PageData data, {int? index, Rect? box}) {
    if (study.readOnly) return;
    if (study.editing != null) _finishAnswer();
    AnswerPlace place;
    String context;
    var ordinal = 0;
    if (index != null) {
      final rule = data.rules[index];
      final slot = slotFrom(data.rules, index, data.fontSize);
      place = AnswerPlace(
        page: data.number,
        kind: 'line',
        x: slot.x,
        y: slot.y,
        w: slot.w,
        pitch: slot.pitch,
        lines: slot.lines,
        indent: slot.indent,
        size: slot.size,
      );
      context = data.contextAt(rule.x + 5, rule.y);
      ordinal = _ordinal(data, rule, context);
    } else {
      final b = box!;
      place = AnswerPlace(
        page: data.number,
        kind: 'box',
        x: b.left,
        y: b.top,
        w: b.width,
        h: b.height,
        size: data.fontSize > 0 ? data.fontSize.clamp(8, 14) : 11,
      );
      context = data.contextAt(b.left + 5, b.top);
    }
    final existing = study.answerAt(place);
    if (existing != null) place = existing.place;
    answer.text = existing?.text ?? '';
    answer.selection = TextSelection.collapsed(offset: answer.text.length);
    study.startAnswer(AnswerEdit(place: place, context: existing?.context ?? context, ordinal: ordinal));
    WidgetsBinding.instance.addPostFrameCallback((_) => answerFocus.requestFocus());
  }

  void _finishAnswer() {
    _keep?.cancel();
    if (study.editing == null) return;
    study.finishAnswer(answer.text);
  }

  /// Tab / Shift+Tab: the next or previous answer line on the page (then the next page's).
  Future<void> _nextBlank(int delta) async {
    final e = study.editing;
    if (e == null) return;
    _finishAnswer();
    var number = e.place.page;
    var data = await study.pageData(number);
    if (data == null) return;
    // The rules each slot starts on, in order.
    List<int> starts(PageData d) {
      final out = <int>[];
      var i = 0;
      while (i < d.rules.length) {
        out.add(i);
        // A blank with ruled lines under it is one answer: skip the lines it takes.
        i += math.max(1, slotFrom(d.rules, i, d.fontSize).lines);
      }
      return out;
    }

    var list = starts(data);
    var at = list.indexWhere((i) => (data!.rules[i].y - e.place.y).abs() < 1 && data.rules[i].x >= e.place.x - 1);
    if (at < 0) at = list.indexWhere((i) => data!.rules[i].y > e.place.y) - (delta > 0 ? 1 : 0);
    var next = at + delta;
    while (next < 0 || next >= list.length) {
      number += delta;
      final d = await study.pageData(number);
      if (d == null) return;
      data = d;
      list = starts(d);
      next = delta > 0 ? 0 : list.length - 1;
      if (list.isEmpty) next = -1;
      if (next >= 0) break;
    }
    if (!mounted) return;
    _goTo(number, y: data!.rules[list[next]].y);
    _startAnswer(data, index: list[next]);
  }

  /// `i`: the first empty answer line on the page in view.
  Future<void> _answerFirstInView() async {
    final data = await study.pageData(study.page);
    if (data == null || data.rules.isEmpty) return;
    for (var i = 0; i < data.rules.length; i++) {
      final s = slotFrom(data.rules, i, data.fontSize);
      final place = AnswerPlace(page: data.number, kind: 'line', x: s.x, y: s.y, w: s.w);
      if (study.answerAt(place) == null) {
        _startAnswer(data, index: i);
        return;
      }
    }
    _startAnswer(data, index: 0);
  }

  // ----- taps -----

  bool _onTap(BuildContext context, PdfViewerController controller, PdfViewerGeneralTapHandlerDetails d) {
    final hit = _hit(d.documentPosition);
    if (hit == null) return false;
    final (page, at) = hit;
    final data = study.pageIfLoaded(page.pageNumber);
    if (data == null) {
      study.pageData(page.pageNumber);
      return false;
    }
    final type = d.type;
    if (type == PdfViewerGeneralTapType.tap || type == PdfViewerGeneralTapType.secondaryTap) {
      // A highlight under the pointer.
      for (final h in study.highlights.reversed) {
        if (h.page == page.pageNumber && h.rects.any((r) => _inflate(r, 1.5).contains(at))) {
          _highlightMenu(h);
          return true;
        }
      }
      // An answer box or line.
      for (final a in study.answers) {
        if (a.page == page.pageNumber && _answerRect(a.place).contains(at)) {
          _startAnswerAt(data, a.place);
          return true;
        }
      }
      final i = ruleAt(data.rules, at.dx, at.dy);
      if (i >= 0 && d.tapOn != PdfViewerPart.selectedText) {
        _startAnswer(data, index: i);
        return true;
      }
      if (study.editing != null) {
        _finishAnswer();
        return true;
      }
    }
    // Long press (or right-click) on empty paper: an answer box there.
    if ((type == PdfViewerGeneralTapType.longPress || type == PdfViewerGeneralTapType.secondaryTap) &&
        !study.readOnly &&
        !_nearText(data, at)) {
      final w = math.min(220.0, page.width - at.dx - 24);
      if (w > 40) {
        _startAnswer(data, box: Rect.fromLTWH(at.dx, at.dy - 8, w, 48));
        return true;
      }
    }
    return false;
  }

  void _startAnswerAt(PageData data, AnswerPlace place) {
    if (place.kind == 'line') {
      final i = data.rules.indexWhere((r) => (r.y - place.y).abs() < 1 && (r.x - (place.x + place.indent)).abs() < 2);
      if (i >= 0) return _startAnswer(data, index: i);
    }
    if (study.readOnly) return;
    if (study.editing != null) _finishAnswer();
    final existing = study.answerAt(place);
    answer.text = existing?.text ?? '';
    study.startAnswer(AnswerEdit(place: place, context: existing?.context ?? '', ordinal: 0));
    WidgetsBinding.instance.addPostFrameCallback((_) => answerFocus.requestFocus());
  }

  static bool _nearText(PageData data, Offset at) => data.chars.any((c) => c.w > 0 && _inflate(c, 6).contains(at));

  static Rect _inflate(Box b, double by) => Rect.fromLTWH(b.x - by, b.y - by, b.w + 2 * by, b.h + 2 * by);

  /// Where an answer's text sits, in points.
  static Rect _answerRect(AnswerPlace p) {
    if (p.kind == 'box') return Rect.fromLTWH(p.x, p.y, p.w, math.max(p.h, 14));
    final lineHeight = p.pitch > 0 ? p.pitch : math.max(p.size * 1.6, 14);
    final top = p.y - lineHeight + 2;
    return Rect.fromLTWH(p.x + p.indent, top, p.w - p.indent, lineHeight + (p.lines - 1) * p.pitch + 4);
  }

  void _hover(PointerHoverEvent e) {
    if (widget.touch || study.readOnly) return;
    final doc = pdf.isReady ? pdf.globalToDocument(e.position) : null;
    (int, Rule)? found;
    if (doc != null) {
      final hit = _hit(doc);
      if (hit != null) {
        final data = study.pageIfLoaded(hit.$1.pageNumber);
        if (data != null) {
          final i = ruleAt(data.rules, hit.$2.dx, hit.$2.dy);
          if (i >= 0) {
            final r = data.rules[i];
            final s = slotFrom(data.rules, i, data.fontSize);
            final empty = study.answerAt(AnswerPlace(page: data.number, kind: 'line', x: s.x, y: s.y, w: s.w)) == null;
            if (empty) found = (data.number, r);
          }
        }
      }
    }
    if (found?.$1 != hovered?.$1 || !identical(found?.$2, hovered?.$2)) setState(() => hovered = found);
  }

  // ----- drawing -----

  List<Widget> _overlays(BuildContext context, Rect pageRect, PdfPage page) {
    final s = _scale(pageRect, page);
    final number = page.pageNumber;
    final data = study.pageIfLoaded(number);
    if (data == null) study.pageData(number);
    final palette = ReaderColors.of(context);
    final edit = study.editing;
    return [
      IgnorePointer(
        child: CustomPaint(
          size: pageRect.size,
          painter: _MarksPainter(
            scale: s,
            pageWidth: page.width,
            highlights: [
              for (final h in study.highlights)
                if (h.page == number) h,
            ],
            answers: [
              for (final a in study.answers)
                if (a.page == number && !(edit != null && edit.place.key('') == a.place.key(''))) a,
            ],
            hovered: hovered?.$1 == number ? hovered!.$2 : null,
            bookmarked: study.bookmarkOn(number) != null,
            palette: palette,
          ),
        ),
      ),
      if (edit != null && edit.place.page == number) _editor(edit, s),
    ];
  }

  Widget _editor(AnswerEdit e, double s) {
    final r = _answerRect(e.place);
    final size = e.place.size * s;
    final lineHeight = e.place.pitch > 0 ? e.place.pitch * s : null;
    final style = TextStyle(
      color: answerInk,
      fontSize: size,
      height: lineHeight == null ? 1.2 : lineHeight / size,
      fontFamily: 'sans-serif',
    );
    return Positioned(
      left: r.left * s,
      top: r.top * s,
      width: r.width * s,
      height: r.height * s,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.tab): _NextBlankIntent(1),
          SingleActivator(LogicalKeyboardKey.tab, shift: true): _NextBlankIntent(-1),
          SingleActivator(LogicalKeyboardKey.escape): _DoneIntent(),
          SingleActivator(LogicalKeyboardKey.equal, control: true): _SizeIntent(1),
          SingleActivator(LogicalKeyboardKey.minus, control: true): _SizeIntent(-1),
        },
        child: Actions(
          actions: {
            _NextBlankIntent: CallbackAction<_NextBlankIntent>(onInvoke: (i) => _nextBlank(i.delta)),
            _DoneIntent: CallbackAction<_DoneIntent>(
              onInvoke: (_) {
                _finishAnswer();
                focus.requestFocus();
                return null;
              },
            ),
            _SizeIntent: CallbackAction<_SizeIntent>(
              onInvoke: (i) {
                final now = study.editing;
                if (now == null) return null;
                final p = now.place;
                final bigger = AnswerPlace(
                  page: p.page,
                  kind: p.kind,
                  x: p.x,
                  y: p.y,
                  w: p.w,
                  h: p.h,
                  pitch: p.pitch,
                  lines: p.lines,
                  indent: p.indent,
                  size: (p.size + i.delta).clamp(6, 24),
                );
                study.startAnswer(AnswerEdit(place: bigger, context: now.context, ordinal: now.ordinal));
                study.keepAnswer(answer.text);
                return null;
              },
            ),
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              border: Border.all(color: answerInk.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: TextField(
              controller: answer,
              focusNode: answerFocus,
              style: style,
              cursorColor: answerInk,
              maxLines: e.place.lines > 1 || e.place.kind == 'box' ? null : 1,
              expands: e.place.lines > 1 || e.place.kind == 'box',
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              onSubmitted: (_) => _nextBlank(1),
              textInputAction: e.place.lines > 1 || e.place.kind == 'box'
                  ? TextInputAction.newline
                  : TextInputAction.next,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ----- selection bar -----

  Widget? _contextMenu(BuildContext context, PdfViewerContextMenuBuilderParams params) {
    if (params.contextMenuFor != PdfViewerPart.selectedText) return null;
    final p = ReaderColors.of(context);
    final locked = study.readOnly;
    return Positioned(
      left: math.max(8, params.anchorA.dx - 20),
      top: math.max(8, params.anchorA.dy - 56),
      child: Material(
        elevation: 4,
        color: p.raised,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!locked)
                for (final (i, c) in studyColors.indexed)
                  IconButton(
                    tooltip: widget.touch ? c : '$c (${i + 1})',
                    icon: Icon(Icons.circle, color: p.swatch(c), size: 22),
                    onPressed: () {
                      params.dismissContextMenu();
                      highlightSelection(color: c);
                    },
                  ),
              if (!locked)
                IconButton(
                  tooltip: widget.touch ? 'Highlight with a note' : 'Highlight with a note (a)',
                  icon: const Icon(Icons.sticky_note_2_outlined, size: 20),
                  onPressed: () {
                    params.dismissContextMenu();
                    highlightSelection(note: true);
                  },
                ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () {
                  params.textSelectionDelegate.copyTextSelection();
                  params.dismissContextMenu();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- keys -----

  void _scrollBy(double dy) {
    if (!pdf.isReady) return;
    pdf.goToPosition(documentOffset: pdf.centerPosition.translate(0, dy / pdf.currentZoom));
  }

  void _page(int delta) {
    final to = (study.page + delta).clamp(1, pdf.isReady ? pdf.pageCount : 1);
    _goTo(to);
  }

  Future<void> goToPageDialog() async {
    if (!pdf.isReady) return;
    final c = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1–${pdf.pageCount}'),
          onSubmitted: (v) => Navigator.pop(d, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text.trim())), child: const Text('Go')),
        ],
      ),
    );
    c.dispose();
    if (n != null && n >= 1 && n <= pdf.pageCount) _goTo(n);
    focus.requestFocus();
  }

  void openSearch() {
    setState(() => searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => searchFocus.requestFocus());
  }

  void _closeSearch() {
    searcher.resetTextSearch();
    setState(() => searching = false);
    focus.requestFocus();
  }

  void fitWidth() {
    final m = pdf.calcMatrixFitWidthForPage(pageNumber: study.page);
    if (m != null) pdf.goTo(m);
  }

  Map<ShortcutActivator, VoidCallback> get _keys => {
    for (final (i, c) in studyColors.indexed)
      SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i)): () => highlightSelection(color: c),
    const SingleActivator(LogicalKeyboardKey.keyA): () => highlightSelection(note: true),
    const SingleActivator(LogicalKeyboardKey.keyH, control: true): () => highlightSelection(note: true),
    const SingleActivator(LogicalKeyboardKey.keyB): () => study.readOnly ? null : study.toggleBookmark(study.page),
    const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
        study.readOnly ? null : study.toggleBookmark(study.page),
    const SingleActivator(LogicalKeyboardKey.keyI): _answerFirstInView,
    const SingleActivator(LogicalKeyboardKey.keyJ): () => _scrollBy(60),
    const SingleActivator(LogicalKeyboardKey.keyK): () => _scrollBy(-60),
    const SingleActivator(LogicalKeyboardKey.keyJ, shift: true): () => _page(1),
    const SingleActivator(LogicalKeyboardKey.keyK, shift: true): () => _page(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _page(1),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _page(-1),
    const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () => _page(1),
    const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () => _page(-1),
    const SingleActivator(LogicalKeyboardKey.keyG): () => _goTo(1),
    const SingleActivator(LogicalKeyboardKey.keyG, shift: true): () => _goTo(pdf.isReady ? pdf.pageCount : 1),
    const SingleActivator(LogicalKeyboardKey.home): () => _goTo(1),
    const SingleActivator(LogicalKeyboardKey.end): () => _goTo(pdf.isReady ? pdf.pageCount : 1),
    const SingleActivator(LogicalKeyboardKey.equal): () => pdf.zoomUp(),
    const SingleActivator(LogicalKeyboardKey.equal, shift: true): () => pdf.zoomUp(),
    const SingleActivator(LogicalKeyboardKey.minus): () => pdf.zoomDown(),
    const SingleActivator(LogicalKeyboardKey.digit0): fitWidth,
    const SingleActivator(LogicalKeyboardKey.equal, control: true): () => pdf.zoomUp(),
    const SingleActivator(LogicalKeyboardKey.minus, control: true): () => pdf.zoomDown(),
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): fitWidth,
    const SingleActivator(LogicalKeyboardKey.keyG, control: true): goToPageDialog,
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): openSearch,
    const SingleActivator(LogicalKeyboardKey.slash): openSearch,
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => widget.onExport?.call(),
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => widget.onNewNote?.call(),
    for (final (i, panel) in StudyPanel.values.indexed)
      SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () =>
          study.setPanel(panel),
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (searching) return _closeSearch();
      pdf.textSelectionDelegate.clearTextSelection();
    },
  };

  /// The keys the reader answers to, for the shortcuts list.
  static const keyList = [
    ('Highlight the selection (yellow, green, blue, pink, purple)', '1–5'),
    ('Highlight the selection and write a note', 'a, Ctrl+H'),
    ('Bookmark the page, or remove its bookmark', 'b, Ctrl+D'),
    ('Answer the first empty line in view', 'i'),
    ('Next or previous answer line (while answering)', 'Tab, Shift+Tab'),
    ('Answer text bigger or smaller (while answering)', 'Ctrl+=, Ctrl+−'),
    ('Done answering', 'Esc'),
    ('Scroll', 'j, k'),
    ('Next or previous page', 'J, K, Alt+→, Alt+←'),
    ('First or last page', 'g, G, Home, End'),
    ('Zoom in, out, fit width', '+, −, 0'),
    ('Go to a page', 'Ctrl+G'),
    ('Search in this book', 'Ctrl+F, /'),
    ('Export this run to Markdown', 'Ctrl+E'),
    ('New book note', 'Ctrl+N'),
    ('Contents, Highlights, Bookmarks, Answers, Notes', 'Ctrl+1 … Ctrl+5'),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: study, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final doc = study.document;
    final palette = ReaderColors.of(context);
    if (study.problem != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(study.problem!)),
      );
    }
    if (doc == null) return const Center(child: CircularProgressIndicator());
    final view = study.run == null ? null : study.store.view(study.run!.id);
    final viewer = PdfViewer(
      PdfDocumentRefDirect(doc),
      controller: pdf,
      params: PdfViewerParams(
        backgroundColor: palette.isDark
            ? mix(palette.background, Colors.black, 0.2)
            : mix(palette.background, palette.foreground, 0.06),
        margin: 12,
        textSelectionParams: PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: true,
          onTextSelectionChange: (_) {},
        ),
        buildContextMenu: _contextMenu,
        pageOverlaysBuilder: _overlays,
        pagePaintCallbacks: [searcher.pageTextMatchPaintCallback],
        onGeneralTap: _onTap,
        calculateInitialPageNumber: (document, controller) =>
            (view?.page ?? study.page).clamp(1, document.pages.length),
        onViewerReady: (document, controller) {
          study.page = controller.pageNumber ?? study.page;
          final z = view?.zoom;
          if (z != null && z > 0 && (z - controller.currentZoom).abs() > 0.01) {
            controller.setZoom(controller.centerPosition, z, duration: Duration.zero);
          }
        },
        onPageChanged: (n) {
          if (n == null) return;
          study.rememberView(n, zoom: pdf.isReady ? pdf.currentZoom : 1);
          study.pageData(n);
          if (n + 1 <= doc.pages.length) study.pageData(n + 1);
        },
      ),
    );
    return CallbackShortcuts(
      bindings: _keys,
      child: Focus(
        focusNode: focus,
        autofocus: !widget.touch,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (study.readOnly)
              MaterialBanner(
                content: Text('${study.run?.name ?? 'This run'} is finished: you can read it, not change it.'),
                actions: const [SizedBox.shrink()],
              ),
            if (searching) _searchBar(palette),
            Expanded(
              child: MouseRegion(onHover: _hover, child: viewer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(Palette p) {
    final n = searcher.matches.length;
    final at = searcher.currentIndex;
    return Container(
      color: p.card,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => searcher.goToPrevMatch(),
                const SingleActivator(LogicalKeyboardKey.f3): () => searcher.goToNextMatch(),
                const SingleActivator(LogicalKeyboardKey.f3, shift: true): () => searcher.goToPrevMatch(),
              },
              child: TextField(
                controller: search,
                focusNode: searchFocus,
                decoration: const InputDecoration(
                  hintText: 'Search in this book',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: (q) => q.trim().isEmpty ? searcher.resetTextSearch() : searcher.startTextSearch(q.trim()),
                onSubmitted: (_) {
                  searcher.goToNextMatch();
                  searchFocus.requestFocus();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(n == 0 ? (search.text.trim().isEmpty ? '' : 'No matches') : '${(at ?? 0) + 1} of $n'),
          IconButton(
            tooltip: 'Previous (Shift+Enter)',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: n == 0 ? null : () => searcher.goToPrevMatch(),
          ),
          IconButton(
            tooltip: 'Next (Enter)',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: n == 0 ? null : () => searcher.goToNextMatch(),
          ),
          IconButton(tooltip: 'Close (Esc)', icon: const Icon(Icons.close), onPressed: _closeSearch),
        ],
      ),
    );
  }
}

class _NextBlankIntent extends Intent {
  const _NextBlankIntent(this.delta);
  final int delta;
}

class _DoneIntent extends Intent {
  const _DoneIntent();
}

class _SizeIntent extends Intent {
  const _SizeIntent(this.delta);
  final double delta;
}

/// Paints one page's marks: highlights like a marker over the print, note markers in the margin, answers in blue ink
/// on their lines, the empty line under the pointer lit up, and a folded corner on a bookmarked page.
class _MarksPainter extends CustomPainter {
  _MarksPainter({
    required this.scale,
    required this.pageWidth,
    required this.highlights,
    required this.answers,
    required this.hovered,
    required this.bookmarked,
    required this.palette,
  });
  final double scale, pageWidth;
  final List<DocHighlight> highlights;
  final List<Answer> answers;
  final Rule? hovered;
  final bool bookmarked;
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale;
    for (final h in highlights) {
      final paint = Paint()
        ..color = palette.swatch(h.color).withValues(alpha: 0.38)
        ..blendMode = BlendMode.multiply;
      for (final r in h.rects) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r.x * s, (r.y - 1) * s, r.w * s, (r.h + 2) * s),
            Radius.circular(2 * s),
          ),
          paint,
        );
      }
      if (h.note != null && h.rects.isNotEmpty) {
        final r = h.rects.first;
        final c = Offset(math.max(6, r.x - 9) * s, (r.y + r.h / 2) * s);
        canvas.drawCircle(c, 3.2 * s, Paint()..color = palette.swatch(h.color));
      }
    }
    final hv = hovered;
    if (hv != null) {
      final paint = Paint()..color = answerInk.withValues(alpha: 0.10);
      final above = math.min(hv.space, 18.0);
      canvas.drawRect(Rect.fromLTWH(hv.x * s, (hv.y - above) * s, hv.w * s, (above + 1.5) * s), paint);
      canvas.drawLine(
        Offset(hv.x * s, hv.y * s),
        Offset((hv.x + hv.w) * s, hv.y * s),
        Paint()
          ..color = answerInk.withValues(alpha: 0.6)
          ..strokeWidth = 1.2,
      );
    }
    for (final a in answers) {
      _paintAnswer(canvas, a);
    }
    if (bookmarked) {
      final w = size.width;
      final d = 22 * s;
      final path = Path()
        ..moveTo(w - d, 0)
        ..lineTo(w, 0)
        ..lineTo(w, d)
        ..close();
      canvas.drawPath(path, Paint()..color = palette.accent);
    }
  }

  void _paintAnswer(Canvas canvas, Answer a) {
    final p = a.place;
    final s = scale;
    if (p.kind == 'box') {
      final rect = Rect.fromLTWH(p.x * s, p.y * s, p.w * s, math.max(p.h, 14) * s);
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = answerInk.withValues(alpha: 0.25),
      );
      final tp = _painter(a.text, p.size * s, rect.width - 4 * s, null);
      tp.paint(canvas, rect.topLeft + Offset(2 * s, 1 * s));
      return;
    }
    final left = (p.x + p.indent) * s;
    final width = (p.w - p.indent) * s;
    if (p.lines > 1 && p.pitch > 0) {
      // Ruled lines: the text wraps from line to line, sitting on each.
      var size = p.size * s;
      TextPainter tp;
      do {
        tp = _painter(a.text, size, width, p.pitch * s);
        if (tp.height <= p.lines * p.pitch * s + 1 || size <= 6 * s) break;
        size *= 0.92;
      } while (true);
      tp.paint(canvas, Offset(left, (p.y - p.pitch + 1.5) * s));
      return;
    }
    // One line: shrink a long answer to fit its blank.
    var size = p.size * s;
    TextPainter tp;
    do {
      tp = _painter(a.text.replaceAll('\n', ' '), size, double.infinity, null);
      if (tp.width <= width || size <= 6 * s) break;
      size *= 0.92;
    } while (true);
    tp.paint(canvas, Offset(left + 1 * s, p.y * s - tp.height + 1.5 * s));
  }

  static TextPainter _painter(String text, double size, double width, double? lineHeight) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: answerInk,
          fontSize: size,
          height: lineHeight == null ? 1.15 : lineHeight / size,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: width.isFinite ? math.max(1, width) : double.infinity);
    return tp;
  }

  @override
  bool shouldRepaint(covariant _MarksPainter old) => true;
}
