import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
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
                    _WorkList(works: library.books, emptyText: 'No writings in this language yet.'),
                    _WorkList(
                      works: library.prayerCategories,
                      emptyText: 'No prayers in this language.',
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
  const _WorkList({required this.works, required this.emptyText, this.first});
  final List<Work> works;
  final String emptyText;

  /// A card before the works: (title, subtitle, on tap).
  final (String, String, VoidCallback)? first;

  @override
  Widget build(BuildContext context) {
    if (works.isEmpty) return Center(child: Text(emptyText));
    final state = AppScope.of(context);
    return LayoutBuilder(builder: (context, box) {
      final columns = (box.maxWidth / 380).floor().clamp(1, 4);
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
              () => _push(context, ReaderScreen(work: work, index: at < 0 ? 0 : at)));
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
