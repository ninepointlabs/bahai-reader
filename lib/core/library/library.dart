import 'passage.dart';

/// A "work" the library lists and the reader opens: a book, or a category of prayers.
class Work {
  Work({required this.title, required this.kind, required this.passages});
  final String title;

  /// `prayers` or `writings`.
  final String kind;
  final List<Passage> passages;

  /// Contents: passages grouped by subgroup, in reading order. Works without parts have one unnamed group.
  List<(String?, List<int>)> get contents {
    final groups = <(String?, List<int>)>[];
    for (var i = 0; i < passages.length; i++) {
      final sg = passages[i].subgroup;
      if (groups.isEmpty || groups.last.$1 != sg) groups.add((sg, []));
      groups.last.$2.add(i);
    }
    return groups;
  }

  int get words => passages.fold(0, (n, p) => n + p.wordCount);

  /// A line for the library card, like the GTK app's `book_summary()`.
  String get summary {
    final parts = {for (final p in passages) if (p.subgroup != null) p.subgroup}.length;
    final w = words;
    final length = w >= 1000 ? '${(w / 1000).round()}k words' : '$w words';
    final count = parts > 1 ? '$parts parts' : '${passages.length} passage${passages.length == 1 ? '' : 's'}';
    return '$count · $length';
  }
}

const hiddenWords = 'The Hidden Words';

/// The book a passage belongs to, as the library shows it, or null for a prayer (GTK `book_of()`).
String? bookOf(Passage p) {
  if (p.section == 'hidden') return hiddenWords;
  if (p.section == 'writings' && p.tags.isNotEmpty) return p.tags.first;
  return null;
}

/// One language's library, with the indexes the app needs.
class Library {
  Library(this.language, this.passages, {List<String> daily = const [], List<(String, List<String>)> obligatory = const []})
      : byId = {for (final p in passages) p.id: p},
        _dailyIds = daily,
        _obligatoryIds = obligatory,
        byMatch = {for (final p in passages) if (p.match != null) p.match!: p} {
    for (final p in passages) {
      final book = bookOf(p);
      if (book != null) {
        _books.putIfAbsent(book, () => Work(title: book, kind: 'writings', passages: [])).passages.add(p);
      } else if (p.isPrayer) {
        // A prayer is listed under each of its categories, as in the GTK app.
        for (final tag in p.tags.isEmpty ? const ['Prayers'] : p.tags) {
          _prayers.putIfAbsent(tag, () => Work(title: tag, kind: 'prayers', passages: [])).passages.add(p);
        }
      }
    }
  }

  final int language;
  final List<Passage> passages;
  final List<String> _dailyIds;
  final List<(String, List<String>)> _obligatoryIds;

  /// The passage of the day, the same one the GTK app shows (its shuffled order, precomputed by the converter).
  Passage? passageOfTheDay(int ordinal) {
    final pool = [for (final id in _dailyIds) if (byId[id] != null) byId[id]!];
    return pool.isEmpty ? null : pool[ordinal % pool.length];
  }

  /// The Obligatory prayers section: the three prayers, then the Kitáb-i-Aqdas guidance on them, each as a work.
  late final List<Work> obligatoryGroups = [
    for (final (group, ids) in _obligatoryIds)
      Work(title: group, kind: 'obligatory', passages: [for (final id in ids) if (byId[id] != null) byId[id]!]),
  ];

  /// The Days of Remembrance readings for a Holy Day's part name.
  List<Passage> readingsFor(String part) =>
      [for (final p in passages) if (p.tags.contains('Days of Remembrance') && p.subgroup == part) p];

  /// The prayers of a category, in order.
  List<Passage> prayersIn(String category) => [for (final p in passages) if (p.isPrayer && p.tags.contains(category)) p];

  /// A Kitáb-i-Aqdas passage by its part (`Text`, `Questions and Answers`, `Notes`) and printed number.
  Passage? aqdas(String part, int number) => passages
      .where((p) => p.tags.contains('The Kitáb-i-Aqdas') && p.subgroup == part && p.title.startsWith('$number · '))
      .firstOrNull;
  final Map<String, Passage> byId;
  final Map<String, Passage> byMatch;
  final Map<String, Work> _books = {};
  final Map<String, Work> _prayers = {};

  /// Books in library order.
  List<Work> get books => _books.values.toList();

  /// Prayer categories, alphabetically.
  List<Work> get prayerCategories => _prayers.values.toList()..sort((a, b) => a.title.compareTo(b.title));

  /// {id: match} for this library, used to follow marks made in this language into another one.
  Map<String, String> get matches => {for (final p in passages) if (p.match != null) p.id: p.match!};

  /// The work a passage is read in, and its index there.
  (Work, int)? workOf(Passage p) {
    final book = bookOf(p);
    final work = book != null ? _books[book] : _prayers[p.tags.isEmpty ? 'Prayers' : p.tags.first];
    if (work == null) return null;
    final i = work.passages.indexWhere((q) => q.id == p.id);
    return i < 0 ? null : (work, i);
  }
}
