/// Accent- and apostrophe-insensitive matching, like the GTK app's `bahai_reader/search.py`: "Bahaullah" finds
/// "Bahá’u’lláh".
///
/// Dart has no Unicode normalisation in its core libraries, so the converter writes `assets/library/fold.json`: for
/// each character in the bundled texts (and accented Latin letters a query may contain), what Python's `fold()` turns
/// it into. Folding applies that table per character, which is what the GTK app's `fold_map()` does.
library;

class Folder {
  Folder(this.table);
  final Map<String, String> table;

  String _char(String c) => table[c] ?? c.toLowerCase();

  String fold(String text) {
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      out.write(_char(text[i]));
    }
    return out.toString();
  }

  /// fold(text), and for each of its code units the index in [text] it came from.
  (String, List<int>) foldMap(String text) {
    final out = StringBuffer();
    final where = <int>[];
    for (var i = 0; i < text.length; i++) {
      final f = _char(text[i]);
      out.write(f);
      for (var k = 0; k < f.length; k++) {
        where.add(i);
      }
    }
    return (out.toString(), where);
  }

  /// Where [query] (already folded) first occurs in [text], as (start, end) in text, or null.
  (int, int)? find(String text, String query) {
    if (query.isEmpty) return null;
    final (folded, where) = foldMap(text);
    final at = folded.indexOf(query);
    if (at < 0) return null;
    return (where[at], where[at + query.length - 1] + 1);
  }
}

/// (before, match, after) around [span], cut at word boundaries, with … where text was left out (GTK `snippet()`).
(String, String, String) snippet(String text, (int, int)? span, {int width = 150}) {
  String clean(String t) => t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (span == null) {
    final flat = clean(text);
    if (flat.length <= width) return (flat, '', '');
    final cut = flat.substring(0, width);
    final sp = cut.lastIndexOf(' ');
    return ('${sp > 0 ? cut.substring(0, sp) : cut}…', '', '');
  }
  final (start, end) = span;
  var left = (start - width ~/ 2).clamp(0, text.length);
  var right = (end + width ~/ 2).clamp(0, text.length);
  if (left > 0) {
    final sp = text.indexOf(' ', left);
    left = sp >= 0 && sp < start ? sp + 1 : left;
  }
  if (right < text.length) {
    final sp = text.lastIndexOf(' ', right);
    if (sp > end) right = sp;
  }
  final pre = text.substring(left, start), post = text.substring(end, right);
  final before = '${left > 0 ? '…' : ''}${clean(pre)}${pre.isNotEmpty && RegExp(r'\s$').hasMatch(pre) ? ' ' : ''}';
  final after = '${post.startsWith(RegExp(r'\s')) ? ' ' : ''}${clean(post)}${right < text.length ? '…' : ''}';
  return (before, text.substring(start, end), after);
}
