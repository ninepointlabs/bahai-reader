/// How passages are named in the interface, ported from the GTK app's `labels.py` and parts of `library.py`.
library;

import 'library.dart';
import 'passage.dart';

const obligatoryPrayers = ['Short Obligatory Prayer', 'Medium Obligatory Prayer', 'Long Obligatory Prayer'];

/// The Central Figures and the institutions, in the order the library lists their books (GTK `AUTHOR_ORDER`).
const authorOrder = ['The Báb', 'Bahá’u’lláh', '‘Abdu’l‑Bahá', 'Shoghi Effendi', 'The Universal House of Justice'];

(int, String) authorRank(String author) {
  final i = authorOrder.indexOf(author);
  return (i < 0 ? authorOrder.length : i, author);
}

String wordLabel(Passage p) => '${p.wordCount} word${p.wordCount == 1 ? '' : 's'}';

/// The reading pane's title: what the passage is, not just its number. [context] is the category it was opened in.
String heading(Passage p, [String? context]) {
  if (p.isPrayer) {
    final named = obligatoryPrayers.where(p.tags.contains).firstOrNull;
    if (named != null) return p.text.trimLeft().startsWith(named) ? 'Obligatory prayers' : named;
    if (context != null && p.tags.contains(context)) return context;
    return p.tags.isNotEmpty ? p.tags.first : 'Prayer';
  }
  if (p.heading != null && p.heading!.isNotEmpty) return p.heading!;
  final number = p.title.split(' · ').first;
  final parts = p.id.split(':');
  final kind = parts.length >= 2 ? parts[parts.length - 2] : parts.first;
  if (kind == 'hidden') {
    final origin = p.tags.contains('From the Arabic')
        ? 'Arabic'
        : p.tags.contains('From the Persian')
            ? 'Persian'
            : null;
    return origin != null ? '$origin no. $number' : number;
  }
  return switch (kind) {
    'Paragraphs' => 'Paragraph $number',
    'QAs' => 'Question and Answer $number',
    'Notes' => 'Note $number',
    _ => number,
  };
}

/// The line over the heading: the rest of where the passage is, never a repeat of the heading.
String subtitle(Passage p, [String? context]) {
  final title = heading(p, context);
  var parts = <String?>[...p.tags, if (p.subgroup != null) p.subgroup];
  if (p.isPrayer) {
    parts = [p.author, ...parts, wordLabel(p)];
  } else if (p.author != null && !parts.any((s) => s != null && s.contains(p.author!)) && !title.contains(p.author!)) {
    parts = [...parts, p.author];
  }
  final seen = <String>{};
  return [for (final s in parts) if (s != null && s.isNotEmpty && s != title && seen.add(s)) s].join(' · ');
}

/// A passage's name in the contents list. The obligatory prayers go by their names.
String listTitle(Passage p) {
  if (p.isPrayer) {
    final named = obligatoryPrayers.where(p.tags.contains).firstOrNull;
    if (named != null) return named;
  }
  return p.title;
}

/// How far through the book a passage is, by words: (words before it, words in the book).
(int, int) bookProgress(List<Passage> passages, Passage p) {
  var before = 0, total = 0;
  var reached = false;
  for (final q in passages) {
    if (q.id == p.id) reached = true;
    if (!reached) before += q.wordCount;
    total += q.wordCount;
  }
  return (before, total);
}

/// The group a search result is listed under: its book, or the prayers' category.
String placeOf(Passage p) => bookOf(p) ?? 'Prayers · ${p.tags.isNotEmpty ? p.tags.first : 'Prayers'}';

/// The author a book is listed under.
String authorOf(Work w) => w.passages.map((p) => p.author).whereType<String>().firstOrNull ?? 'Other';

/// A work's contents as the GTK sidebar shows them: named groups (the Hidden Words' Arabic and Persian, a book's parts)
/// holding passage indexes, with passages outside any part listed on their own (group null).
List<(String?, List<int>)> contentsOf(Work w) {
  final groups = <(String?, List<int>)>[];
  final hidden = w.title == hiddenWords;
  for (var i = 0; i < w.passages.length; i++) {
    final p = w.passages[i];
    final name = hidden ? (p.tags.isNotEmpty ? p.tags.first : null) : p.subgroup;
    if (groups.isEmpty || groups.last.$1 != name) groups.add((name, []));
    groups.last.$2.add(i);
  }
  return groups;
}

/// The phone reader's heading: the passage's own heading, or its title when that is a name ("7 · Muhammad",
/// "Epistle to the Son of the Wolf"). Most titles are only the passage's opening words, cut short, worked out from the
/// text without its margin numbers and its own heading line (“Medium Obligatory Prayer”); the text already shows those
/// words, so then only the number is a heading, or nothing.
String? phoneHeading(Passage p) {
  if (p.heading != null) return p.heading;
  String flat(String s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  final cut = p.title.indexOf(' · ');
  final (number, rest) = cut < 0 ? ('', p.title) : (p.title.substring(0, cut), p.title.substring(cut + 3));
  final opening = flat(rest);
  final at = opening.isEmpty ? -1 : flat(p.unnumbered).indexOf(opening);
  // A long title found further in is still the opening, after a preface (Hidden Words no. 1, a tablet's name).
  if (at == 0 || (at > 0 && opening.length >= 40)) return number.isEmpty ? null : number;
  return p.title;
}
