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

  bool get isPrayer => section == 'prayers';

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
