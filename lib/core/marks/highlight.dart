/// Highlights and notes, modelled on the GTK app's `bahai_reader/marks.py`.
///
/// A highlight is stored by passage id plus character offsets into the passage's text, with the highlighted words
/// themselves so it can find its place again if the text changes. Marks are never written into the texts.
library;

const highlightColors = ['yellow', 'green', 'blue', 'magenta'];

/// Characters kept in one note.
const noteLimit = 5000;

class Highlight {
  const Highlight({
    required this.id,
    required this.start,
    required this.end,
    required this.words,
    required this.color,
    this.created,
    this.note,
    this.uid,
  });

  final String id;
  final int start;
  final int end;
  final String words;
  final String color;
  final String? created;
  final String? note;

  /// The record's own id in the user-data store (a UUID), or null until it is first stored. Not part of the GTK shape
  /// ([toJson]) and not part of equality: two records with the same place, words, colour and note are the same mark.
  final String? uid;

  Highlight withUid(String uid) =>
      Highlight(id: id, start: start, end: end, words: words, color: color, created: created, note: note, uid: uid);

  Highlight copyWith({int? start, int? end, String? color, String? note, bool clearNote = false}) => Highlight(
        id: id,
        start: start ?? this.start,
        end: end ?? this.end,
        words: words,
        color: color ?? this.color,
        created: created,
        note: clearNote ? null : (note ?? this.note),
        uid: uid,
      );

  /// The same keys and shape as a GTK `settings.json` highlight record.
  Map<String, Object> toJson() => {
        'id': id,
        'start': start,
        'end': end,
        'words': words,
        'color': color,
        'created': ?created,
        'note': ?note,
      };

  /// A well-formed record, or null (GTK `clean_highlights()` for one record).
  static Highlight? tryParse(Object? r) {
    if (r is! Map) return null;
    final id = r['id'], start = r['start'], end = r['end'], words = r['words'], color = r['color'];
    if (id is! String || start is! int || end is! int || !(0 <= start && start < end)) return null;
    if (!highlightColors.contains(color) || words is! String || words.isEmpty) return null;
    final note = r['note'];
    final created = r['created'];
    final uid = r['uid'];
    return Highlight(
      id: id,
      start: start,
      end: end,
      words: words,
      color: color as String,
      note: note is String && note.trim().isNotEmpty ? _limit(note) : null,
      created: created is String ? created : null,
      uid: uid is String && uid.isNotEmpty ? uid : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Highlight &&
      other.id == id &&
      other.start == start &&
      other.end == end &&
      other.words == words &&
      other.color == color &&
      other.note == note &&
      other.created == created;

  @override
  int get hashCode => Object.hash(id, start, end, words, color, note, created);
}

String _limit(String s) => s.length <= noteLimit ? s : s.substring(0, noteLimit);

List<Highlight> cleanHighlights(Object? records) =>
    records is List ? [for (final r in records) ?Highlight.tryParse(r)] : [];

final _space = RegExp(r'\s');

String _today() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A highlight of `text[start:end]` of passage [id], never beginning or ending on a space (GTK `make()`).
Highlight? makeHighlight(String id, String text, int start, int end,
    {String color = 'yellow', String? note, String? today}) {
  start = start.clamp(0, text.length);
  end = end.clamp(0, text.length);
  if (start > end) (start, end) = (end, start);
  while (start < end && _space.hasMatch(text[start])) {
    start++;
  }
  while (end > start && _space.hasMatch(text[end - 1])) {
    end--;
  }
  if (start >= end) return null;
  final trimmed = note?.trim();
  return Highlight(
    id: id,
    start: start,
    end: end,
    words: text.substring(start, end),
    color: highlightColors.contains(color) ? color : highlightColors.first,
    created: today ?? _today(),
    note: trimmed != null && trimmed.isNotEmpty ? _limit(trimmed) : null,
  );
}

/// Where a highlight is in [text] now: its offsets if the words are still there, else the nearest place the same words
/// are found, else null (the text changed; the highlight is kept and listed, but not drawn) (GTK `anchor()`).
(int, int)? anchor(String text, Highlight record) {
  final start = record.start, end = record.end;
  if (end <= text.length && text.substring(start, end) == record.words) return (start, end);
  int? best;
  for (var at = text.indexOf(record.words); at >= 0; at = text.indexOf(record.words, at + 1)) {
    if (best == null || (at - start).abs() < (best - start).abs()) best = at;
  }
  return best == null ? null : (best, best + record.words.length);
}

List<Highlight> ofPassage(Iterable<Highlight> records, String id) => [for (final r in records) if (r.id == id) r];

/// The passage's highlights that touch start..end.
List<Highlight> overlapping(Iterable<Highlight> records, String id, int start, int end) =>
    [for (final r in ofPassage(records, id)) if (r.start < end && start < r.end) r];

/// Adds a highlight; any highlight of the same passage it overlaps is replaced by it (one colour per word).
List<Highlight> addHighlight(List<Highlight> records, Highlight record) => [
      for (final r in records)
        if (!(r.id == record.id && r.start < record.end && record.start < r.end)) r,
      record,
    ];

/// A note trimmed and limited like the GTK app's; empty means no note.
String? cleanNote(String? note) {
  final t = note?.trim();
  return t == null || t.isEmpty ? null : _limit(t);
}

// ----- following a passage into another language -----
// Highlights and saved passages are stored under the id of the passage they were made on ("hidden:2" in English,
// "4:hidden:687" in Spanish) and are never rewritten. In another language they are shown on the passage with the same
// numbering (the item's `match`). Prayers, Days of Remembrance, Riḍván messages and English-only bahai.org texts have
// no match, so they stay with their own language.

/// The language a stored passage id belongs to: "4:hidden:687" is 4; an id with no number in front is English (1).
int languageOf(String key) {
  final head = key.split(':').first;
  return int.tryParse(head) != null && RegExp(r'^\d+$').hasMatch(head) ? int.parse(head) : 1;
}

/// The passage of the current library that a stored id means, or null (GTK `marks.follow()`).
/// [byId] and [byMatch] index the current library; [matchesIn] gives {id: match} for a language's library.
T? follow<T>(String key, Map<String, T> byId, Map<String, T> byMatch, Map<String, String> Function(int) matchesIn) {
  final item = byId[key];
  if (item != null) return item;
  final match = matchesIn(languageOf(key))[key];
  return match == null ? null : byMatch[match];
}

String excerpt(String words, [int limit = 220]) {
  final flat = words.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (flat.length <= limit) return flat;
  final cut = flat.substring(0, limit);
  final space = cut.lastIndexOf(' ');
  return '${space > 0 ? cut.substring(0, space) : cut}…';
}
