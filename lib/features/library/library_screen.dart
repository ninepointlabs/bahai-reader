import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/library/labels.dart';
import '../../core/library/library.dart';
import '../about/about_screen.dart';
import '../marks/marks_screen.dart';
import '../reader/reader_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../today/exact_times.dart';
import '../today/location_dialog.dart';
import '../today/phone_today.dart';
import '../today/today_view.dart';
import 'contents_screen.dart';
import 'language_menu.dart';

/// The phone layout's home: Today (the date, the obligatory prayer, Feasts, the Fast, the passage of the day), the
/// writings (books) and the prayers (by category, after the Obligatory prayers), for the chosen language.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.openId});

  /// A passage to open once the library is ready.
  final String? openId;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 3, vsync: this);
  StreamSubscription<String>? _opens;

  void showToday() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    tabs.animateTo(0);
  }

  /// A reminder's tap: its obligatory prayer, or Today.
  void _openFromNotification(String target) {
    showToday();
    if (target.startsWith('prayer:')) openObligatoryPrayer(context, target.substring(7));
  }

  @override
  void dispose() {
    _opens?.cancel();
    tabs.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _opens = AppScope.read(context).openRequests.listen(_openFromNotification);
    AppScope.read(context).remindersStarted.then((_) {
      if (mounted) offerExactTimes(context, atStart: true);
    });
    final id = widget.openId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final state = AppScope.read(context);
        await state.marksReady;
        if (!mounted) return;
        final p = state.passageOf(id);
        final place = p == null ? null : state.library?.workOf(p);
        if (place != null && mounted) _push(context, ReaderScreen(work: place.$1, index: place.$2));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.read(context);
    final notice = state.notice;
    if (notice != null) {
      state.notice = null;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice), duration: const Duration(seconds: 8))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final library = state.library;
    return Scaffold(
        appBar: AppBar(
          title: const Text('Bahá’í Reader'),
          actions: [
            const LanguageMenu(),
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: library == null ? null : () => _push(context, const SearchScreen()),
            ),
            IconButton(
              tooltip: 'Saved & highlights',
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: library == null ? null : () => _push(context, const MarksScreen()),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'location'
                  ? showLocationPage(context)
                  : _push(context, v == 'settings' ? const SettingsScreen() : const AboutScreen()),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'location', child: Text('Location & reminders')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
                PopupMenuItem(value: 'about', child: Text('About & attribution')),
              ],
            ),
          ],
          bottom: TabBar(controller: tabs, tabs: const [Tab(text: 'Today'), Tab(text: 'Writings'), Tab(text: 'Prayers')]),
        ),
        body: state.error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(state.error!)))
            : state.loading || library == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(controller: tabs, children: [
                    TodayView(onAction: (row) => actOnPhone(context, row, showToday: showToday)),
                    _WorkList(works: library.books, emptyText: 'No writings in this language yet.', index: true, unit: 'passages'),
                    _WorkList(
                      works: library.prayerCategories,
                      emptyText: 'No prayers in this language.',
                      index: true,
                      first: library.obligatoryGroups.isEmpty
                          ? null
                          : ('Obligatory prayers', 'The three prayers, their guidance, and the Alláh-u-Abhá counter',
                              () => _push(context, const ObligatoryScreen())),
                    ),
                  ]),
    );
  }
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

class _WorkList extends StatelessWidget {
  const _WorkList({required this.works, required this.emptyText, this.first, this.index = false, this.unit = 'prayers'});
  final List<Work> works;
  final String emptyText;

  /// On a narrow screen a compact table of contents (one line per work, with its count) instead of cards; and a work
  /// opens its contents ([ContentsScreen]) rather than its first passage.
  final bool index;

  /// What the count beside each work counts, for screen readers.
  final String unit;

  /// A card before the works: (title, subtitle, on tap).
  final (String, String, VoidCallback)? first;

  @override
  Widget build(BuildContext context) {
    if (works.isEmpty) return Center(child: Text(emptyText));
    final state = AppScope.of(context);
    (String, int) continueAt(Work work) {
      final last = state.settings.positions[work.title];
      final at = last == null ? -1 : work.passages.indexWhere((p) => p.id == last);
      return (at > 0 ? 'Continue at ${at + 1}' : '', at < 0 ? 0 : at);
    }

    return LayoutBuilder(builder: (context, box) {
      final columns = (box.maxWidth / 380).floor().clamp(1, 4);
      if (index && columns == 1) {
        final theme = Theme.of(context);
        final dim = theme.textTheme.bodySmall;
        const divider = Divider(height: 1, indent: 16, endIndent: 16);
        Widget row(Work work) {
          final (note, _) = continueAt(work);
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(work.title, style: const TextStyle(fontSize: 15.5)),
            subtitle: note.isEmpty ? null : Text(note, style: dim),
            trailing: Text('${work.passages.length}', style: dim, semanticsLabel: '${work.passages.length} $unit'),
            onTap: () => _push(context, ContentsScreen(work: work)),
          );
        }

        final prayers = works.first.passages.first.isPrayer;
        final rows = <Widget>[
          if (first case final f?) ...[
            ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(f.$2, style: dim),
              onTap: f.$3,
            ),
            divider,
          ],
          // Writings under their authors (several authors: Compilations); prayer categories as one list.
          if (prayers)
            for (final (i, w) in works.indexed) ...[if (i > 0) divider, row(w)]
          else
            // Each author folds open to their books, as on the desktop.
            for (final (author, books) in booksByAuthor(works))
              ExpansionTile(
                key: PageStorageKey('author/$author'),
                title: Text(author, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${books.length} book${books.length == 1 ? '' : 's'}', style: dim),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.only(left: 12),
                children: [
                  for (final (i, w) in books.indexed) ...[if (i > 0) divider, row(w)],
                ],
              ),
        ];
        return ListView(padding: const EdgeInsets.only(top: 4, bottom: 16), children: rows);
      }
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns, mainAxisExtent: 120, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: works.length + (first == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (first case final f?) {
            if (i == 0) return _card(context, f.$1, f.$2, f.$3);
            i--;
          }
          final work = works[i];
          final last = state.settings.positions[work.title];
          final at = last == null ? -1 : work.passages.indexWhere((p) => p.id == last);
          return _card(context, work.title, at > 0 ? '${work.summary} · continue at ${at + 1}' : work.summary,
              () => _push(context, index ? ContentsScreen(work: work) : ReaderScreen(work: work, index: at < 0 ? 0 : at)));
        },
      );
    });
  }
}

Widget _card(BuildContext context, String title, String subtitle, VoidCallback onTap) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
