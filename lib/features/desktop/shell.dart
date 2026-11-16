import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../about/about_screen.dart';
import '../settings/settings_screen.dart';
import '../../core/calendar/badi.dart';
import '../../core/calendar/today.dart';
import '../today/counter_view.dart';
import 'finder.dart';
import '../today/location_dialog.dart';
import '../today/today_view.dart';
import 'highlights_view.dart';
import 'home_view.dart';
import 'section_welcome.dart';
import 'reading_view.dart';
import 'shell_model.dart';
import 'sidebar.dart';
import 'widgets.dart';

/// Below this width the sidebar and the content take turns, as in the GTK app.
const narrowWidth = 700.0;

/// The desktop window, laid out as the GTK app's libadwaita window: a sidebar with Home, Prayers, Writings and Saved
/// (and the open section's contents), and the content beside it under its own header bar.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.state, this.openId});
  final AppState state;

  /// A passage to open once the library is ready.
  final String? openId;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  late final ShellModel model = ShellModel(widget.state);
  final reading = GlobalKey<ReadingViewState>();
  late int _language = widget.state.settings.language;
  late int _saved = widget.state.settings.saved.length;
  StreamSubscription<String>? _opens;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_appChanged);
    _opens = widget.state.openRequests.listen(_openFromNotification);
    final id = widget.openId;
    if (id != null) {
      widget.state.marksReady.then((_) {
        final p = widget.state.passageOf(id);
        if (p != null && mounted) model.openPassage(p);
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_appChanged);
    _opens?.cancel();
    model.dispose();
    super.dispose();
  }

  void _appChanged() {
    final s = widget.state;
    if (s.settings.language != _language && !s.loading) {
      _language = s.settings.language;
      model.languageChanged();
    }
    if (s.settings.saved.length != _saved) {
      _saved = s.settings.saved.length;
      model.savedChanged();
    }
  }

  /// A reminder's "Open": its obligatory prayer, or Today.
  void _openFromNotification(String target) {
    final name = target.startsWith('prayer:') ? target.substring(7) : null;
    final item = name != null && prayerNames.containsKey(name) ? widget.state.todayContext()?.prayerItem(name) : null;
    if (item != null) {
      model.openObligatory(item);
    } else {
      model.navigate(Section.today);
    }
  }

  void _toggleSaved() {
    final p = model.current;
    if (p != null) widget.state.toggleSaved(p);
  }

  Future<void> _dialog(Widget page) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640), child: page),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final state = AppScope.of(context);
        if (state.error != null) {
          return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(state.error!))));
        }
        if (state.loading || state.library == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < narrowWidth;
          final content = _content(context, state, narrow);
          final sidebar = Sidebar(model: model, onSearch: () => showFinder(context, model), onAction: (r) => _act(context, r));
          Widget body;
          if (narrow) {
            body = model.showContent || model.focusMode ? content : sidebar;
          } else {
            final width = (box.maxWidth * 0.26).clamp(240.0, 340.0);
            body = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (model.sidebarShown && !model.focusMode) ...[
                SizedBox(width: width, child: sidebar),
                VerticalDivider(width: 1, thickness: 1, color: ReaderColors.of(context).selection),
              ],
              Expanded(child: content),
            ]);
          }
          return Scaffold(
            body: CallbackShortcuts(
              bindings: _keys(context, narrow),
              child: Focus(autofocus: true, child: body),
            ),
          );
        });
      },
    );
  }

  Map<ShortcutActivator, VoidCallback> _keys(BuildContext context, bool narrow) => {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showFinder(context, model),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): _toggleSaved,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true): () => reading.currentState?.copy(),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            reading.currentState?.highlightSelection(color: widget.state.settings.highlightColor, edit: true),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => model.step(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => model.step(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () => model.step(1),
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () => model.step(-1),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          if (narrow) {
            model.showContent = false;
          } else {
            model.sidebarShown = true;
          }
          model.setFocusMode(false);
        },
        const SingleActivator(LogicalKeyboardKey.f11): () => model.setFocusMode(!model.focusMode),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (model.focusMode) {
            model.setFocusMode(false);
          } else if (!narrow && !model.sidebarShown) {
            model.toggleSidebar(narrow: false);
          } else if (narrow && model.showContent) {
            model.toggleSidebar(narrow: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f1): () => _dialog(const AboutScreen()),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): () => model.navigate(Section.today),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true): model.showCounter,
        const SingleActivator(LogicalKeyboardKey.slash, control: true, shift: true): () => _shortcuts(context),
      };

  Widget _content(BuildContext context, AppState state, bool narrow) {
    final p = model.current;
    var (title, sub) = switch (model.pane) {
      Pane.home => ('Home', ''),
      Pane.today => ('Today', state.settings.place?.label ?? ''),
      Pane.counter => ('Alláh-u-Abhá', 'Kitáb-i-Aqdas ¶18'),
      Pane.library => ('Library', '${state.library!.books.length} books'),
      Pane.prayers => ('Prayers', '${state.library!.prayerCategories.length} topics'),
      Pane.highlights => ('Highlights & notes', ''),
      Pane.reading => p == null
          ? (model.section == Section.saved ? 'Saved' : 'Prayers', '')
          : (
              bookOf(p) ??
                  switch (model.section) {
                    Section.saved => 'Saved',
                    Section.obligatory => 'Obligatory prayers',
                    _ => 'Prayers',
                  },
              heading(p, model.group?.kind == 'prayers' ? model.group!.title : null)
            ),
    };
    final saved = p != null && state.isSaved(p);
    final view = switch (model.pane) {
      Pane.home => HomeView(model: model, onAction: (r) => _act(context, r)),
      Pane.today => TodayView(onAction: (r) => _act(context, r)),
      Pane.counter => CounterView(onBack: model.leaveCounter),
      Pane.library => WritingsView(model: model),
      Pane.prayers => PrayersView(model: model),
      Pane.highlights => HighlightsView(model: model),
      Pane.reading => ReadingView(key: reading, model: model),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!model.focusMode)
        HeaderBar(
          start: [
            narrow
                ? HeaderButton(
                    icon: Icons.arrow_back_ios_new_rounded, tooltip: 'Back', onPressed: () => model.toggleSidebar(narrow: true))
                : HeaderButton(
                    icon: Icons.view_sidebar_outlined,
                    tooltip: 'Show or hide the sidebar',
                    onPressed: () => model.toggleSidebar(narrow: false)),
          ],
          title: WindowTitle(title: title, subtitle: sub),
          end: [
            HeaderButton(icon: Icons.search, tooltip: 'Search the texts (Ctrl+K)', onPressed: () => showFinder(context, model)),
            _TextMenu(state: state),
            if (!narrow)
              HeaderButton(
                icon: Icons.copy_outlined,
                tooltip: 'Copy the passage with its citation (Ctrl+Shift+C)',
                onPressed: p == null ? null : () => reading.currentState?.copy(),
              ),
            HeaderButton(
              icon: saved ? Icons.star_rounded : Icons.star_outline_rounded,
              tooltip: saved ? 'Saved (Ctrl+D to unsave)' : 'Save this passage (Ctrl+D)',
              color: saved ? ReaderColors.of(context).accentText : null,
              onPressed: p == null ? null : _toggleSaved,
            ),
            _menu(context, narrow, p != null),
          ],
        ),
      Expanded(child: view),
    ]);
  }

  Widget _menu(BuildContext context, bool narrow, bool onPassage) {
    PopupMenuItem<VoidCallback> item(String label, VoidCallback action, [String? keys, bool enabled = true]) => PopupMenuItem(
          value: action,
          enabled: enabled,
          height: 40,
          child: Row(children: [
            Expanded(child: Text(label)),
            if (keys != null) ...[const SizedBox(width: 24), Text(keys, style: dimStyle(context))],
          ]),
        );
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Menu',
      icon: const Icon(Icons.more_vert, size: 20),
      position: PopupMenuPosition.under,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        item('Search the texts…', () => showFinder(context, model), 'Ctrl+K'),
        if (narrow) item('Copy the passage', () => reading.currentState?.copy(), 'Ctrl+Shift+C', onPassage),
        const PopupMenuDivider(),
        item(Platform.isLinux ? 'Languages, settings & GTK import…' : 'Languages & settings…', () => _dialog(const SettingsScreen())),
        item('Today', () => model.navigate(Section.today), 'Ctrl+T'),
        item('Alláh-u-Abhá counter', model.showCounter, 'Ctrl+Shift+A'),
        item('Location & reminders…', () => showLocationDialog(context)),
        const PopupMenuDivider(),
        item('Keyboard shortcuts', () => _shortcuts(context), 'Ctrl+?'),
        item('About Bahá’í Reader', () => _dialog(const AboutScreen()), 'F1'),
      ],
    );
  }

  /// Carries out a button on Today, Home's cards or the Today calendar.
  void _act(BuildContext context, TodayRow row) {
    final state = widget.state;
    final library = state.library;
    if (library == null) return;
    switch (row.action) {
      case OpenToday():
        model.navigate(Section.today);
      case OpenLocation():
        showLocationDialog(context);
      case OpenCounter():
        model.showCounter();
      case OpenObligatory(:final passage, :final label):
        model.openObligatory(passage, label: label);
      case OpenPassage(:final passage, :final label):
        model.openPassage(passage, label: label);
      case OpenGroup(:final passages, :final label):
        final first = passages.first;
        if (first.isPrayer) {
          final work = Work(title: label, kind: 'prayers', passages: passages);
          model.openFromToday(work, 0, section: Section.prayers, label: label);
        } else {
          // Readings of a Holy Day: among the readings, in Days of Remembrance.
          final book = library.workOf(first)?.$1;
          model.openFromToday(Work(title: label, kind: 'readings', passages: passages), 0,
              section: Section.writings, book: book, label: label);
        }
      case MarkSaid(:final key, :final long):
        long ? state.markLong(!row.active) : state.markSaid(key, !row.active);
      case MarkFasted(:final key):
        state.markFasted(key, !row.active);
      case null:
        break;
    }
  }

  void _shortcuts(BuildContext context) {
    const groups = [
      ('Reading', [
        ('Next passage', 'Alt+→  or  Ctrl+Page Down'),
        ('Previous passage', 'Alt+←  or  Ctrl+Page Up'),
        ('Save or unsave the passage', 'Ctrl+D'),
        ('Copy the passage (or the selected words) with its citation', 'Ctrl+Shift+C'),
        ('Highlight the selected words and open its note', 'Ctrl+H'),
        ('Focus mode: only the text', 'F11'),
      ]),
      ('Finding', [
        ('Search all the texts, or only the open book', 'Ctrl+K'),
        ('Today', 'Ctrl+T'),
        ('Show the sidebar and its contents', 'Ctrl+F'),
      ]),
      ('Alláh-u-Abhá counter', [
        ('Open the counter', 'Ctrl+Shift+A'),
        ('Count one', 'Space  or  Enter'),
        ('Undo one', 'Backspace'),
        ('Start over', 'Ctrl+0'),
        ('Back to where you were', 'Esc'),
      ]),
      ('The app', [
        ('Keyboard shortcuts', 'Ctrl+?'),
        ('About Bahá’í Reader', 'F1'),
        ('Show the sidebar again; leave focus mode; close a dialog', 'Esc'),
      ]),
    ];
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
          child: ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
            const Text('Keyboard shortcuts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            for (final (title, rows) in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 6),
                child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: ReaderColors.of(context).accentText)),
              ),
              for (final (name, keys) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(name)),
                    const SizedBox(width: 16),
                    Text(keys, style: dimStyle(context, size: 13.5)),
                  ]),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// "Aa": appearance and text size, as the GTK app's text menu.
class _TextMenu extends StatelessWidget {
  const _TextMenu({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        final box = context.findRenderObject() as RenderBox;
        final o = box.localToGlobal(Offset.zero);
        showPopoverAt<void>(context, o & box.size, (_) => const _TextSettings(), below: true);
      },
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(36, 34)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Aa', style: TextStyle(fontWeight: FontWeight.w800)),
        Icon(Icons.expand_more, size: 18),
      ]),
    );
  }
}

class _TextSettings extends StatelessWidget {
  const _TextSettings();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = ReaderColors.of(context);
    final auto = state.omarchy != null ? 'Omarchy' : 'System';
    final themes = [('system', auto), ('light', 'Light'), ('dark', 'Dark'), ('sepia', 'Sepia')];
    return Padding(
      padding: const EdgeInsets.all(18),
      child: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Appearance'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (value, label) in themes)
              TextButton(
                onPressed: () => state.setTheme(value),
                style: TextButton.styleFrom(
                  backgroundColor:
                      state.settings.theme == value ? p.foreground.withValues(alpha: 0.2) : p.foreground.withValues(alpha: 0.07),
                ),
                child: Text(label),
              ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('Text size')),
            Text('${state.settings.textSize.round()}', style: dimStyle(context)),
          ]),
          Slider(min: 15, max: 36, divisions: 21, value: state.settings.textSize, onChanged: state.setTextSize),
        ]),
      ),
    );
  }
}
