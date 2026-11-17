import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../../core/library/passage.dart';
import '../../core/search/fold.dart';
import '../../core/search/search_index.dart';
import 'shell_model.dart';
import 'widgets.dart';

/// Ctrl+K: search everything, or only the open book, as the GTK app's Search dialog. Results are grouped by book (or
/// prayer category); Enter opens the first, ↓ moves into the list, Esc closes.
Future<void> showFinder(BuildContext context, ShellModel model) => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _Finder(model: model),
    );

class _Finder extends StatefulWidget {
  const _Finder({required this.model});
  final ShellModel model;

  @override
  State<_Finder> createState() => _FinderState();
}

class _FinderState extends State<_Finder> {
  static const shown = 60;
  final entry = TextEditingController();
  final firstResult = FocusNode();
  SearchIndex? index;
  Timer? _debounce;
  bool everything = true;
  List<Passage> found = const [];
  int bookCount = 0, total = 0;
  String text = '';

  /// What "This book" means for the passage on show: its book, or all the prayers.
  late final (String, bool Function(Passage))? scope = () {
    final p = widget.model.current;
    if (p == null) return null;
    final book = bookOf(p);
    if (book != null) return (book, (Passage q) => bookOf(q) == book);
    if (p.isPrayer) return ('Prayers', (Passage q) => q.isPrayer);
    return null;
  }();

  @override
  void initState() {
    super.initState();
    AppScope.read(context).searchIndex().then((i) {
      if (!mounted) return;
      setState(() => index = i);
      _run();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    entry.dispose();
    firstResult.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _run);
  }

  void _run() {
    final i = index;
    if (i == null) return;
    final t = entry.text.trim();
    final all = t.isEmpty ? const <Passage>[] : i.search(t, limit: 1 << 30);
    final s = scope;
    final inBook = s == null ? const <Passage>[] : all.where(s.$2).toList();
    setState(() {
      text = t;
      total = all.length;
      bookCount = inBook.length;
      found = everything || s == null ? all : inBook;
    });
  }

  void _open(Passage p) {
    final state = AppScope.read(context);
    final folder = state.folder!;
    final span = folder.find(p.text, folder.fold(text));
    Navigator.pop(context);
    widget.model.openPassage(p, found: span);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final palette = ReaderColors.of(context);
    final folder = state.folder!;
    final query = folder.fold(text);
    final s = scope;
    final rows = <Widget>[];
    String? lastPlace;
    for (var n = 0; n < found.length && n < shown; n++) {
      final p = found[n];
      final place = placeOf(p);
      if (place != lastPlace) {
        rows.add(Padding(
          padding: EdgeInsets.fromLTRB(10, lastPlace == null ? 2 : 10, 10, 2),
          child: Text(place, style: dimStyle(context).copyWith(fontWeight: FontWeight.w700)),
        ));
        lastPlace = place;
      }
      final (before, match, after) = snippet(p.text, folder.find(p.text, query));
      final name = p.isPrayer ? listTitle(p) : heading(p);
      rows.add(SideRow(
        onTap: () => _open(p),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Focus(
          focusNode: n == 0 ? firstResult : null,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.space)) {
              _open(p);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return Container(
              color: focused ? palette.selection : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: before),
                    TextSpan(text: match, style: TextStyle(fontWeight: FontWeight.w700, color: palette.foreground)),
                    TextSpan(text: after),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dimStyle(context),
                ),
              ]),
            );
          }),
        ),
      ));
    }
    final status = index == null
        ? 'Preparing search…'
        : text.isEmpty
            ? 'Type a word or phrase. ↓ moves into the results, Enter opens one, Esc closes.'
            : found.isEmpty
                ? 'No passages match “$text”.'
                : '${found.length} passage${found.length == 1 ? '' : 's'}'
                    '${found.length > shown ? '; the first $shown are listed. Add a word to narrow them.' : '.'}';

    Widget pill(String label, bool active, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: active ? palette.foreground.withValues(alpha: 0.2) : palette.foreground.withValues(alpha: 0.07),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: Text(label),
          ),
        );

    return Dialog(
      backgroundColor: palette.raised,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              if (!firstResult.hasFocus) firstResult.requestFocus();
            },
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: HeaderBar.height,
              child: Stack(alignment: Alignment.center, children: [
                const Text('Search', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                Positioned(
                  right: 8,
                  child: HeaderButton(icon: Icons.close, tooltip: 'Close', onPressed: () => Navigator.pop(context)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: TextField(
                controller: entry,
                autofocus: true,
                onChanged: _changed,
                onSubmitted: (_) {
                  _run();
                  if (found.isNotEmpty) _open(found.first);
                },
                decoration: const InputDecoration(
                  hintText: 'Search the texts…',
                  prefixIcon: Icon(Icons.search, size: 20),
                  contentPadding: EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(children: [
                if (s != null)
                  Tooltip(
                    message: 'Only ${s.$1}',
                    child: pill(text.isEmpty ? 'This book' : 'This book · $bookCount', !everything, () {
                      everything = false;
                      _run();
                    }),
                  ),
                pill(text.isEmpty ? 'Everything' : 'Everything · $total', everything || s == null, () {
                  everything = true;
                  _run();
                }),
                Expanded(
                  child: Text('Ignores accents and apostrophes · offline',
                      textAlign: TextAlign.right, maxLines: 2, style: dimStyle(context)),
                ),
              ]),
            ),
            const Divider(),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(6, 6, 6, 6), children: rows),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Text(status, style: dimStyle(context)),
            ),
          ]),
        ),
      ),
    );
  }
}
