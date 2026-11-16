/// One passage of a library, as converted by `scripts/convert_library.py` from the GTK app's `load_library()`.
///
/// Offsets (spans, highlights) are indexes into [text]. The converter guarantees the texts have no characters outside
/// the Basic Multilingual Plane, so Python's code-point offsets and Dart's UTF-16 offsets are the same numbers.
library;

/// A styled range of an official (bahai.org) text: `i`, `b`, `u`, `num`, `heading` or `quote`.
class TextStyleSpan {
  const TextStyleSpan(this.start, this.end, this.kind);
  final int start;
  final int end;
  final String kind;
}

class Passage {
  const Passage({
    required this.id,
    required this.title,
    required this.section,
    required this.tags,
    required this.text,
    required this.citation,
    required this.wordCount,
    this.heading,
    this.author,
    this.subgroup,
    this.match,
    this.spans = const [],
    this.references = const [],
    this.official = false,
    this.source,
    this.officialBook,
    this.directions = const [],
  });

  /// Stable id: `hidden:2`, `aqdas:Paragraphs:6`, or `4:hidden:687` outside English.
  final String id;
  final String title;
  final String? heading;
  final String? author;

  /// `prayers`, `hidden` or `writings`.
  final String section;
  final List<String> tags;
  final String? subgroup;
  final String text;

  /// Cross-language pairing key (GTK `ALIGN`), or null for passages that are never paired.
  final String? match;
  final String citation;
  final int wordCount;
  final List<TextStyleSpan> spans;

  /// Links to other passages: (passage id, label), e.g. Aqdas notes.
  final List<(String, String)> references;

  /// True when the text is bahai.org's official text.
  final bool official;
  final String? source;

  /// The bahai.org book an official prayer's text was taken from (its citation already names it).
  final String? officialBook;

  /// An obligatory prayer's directions (when and how to say it), shown in italics: (start, end) offsets.
  final List<(int, int)> directions;

  bool get isPrayer => section == 'prayers';

  Passage copyWith({List<(int, int)>? directions}) => Passage(
        id: id,
        title: title,
        section: section,
        tags: tags,
        text: text,
        citation: citation,
        wordCount: wordCount,
        heading: heading,
        author: author,
        subgroup: subgroup,
        match: match,
        spans: spans,
        references: references,
        official: official,
        source: source,
        officialBook: officialBook,
        directions: directions ?? this.directions,
      );

  /// The converter's record (`scripts/convert_library.py`), which [Passage.fromJson] reads.
  Map<String, Object?> toJson() => {
        'id': id,
        't': title,
        'a': ?author,
        's': section,
        'g': tags,
        'sg': ?subgroup,
        'x': text,
        'm': ?match,
        'c': citation,
        'w': wordCount,
        'h': ?heading,
        if (spans.isNotEmpty) 'sp': [for (final s in spans) [s.start, s.end, s.kind]],
        if (references.isNotEmpty) 'r': [for (final (id, label) in references) [id, label]],
        if (official) 'o': true,
        'ob': ?officialBook,
        'src': ?source,
        if (directions.isNotEmpty) 'd': [for (final (a, b) in directions) [a, b]],
      };

  /// The text without bahai.org's margin numbers, for plain labels (GTK `unnumbered()`).
  String get unnumbered {
    final numbers = [for (final s in spans) if (s.kind == 'num') (s.start, s.end)]..sort((a, b) => a.$1.compareTo(b.$1));
    if (numbers.isEmpty) return text;
    final out = StringBuffer();
    var at = 0;
    for (final (a, b) in numbers) {
      out.write(text.substring(at, a));
      at = b < text.length && text[b] == ' ' ? b + 1 : b;
    }
    return (out..write(text.substring(at))).toString();
  }

  factory Passage.fromJson(Map<String, dynamic> j) => Passage(
        id: j['id'] as String,
        title: j['t'] as String,
        heading: j['h'] as String?,
        author: j['a'] as String?,
        section: j['s'] as String,
        tags: (j['g'] as List).cast<String>(),
        subgroup: j['sg'] as String?,
        text: j['x'] as String,
        match: j['m'] as String?,
        citation: (j['c'] as String?) ?? '',
        wordCount: (j['w'] as num?)?.toInt() ?? 0,
        spans: [
          for (final s in (j['sp'] as List? ?? const []))
            TextStyleSpan((s[0] as num).toInt(), (s[1] as num).toInt(), s[2] as String),
        ],
        references: [
          for (final r in (j['r'] as List? ?? const [])) (r[0] as String, r[1] as String),
        ],
        official: j['o'] == true,
        source: j['src'] as String?,
        officialBook: j['ob'] as String?,
        directions: [
          for (final d in (j['d'] as List? ?? const [])) ((d[0] as num).toInt(), (d[1] as num).toInt()),
        ],
      );
}

/// A bundled language, from `assets/library/manifest.json`.
class LanguageInfo {
  const LanguageInfo({required this.id, required this.name, required this.english, this.rtl = false});
  final int id;
  final String name;
  final String english;
  final bool rtl;

  String get label => name == english ? name : '$name ($english)';

  factory LanguageInfo.fromJson(Map<String, dynamic> j) => LanguageInfo(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        english: j['english'] as String,
        rtl: j['rtl'] == true,
      );
}
