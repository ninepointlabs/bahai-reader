import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app/app_state.dart';
import '../../core/library/library.dart';
import '../../core/library/passage.dart';
import '../../core/search/fold.dart';
import '../../core/search/search_index.dart';
import '../reader/reader_screen.dart';

/// Searches every passage of the current language's library: titles, texts and categories, ignoring case, accents,
/// apostrophes and hyphens ("Bahaullah" finds "Bahá’u’lláh").
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final controller = TextEditingController();
  Timer? _debounce;
  SearchIndex? index;
  List<Passage> results = const [];
  String query = '';
  static const limit = 500;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.read(context).searchIndex().then((i) {
      if (!mounted) return;
      setState(() => index = i);
      _run();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _run);
  }

  void _run() {
    final i = index;
    if (i == null) return;
    setState(() {
      query = controller.text;
      results = i.search(query, limit: limit);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final folder = state.folder!;
    final folded = folder.fold(query.trim());
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          autofocus: true,
          onChanged: _changed,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: 'Search ${state.language.english} library',
            border: InputBorder.none,
          ),
        ),
      ),
      body: index == null
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Preparing search…'),
            ]))
          : folded.isEmpty
              ? const Center(child: Text('Type to search titles and texts. Accents and apostrophes are optional.'))
              : results.isEmpty
                  ? const Center(child: Text('No passages found.'))
                  : ListView.separated(
                      itemCount: results.length + 1,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                                results.length >= limit ? 'First $limit passages' : '${results.length} passages',
                                style: theme.textTheme.bodySmall),
                          );
                        }
                        final p = results[i - 1];
                        final (before, match, after) = snippet(p.text, folder.find(p.text, folded));
                        return ListTile(
                          title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(bookOf(p) ?? (p.tags.isEmpty ? 'Prayers' : 'Prayers · ${p.tags.first}'),
                                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: before),
                                TextSpan(
                                    text: match,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        backgroundColor: theme.colorScheme.tertiaryContainer)),
                                TextSpan(text: after),
                              ]),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                          onTap: () {
                            final place = state.library!.workOf(p);
                            if (place == null) return;
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ReaderScreen(work: place.$1, index: place.$2, query: query)));
                          },
                        );
                      },
                    ),
    );
  }
}
