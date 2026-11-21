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
import 'study_actions.dart' show exportAllRuns;
import 'study_runs.dart';

/// The ink answers are written in: blue, so they read as filled in rather than printed (as in Dogear).
const answerInk = Color(0xFF1F4FA8);

/// A Study book's pages, with the run's highlights, bookmarks and answers drawn on them.
///
/// Desktop keys (when the page has focus, not while typing): 1–5 highlight the selection in that colour, `a` (or
/// Ctrl+H) highlights it and asks for a note, `b` (or Ctrl+D) bookmarks the page, `i` answers the first empty line in
/// view, `j`/`k` scroll, `J`/`K` and Alt+→/Alt+← turn pages, `g`/`G` go to the first or last page, `+`/`-`/`0` zoom,
/// Ctrl+G goes to a page, Ctrl+F or `/` searches.
class StudyReader extends StatefulWidget {
  const StudyReader({
    super.key,
    required this.study,
    this.touch = false,
    this.onExport,
    this.onNewNote,
    this.showRun,
    this.follow,
  });
  final StudyController study;

  /// The compare pane: shows this run's marks, read-only, scrolled with [follow] (the main reader's view).
  final StudyRun? showRun;
  final PdfViewerController? follow;

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

  /// A compare pane: another run's marks, read-only, following the main reader.
  bool get _mirror => widget.showRun != null;
  String? get _runId => widget.showRun?.id ?? study.run?.id;
  bool get _readOnly => _mirror || study.readOnly;
  String? get _docId => study.book?.docId;
  List<DocHighlight> get _highlights => _runId == null
      ? const []
      : [
          for (final h in study.store.highlights(_runId!))
            if (h.docId == _docId) h,
        ];
  List<Answer> get _answers => _runId == null
      ? const []
      : [
          for (final a in study.store.answers(_runId!))
            if (a.docId == _docId) a,
        ];
  bool _bookmarked(int page) =>
      _runId != null && study.book != null && study.store.bookmarkOn(_runId!, study.book!.docId, page) != null;

  /// Every run's answers by question blank, worked out once per build (for the history marks).
  Map<String, List<(StudyRun, Answer)>> _bySlot = const {};

  /// Comparing in a second pane beside this one (wide windows); otherwise the other run's answers are drawn faintly
  /// under this run's.
  bool _sideBySide = false;

  /// History marks on [page]: where an answer of this question exists in another time through (a box in points, how
  /// many other runs answered it, and its question).
  List<({Rect at, int count, String slotKey})> _chips(int page) {
    if (_bySlot.isEmpty) return const [];
    final runId = _runId;
    final out = <({Rect at, int count, String slotKey})>[];
    final seen = <String>{};
    void add(Answer a) {
      if (a.page != page || a.docId != _docId || !seen.add(a.slotKey)) return;
      final others = (_bySlot[a.slotKey] ?? const []).where((e) => e.$1.id != runId).length;
      if (others == 0) return;
      final r = _answerRect(a.place);
      // Beside a block of ruled lines or a box; above the end of a one-line blank, clear of the words after it.
      final at = a.place.lines > 1 || a.place.kind == 'box'
          ? Rect.fromLTWH(r.right + 2, r.bottom - 11, 20, 10)
          : Rect.fromLTWH(r.right - 16, r.top - 9, 18, 9);
      out.add((at: at, count: others, slotKey: a.slotKey));
    }

    for (final a in _answers) {
      add(a);
    }
    for (final list in _bySlot.values) {
      for (final (_, a) in list) {
        add(a);
      }
    }
    return out;
  }

  void _follow() {
    final f = widget.follow;
    if (f != null && f.isReady && pdf.isReady && pdf.value != f.value) pdf.value = f.value;
  }

  @override
  void initState() {
    super.initState();
    widget.follow?.addListener(_follow);
    if (_mirror) return;
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
    widget.follow?.removeListener(_follow);
    if (!_mirror && study.editing != null) study.finishAnswer(answer.text);
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
    if (_readOnly) return;
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
    final locked = _readOnly;
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
    if (_readOnly) return;
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
    if (study.placing != null) {
      // Placing an answer brought from another edition: it goes here, with this edition's question.
      study.place(place, context: context, ordinal: ordinal);
      return;
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
    // A history mark: this question's answers in every time through.
    for (final c in _chips(page.pageNumber)) {
      if (c.at.inflate(3).contains(at)) {
        showAnswerHistory(context, study, c.slotKey);
        return true;
      }
    }
    final data = study.pageIfLoaded(page.pageNumber);
    if (data == null) {
      study.pageData(page.pageNumber);
      return false;
    }
    final type = d.type;
    if (type == PdfViewerGeneralTapType.tap || type == PdfViewerGeneralTapType.secondaryTap) {
      // A highlight under the pointer.
      for (final h in _highlights.reversed) {
        if (h.page == page.pageNumber && h.rects.any((r) => _inflate(r, 1.5).contains(at))) {
          _highlightMenu(h);
          return true;
        }
      }
      // An answer box or line.
      for (final a in _answers) {
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
        !_readOnly &&
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
    if (_readOnly) return;
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
    if (widget.touch || _readOnly) return;
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
            font: TextStyle(
              fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
              fontFamilyFallback: Theme.of(context).textTheme.bodyMedium?.fontFamilyFallback,
            ),
            scale: s,
            pageWidth: page.width,
            highlights: [
              for (final h in _highlights)
                if (h.page == number) h,
            ],
            answers: [
              for (final a in _answers)
                if (a.page == number && !(edit != null && !_mirror && edit.place.key('') == a.place.key(''))) a,
            ],
            hovered: hovered?.$1 == number ? hovered!.$2 : null,
            bookmarked: _bookmarked(number),
            palette: palette,
            ghosts: [
              if (!_mirror && study.compare != null && !_sideBySide)
                for (final a in study.store.answers(study.compare!.id))
                  if (a.page == number && a.docId == _docId) a,
            ],
            chips: _mirror ? const [] : _chips(number),
          ),
        ),
      ),
      if (!_mirror && edit != null && edit.place.page == number) _editor(edit, s),
    ];
  }

  Widget _editor(AnswerEdit e, double s) {
    final r = _answerRect(e.place);
    final size = e.place.size * s;
    final lineHeight = e.place.pitch > 0 ? e.place.pitch * s : null;
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final style = TextStyle(
      color: answerInk,
      fontSize: size,
      height: lineHeight == null ? 1.2 : lineHeight / size,
      fontFamily: base.fontFamily,
      fontFamilyFallback: base.fontFamilyFallback,
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
    final locked = _readOnly;
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
    const SingleActivator(LogicalKeyboardKey.keyB): () => _readOnly ? null : study.toggleBookmark(study.page),
    const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
        _readOnly ? null : study.toggleBookmark(study.page),
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
    const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true): () => exportAllRuns(context, study),
    const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): () => startNewRunDialog(context, study),
    const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true): toggleCompare,
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
    ('Export every time through to one Markdown file', 'Ctrl+Shift+E'),
    ('Start a new time through the book', 'Ctrl+Shift+N'),
    ('Compare with another time through, or stop', 'Ctrl+Shift+V'),
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
    final book = study.book;
    _bySlot = book == null || study.runs.length < 2
        ? const {}
        : {for (final q in study.store.questions(book)) q.slotKey: q.answers};
    final view = study.run == null ? null : study.store.view(study.run!.id);
    final viewer = PdfViewer(
      PdfDocumentRefDirect(doc, autoDispose: false), // StudyController owns and closes it
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
            (study.jump?.$1 ?? view?.page ?? study.page).clamp(1, document.pages.length),
        onViewerReady: (document, controller) {
          if (_mirror) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
            return;
          }
          study.page = controller.pageNumber ?? study.page;
          final jump = study.jump;
          if (jump != null) {
            study.jump = null;
            WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(jump.$1, y: jump.$2));
            return;
          }
          final z = view?.zoom;
          if (z != null && z > 0 && (z - controller.currentZoom).abs() > 0.01) {
            controller.setZoom(controller.centerPosition, z, duration: Duration.zero);
          }
        },
        onPageChanged: (n) {
          if (n == null || _mirror) return;
          study.rememberView(n, zoom: pdf.isReady ? pdf.currentZoom : 1);
          study.pageData(n);
          if (n + 1 <= doc.pages.length) study.pageData(n + 1);
        },
      ),
    );
    if (_mirror) {
      // The compare pane: a label, and the pages following the main reader (it takes no input of its own).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: palette.card,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '${widget.showRun!.name} · read-only',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.dim),
            ),
          ),
          Expanded(child: IgnorePointer(child: viewer)),
        ],
      );
    }
    final run = study.run;
    final compare = study.compare;
    return CallbackShortcuts(
      bindings: _keys,
      child: Focus(
        focusNode: focus,
        autofocus: !widget.touch,
        child: LayoutBuilder(
          builder: (context, box) {
            final side = compare != null && box.maxWidth >= 1000;
            if (side != _sideBySide) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _sideBySide = side);
              });
            }
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (study.placing != null)
                  MaterialBanner(
                    content: Text(
                      'Tap the line (or an empty spot, with a long press) where this answer goes: '
                      '“${_short(study.placing!.text)}”',
                    ),
                    actions: [TextButton(onPressed: () => study.startPlacing(null), child: const Text('Cancel'))],
                  )
                else if (_unplacedCount > 0)
                  MaterialBanner(
                    content: Text(
                      '$_unplacedCount mark${_unplacedCount == 1 ? '' : 's'} from the other edition could not be '
                      'found in this one and ${_unplacedCount == 1 ? 'is' : 'are'} not placed yet.',
                    ),
                    actions: [TextButton(onPressed: () => showUnplaced(context, study), child: const Text('Show'))],
                  ),
                if (run != null && !study.onCurrentRun)
                  MaterialBanner(
                    content: Text(
                      study.readOnly
                          ? 'You are looking at “${run.name}”, an earlier time through. It is finished, so it can be '
                                'read but not changed.'
                          : '“${run.name}” is unlocked until you close the book: changes go into that time through.',
                    ),
                    actions: [
                      if (study.readOnly) TextButton(onPressed: _unlock, child: const Text('Unlock')),
                      TextButton(onPressed: study.backToCurrent, child: const Text('Back to the current one')),
                    ],
                  ),
                if (compare != null)
                  MaterialBanner(
                    content: Text(
                      side
                          ? 'Comparing with “${compare.name}”, shown on the right.'
                          : 'Comparing with “${compare.name}”: its answers are shown in grey under yours.',
                    ),
                    actions: [TextButton(onPressed: () => study.setCompare(null), child: const Text('Stop comparing'))],
                  ),
                if (searching) _searchBar(palette),
                Expanded(
                  child: MouseRegion(onHover: _hover, child: viewer),
                ),
              ],
            );
            if (!side) return main;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: main),
                VerticalDivider(width: 1, color: palette.selection),
                Expanded(
                  child: StudyReader(
                    key: ValueKey('compare:${compare.id}'),
                    study: study,
                    showRun: compare,
                    follow: pdf,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _unlock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Unlock “${study.run?.name}”?'),
        content: const Text(
          'Changes will go into this earlier time through until you close the book; then it is locked again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Unlock')),
        ],
      ),
    );
    if (ok == true) study.unlockRun();
  }

  int get _unplacedCount {
    if (_mirror) return 0;
    final u = study.unplaced;
    return u.highlights.length + u.answers.length + u.bookmarks.length;
  }

  static String _short(String s) => s.length <= 60 ? s : '${s.substring(0, 59)}…';

  /// Ctrl+Shift+V: compare with the latest other time through, or stop comparing.
  void toggleCompare() {
    if (study.compare != null) return study.setCompare(null);
    final others = [
      for (final r in study.runs.reversed)
        if (r.id != study.run?.id) r,
    ];
    if (others.isNotEmpty) study.setCompare(others.first);
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
    this.font = const TextStyle(),
    this.ghosts = const [],
    this.chips = const [],
  });
  final double scale, pageWidth;
  final List<DocHighlight> highlights;
  final List<Answer> answers;
  final Rule? hovered;
  final bool bookmarked;
  final Palette palette;

  /// The interface font (family and fallbacks) answers are written in, as the rest of the app's own text.
  final TextStyle font;

  /// Another run's answers, drawn faintly just under the lines (comparing on a narrow screen).
  final List<Answer> ghosts;

  /// Marks where a question was answered in another time through.
  final List<({Rect at, int count, String slotKey})> chips;

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
        // In the page's margin, beside the highlight's first line.
        final c = Offset(math.min(14, math.max(6, r.x - 12)) * s, (r.y + r.h / 2) * s);
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
    for (final a in ghosts) {
      _paintGhost(canvas, a);
    }
    for (final a in answers) {
      _paintAnswer(canvas, a);
    }
    for (final c in chips) {
      final r = Rect.fromLTWH(c.at.left * s, c.at.top * s, c.at.width * s, c.at.height * s);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(3 * s)),
        Paint()..color = palette.accent.withValues(alpha: 0.85),
      );
      final tp = _painter('↺${c.count}', 7.5 * s, double.infinity, null, color: Colors.white);
      tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
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

  /// An answer from the run being compared: grey, small, just under its line (one line, shrunk to fit a short blank).
  void _paintGhost(Canvas canvas, Answer a) {
    final p = a.place;
    final s = scale;
    const grey = Color(0xFF7A7A7A);
    final width = math.max(1.0, (p.w - p.indent) * s);
    final oneLine = p.kind == 'line' && p.lines <= 1;
    var size = math.max(6.0, p.size * 0.8) * s;
    TextPainter tp;
    do {
      tp = oneLine
          ? _painter(a.text.replaceAll('\n', ' '), size, double.infinity, null, color: grey)
          : _painter(a.text, size, width, null, color: grey);
      if (!oneLine || tp.width <= width || size <= 5 * s) break;
      size *= 0.92;
    } while (true);
    final top = p.kind == 'box' ? (p.y + math.max(p.h, 14) + 1) : (p.y + (p.lines - 1) * p.pitch + 1.5);
    canvas.save();
    if (oneLine) canvas.clipRect(Rect.fromLTWH((p.x + p.indent) * s, top * s, width, tp.height));
    tp.paint(canvas, Offset((p.x + p.indent) * s, top * s));
    canvas.restore();
  }

  TextPainter _painter(String text, double size, double width, double? lineHeight, {Color color = answerInk}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: font.copyWith(color: color, fontSize: size, height: lineHeight == null ? 1.15 : lineHeight / size),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: width.isFinite ? math.max(1, width) : double.infinity);
    return tp;
  }

  @override
  bool shouldRepaint(covariant _MarksPainter old) => true;
}
