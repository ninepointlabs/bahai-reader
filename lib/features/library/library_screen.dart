import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/library/library.dart';
import '../about/about_screen.dart';
import '../marks/marks_screen.dart';
import '../reader/reader_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import 'language_menu.dart';

/// The library: writings (books) and prayers (by category), for the chosen language.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.openId});

  /// A passage to open once the library is ready.
  final String? openId;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
              onSelected: (v) => _push(context, v == 'settings' ? const SettingsScreen() : const AboutScreen()),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'settings', child: Text('Settings')),
                PopupMenuItem(value: 'about', child: Text('About & attribution')),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Writings'), Tab(text: 'Prayers')]),
        ),
        body: state.error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(state.error!)))
            : state.loading || library == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _WorkList(works: library.books, emptyText: 'No writings in this language yet.'),
                    _WorkList(works: library.prayerCategories, emptyText: 'No prayers in this language.'),
                  ]),
      ),
    );
  }
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

class _WorkList extends StatelessWidget {
  const _WorkList({required this.works, required this.emptyText});
  final List<Work> works;
  final String emptyText;

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
        itemCount: works.length,
        itemBuilder: (context, i) {
          final work = works[i];
          final last = state.settings.positions[work.title];
          final at = last == null ? -1 : work.passages.indexWhere((p) => p.id == last);
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _push(context, ReaderScreen(work: work, index: at < 0 ? 0 : at)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(work.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    const SizedBox(height: 4),
                    Text(at > 0 ? '${work.summary} · continue at ${at + 1}' : work.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
