/// Language packs: the BahaiPrayers.net feeds of one language, as the GTK app downloads and keeps them
/// (`~/.local/share/bahai-reader/libraries/<id>.json`: `{feed key: the feed's JSON}`), turned into passages here.
///
/// A line-by-line port of the GTK app's `load_bahaiprayers()`, `validate_feed()`, `plain()`, `word_count()`,
/// `citation()`, `align()`, `obligatory()`, `directions()` and `reflections()` with its shuffled order, so a pack gives
/// the same ids, titles, groups, `match` keys, citations, references and passage of the day as in the GTK app
/// (checked against the GTK output in test/packs_test.dart). Nothing here touches the network; see `downloads.dart`.
library;

import 'dart:convert';

import 'passage.dart';

/// The feeds a pack can hold, in the GTK app's order (GTK `FEEDS`), with their BahaiPrayers.net endpoints.
const feeds = {
  'prayers': 'prayersystembylanguage?html=true&languageid=1',
  'hidden': 'HiddensByLanguage?languageid=1',
  'gleanings': 'GleaningsByLanguage?languageid=1',
  'meditations': 'PMsByLanguage?languageid=1',
  'tablets': 'TabsByLanguage?languageid=1',
  'iqan': 'IqansByLanguage?languageid=1',
  'aqdas': 'AqdasByLanguage?languageid=1&html=true',
  'saq': 'SaqTopicsByLanguage?languageid=1',
  'days': 'DaysRemembersByLanguage?languageid=1',
  'ridvan': 'RidvansByLanguage?languageid=1',
};

/// Which languages offer each collection (GTK `LANGUAGE_ENDPOINTS`).
const languageEndpoints = {
  'prayers': 'Languages',
  'hidden': 'HiddenLanguages',
  'gleanings': 'GleaningLanguages',
  'meditations': 'PMLanguages',
  'tablets': 'TabLanguages',
  'iqan': 'IqanLanguages',
  'aqdas': 'AqdasLanguages',
  'saq': 'SaqLanguages',
  'days': 'DaysRememberLanguages',
  'ridvan': 'RidvanLanguages',
};

const bookNames = {
  'gleanings': 'Gleanings from the Writings of Bahá’u’lláh',
  'meditations': 'Prayers and Meditations',
  'tablets': 'Tablets of Bahá’u’lláh',
  'iqan': 'The Kitáb-i-Íqán',
  'aqdas': 'The Kitáb-i-Aqdas',
  'saq': 'Some Answered Questions',
  'days': 'Days of Remembrance',
  'ridvan': 'Riḍván Messages',
};

const sectionNames = {'prayers': 'Prayers', 'hidden': 'The Hidden Words', ...bookNames};

const prayerFeedBooks = {'Epistle to the Son of the Wolf'};

const holyDays = {
  'NAWRUZ': 'Naw-Rúz',
  'RIDVAN': 'Riḍván',
  'DECLARATIONBAB': 'Declaration of the Báb',
  'MARTYRDOMBAB': 'Martyrdom of the Báb',
  'ASCENSIONBAHAULLAH': 'Ascension of Bahá’u’lláh',
  'BIRTHBAB': 'Birth of the Báb',
  'BIRTHBAHAULLAH': 'Birth of Bahá’u’lláh',
};

const aqdasSections = {'Paragraphs': 'Text', 'QAs': 'Questions and Answers', 'Notes': 'Notes'};

const prayerAuthors = {1: 'The Báb', 2: 'Bahá’u’lláh', 3: '‘Abdu’l‑Bahá'};

const bookAuthors = {
  'hidden': 'Bahá’u’lláh',
  'gleanings': 'Bahá’u’lláh',
  'meditations': 'Bahá’u’lláh',
  'tablets': 'Bahá’u’lláh',
  'iqan': 'Bahá’u’lláh',
  'aqdas': 'Bahá’u’lláh',
  'saq': '‘Abdu’l‑Bahá',
  'days': 'Bahá’u’lláh',
  'ridvan': 'The Universal House of Justice',
};

/// Passages line up across languages by their numbering, as in BahaiPrayers.net's Matrix feeds (GTK `ALIGN`).
const _align = {
  'hidden': ['IsArabic', 'Number'],
  'gleanings': ['Number'],
  'meditations': ['Number'],
  'tablets': ['TabletNumber', 'Number'],
  'iqan': ['Part', 'Number'],
  'aqdas': ['AqdasSection', 'Number'],
  'saq': ['Number'],
};

class PackError implements Exception {
  PackError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Python's `str()` of a JSON value, for ids and numbers joined into keys and titles.
String pyStr(Object? v) => switch (v) {
      null => 'None',
      true => 'True',
      false => 'False',
      double d when d == d.truncateToDouble() && d.abs() < 1e16 => '${d.toInt()}.0',
      _ => '$v',
    };

/// The rows of one feed, checked (GTK `validate_feed()`); throws [PackError] if it is not usable.
List<Map<String, dynamic>> validateFeed(String key, Object? data, int language) {
  List<Object?>? rows;
  if (key == 'prayers') {
    if (data is! Map || data['IsInError'] == true) throw PackError('Prayer API returned an error');
    final p = data['Prayers'];
    rows = p is List ? p : null;
  } else if (key == 'aqdas') {
    if (data is! Map || (data['Language'] is Map ? data['Language']['Id'] : null) != language) {
      throw PackError('Unexpected Aqdas language');
    }
    rows = [];
    for (final section in aqdasSections.keys) {
      final entries = data[section];
      if (entries is! List || entries.isEmpty) throw PackError('Incomplete Aqdas collection');
      for (final entry in entries) {
        if (entry is! Map) throw PackError('Invalid Aqdas entry');
        rows.add({...entry.cast<String, dynamic>(), 'Id': '$section:${pyStr(entry['Id'])}', 'AqdasSection': section});
      }
    }
  } else {
    rows = data is List ? data : null;
  }
  if (rows == null || rows.isEmpty) throw PackError('No content returned for ${sectionNames[key]}');
  for (final row in rows) {
    if (row is! Map || !row.containsKey('Id') || row['Text'] is! String || row['LanguageId'] != language) {
      throw PackError('Unexpected language or content format');
    }
    if (key == 'hidden' && row['IsArabic'] is! bool) throw PackError('Invalid Hidden Words section');
    if (key == 'prayers' && row.containsKey('Tags') && row['Tags'] is! List) throw PackError('Invalid prayer categories');
  }
  return [for (final r in rows) (r as Map).cast<String, dynamic>()];
}

/// A pack as stored, or null if it is not a usable pack (GTK `local_pack()`).
Map<String, dynamic>? checkPack(Object? data, int language) {
  if (data is! Map || !data.containsKey('prayers')) return null;
  try {
    for (final e in data.entries) {
      if (!feeds.containsKey(e.key)) return null;
      validateFeed(e.key as String, e.value, language);
    }
  } on PackError {
    return null;
  } on TypeError {
    return null;
  }
  return data.cast<String, dynamic>();
}

// ----- text -----

final _blockTags = {'p', 'br', 'h1', 'h2', 'h3', 'div'};
final _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'rsquo': '’',
  'lsquo': '‘',
  'rdquo': '”',
  'ldquo': '“',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
};

String _unescape(String s) => s.replaceAllMapped(RegExp(r'&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
      final name = m[1]!;
      if (name.startsWith('#')) {
        final code = name[1] == 'x' || name[1] == 'X' ? int.tryParse(name.substring(2), radix: 16) : int.tryParse(name.substring(1));
        return code == null || code > 0x10FFFF ? m[0]! : String.fromCharCode(code);
      }
      return _named[name] ?? m[0]!;
    });

/// The text of a feed's HTML as plain paragraphs (GTK `plain()`): block tags start a paragraph, other tags are dropped.
String plain(String? html) {
  final value = html ?? '';
  final parts = StringBuffer();
  final tag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>|<!--.*?-->|<![^>]*>|<\?[^>]*>', dotAll: true);
  var at = 0;
  for (final m in tag.allMatches(value)) {
    parts.write(_unescape(value.substring(at, m.start)));
    at = m.end;
    if (m[2] != null && m[1] == '' && _blockTags.contains(m[2]!.toLowerCase())) parts.write('\n\n');
  }
  parts.write(_unescape(value.substring(at)));
  return parts.toString().replaceAll(RegExp(r'\n\s*\n'), '\n\n').trim();
}

/// Words, keeping apostrophes and hyphens inside them; dashes separate words (GTK `word_count()`).
int wordCount(String text) =>
    RegExp(r"[\p{L}\p{N}]+(?:[’‘ʼ'\-‑][\p{L}\p{N}]+)*", unicode: true).allMatches(text).length;

String roman(int number) {
  const numerals = [
    (1000, 'M'), (900, 'CM'), (500, 'D'), (400, 'CD'), (100, 'C'), (90, 'XC'), (50, 'L'), //
    (40, 'XL'), (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I'),
  ];
  final out = StringBuffer();
  for (final (value, letters) in numerals) {
    while (number >= value) {
      out.write(letters);
      number -= value;
    }
  }
  return out.toString();
}

String _or(Object? v, String fallback) => v == null || v == '' || v == false || v == 0 ? fallback : pyStr(v);

/// Author and place in the book (GTK `citation()`).
String? citation(String key, Map<String, dynamic> row) {
  String? author = bookAuthors[key];
  final number = row.containsKey('Number') ? row['Number'] : '';
  if (key == 'prayers') return prayerAuthors[row['AuthorId']];
  String where;
  switch (key) {
    case 'hidden':
      where = '${row['IsArabic'] == true ? 'Arabic' : 'Persian'} no. ${pyStr(number)}';
    case 'gleanings':
      where = _or(row['Roman'], pyStr(number));
    case 'meditations':
      where = number is int && number > 0 ? roman(number) : pyStr(number);
    case 'tablets':
      where = _or(row['Title'], 'Tablet ${pyStr(row.containsKey('TabletNumber') ? row['TabletNumber'] : '')}');
      final sub = row['SubTitle'];
      if (sub == 'Footnotes') {
        author = null;
      } else if (sub != null && sub != '' && sub != false) {
        where += ' (${pyStr(sub)})';
      }
    case 'iqan':
      where = 'Part ${pyStr(row.containsKey('Part') ? row['Part'] : '')}, no. ${pyStr(number)}';
    case 'aqdas':
      final section = row['AqdasSection'];
      where = {
        'Paragraphs': '¶${pyStr(number)}',
        'QAs': 'Question and Answer ${pyStr(number)}',
        'Notes': 'Note ${pyStr(number)}',
      }[section]!;
      if (section == 'Notes') author = null;
    case 'saq':
      where = 'chapter ${pyStr(number)}';
    case 'days':
      final day = row['HolyDay'];
      where = holyDays[day] ?? _or(day, '');
    case 'ridvan':
      return [?author, 'Riḍván ${pyStr(row.containsKey('Year') ? row['Year'] : '')}'.trim()]
          .where((p) => p.isNotEmpty)
          .join(', ');
    default:
      where = '';
  }
  return [?author, sectionNames[key], where].whereType<String>().where((p) => p.isNotEmpty).join(', ');
}

String? align(String key, Map<String, dynamic> row) {
  final fields = _align[key];
  return fields == null ? null : [key, for (final f in fields) pyStr(row[f])].join(':');
}

/// Python's `text.split()` joined by single spaces.
String _flat(String t) => t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

/// Python's `s[:n]` for a string of BMP characters (the converter refuses others; see [Passage]).
String _head(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// The passages of a pack (GTK `load_bahaiprayers()` for a downloaded language).
List<Passage> packPassages(Map<String, dynamic> pack, int language) {
  final result = <Passage>[];
  final prefix = language == 1 ? '' : '$language:';
  for (final key in feeds.keys) {
    if (!pack.containsKey(key)) continue;
    final rows = validateFeed(key, pack[key], language);
    for (var position = 1; position <= rows.length; position++) {
      final row = rows[position - 1];
      final text = plain(row['Text'] as String?);
      if (text.isEmpty) continue;
      final group = key == 'hidden'
          ? (row['IsArabic'] == true ? 'From the Arabic' : 'From the Persian')
          : bookNames[key] ?? 'Prayers';
      var tags = key == 'prayers'
          ? [for (final t in (row['Tags'] as List? ?? const [])) pyStr((t as Map)['Name'])]
          : [group];
      final number = row.containsKey('Roman') ? row['Roman'] : (row.containsKey('Number') ? row['Number'] : '');
      final opening = _flat(text);
      var title = key == 'prayers' ? _head(opening, 90) : '${pyStr(number)} · ${_head(opening, 72)}';
      var shelf = bookNames.containsKey(key) ? 'writings' : key;
      String? book;
      final inBooks = tags.where(prayerFeedBooks.contains).toList()..sort();
      if (key == 'prayers' && inBooks.isNotEmpty) {
        book = inBooks.first;
        shelf = 'writings';
        tags = [book];
        title = book;
      }
      String? subgroup = key == 'tablets'
          ? _or(row['SubTitle'], _or(row['Title'], 'Tablet ${pyStr(row.containsKey('TabletNumber') ? row['TabletNumber'] : '')}'))
          : key == 'iqan'
              ? 'Part ${pyStr(row.containsKey('Part') ? row['Part'] : '')}'
              : null;
      final references = <(String, String)>[];
      if (key == 'aqdas') {
        subgroup = aqdasSections[row['AqdasSection']];
        title = '${pyStr(number)} · ${_head(opening, 72)}';
        for (final section in aqdasSections.keys) {
          final values = row[section];
          if (values is! List) continue;
          for (final value in values) {
            final match = rows.where((r) => r['AqdasSection'] == section && r['Number'] == value).firstOrNull;
            if (match != null) references.add(('${prefix}aqdas:${pyStr(match['Id'])}', '${aqdasSections[section]} ${pyStr(value)}'));
          }
        }
        final aqdasNumber = row['AqdasNumber'];
        if (aqdasNumber != null && aqdasNumber != 0 && aqdasNumber != '' && aqdasNumber != false) {
          final target = rows.where((r) => r['AqdasSection'] == 'Paragraphs' && r['Number'] == aqdasNumber).firstOrNull;
          if (target != null) references.add(('${prefix}aqdas:${pyStr(target['Id'])}', 'Text ${pyStr(aqdasNumber)}'));
        }
      } else if (key == 'saq') {
        subgroup = '${pyStr(row.containsKey('PartNumber') ? row['PartNumber'] : '')} · ${pyStr(row.containsKey('PartTitle') ? row['PartTitle'] : '')}';
        title = '${pyStr(number)} · ${_or(row['Title'], _head(opening, 72))}';
      } else if (key == 'days') {
        final day = row['HolyDay'];
        subgroup = holyDays[day] ?? (row.containsKey('HolyDay') ? (day == null ? null : pyStr(day)) : 'Selections');
        title = '$position · ${_head(opening, 72)}';
      } else if (key == 'ridvan') {
        final year = pyStr(row.containsKey('Year') ? row['Year'] : '');
        subgroup = RegExp(r'^\d+$').hasMatch(year) ? '${int.parse(year) ~/ 10 * 10}s' : 'Messages';
        title = '$year · ${_or(row['Title'], 'Riḍván message')}';
      }
      final author = key == 'prayers' ? prayerAuthors[row['AuthorId']] : bookAuthors[key];
      final cite = [?citation(key, row), ?book].where((p) => p.isNotEmpty).join(', ');
      result.add(Passage(
        id: '$prefix$key:${pyStr(row['Id'])}',
        author: author,
        section: shelf,
        tags: tags,
        title: title,
        text: text,
        subgroup: subgroup,
        wordCount: wordCount(text),
        references: references,
        match: align(key, row),
        citation: cite,
      ));
    }
  }
  return [for (final p in result) withDirections(p)];
}

// ----- the Obligatory prayers section, the obligatory prayers' directions and the passage of the day -----

const obligatoryPrayers = ['Short Obligatory Prayer', 'Medium Obligatory Prayer', 'Long Obligatory Prayer'];
const aqdasOnPrayer = [6, 8, 10, 12, 13, 14];

/// The Obligatory prayers section: the three prayers, then the Kitáb-i-Aqdas paragraphs on obligatory prayer with the
/// notes and Questions and Answers they link to (GTK `obligatory()`), as [(group, ids)].
List<(String, List<String>)> obligatoryGroups(List<Passage> items) {
  final groups = <(String, List<String>)>[];
  final prayers = [
    for (final name in obligatoryPrayers)
      if (items.where((i) => i.section == 'prayers' && i.tags.contains(name)).firstOrNull case final p?) p.id,
  ];
  if (prayers.isNotEmpty) groups.add(('The three prayers', prayers));
  final byId = {for (final i in items) i.id: i};
  final guidance = <String, Passage>{};
  for (final number in aqdasOnPrayer) {
    final paragraph = items.where((i) => i.id.endsWith('aqdas:Paragraphs:$number')).firstOrNull;
    if (paragraph == null) continue;
    for (final p in [paragraph, for (final (target, _) in paragraph.references) ?byId[target]]) {
      guidance.putIfAbsent(p.id, () => p);
    }
  }
  if (guidance.isNotEmpty) {
    final parts = aqdasSections.values.toList();
    (int, int) order(Passage i) {
      final n = i.title.split(' · ').first;
      return (parts.indexOf(i.subgroup ?? ''), RegExp(r'^\d+$').hasMatch(n) ? int.parse(n) : 0);
    }

    // Python's sorted() is stable; so is this, by keeping the first-seen order for ties.
    final list = guidance.values.toList();
    final at = {for (var k = 0; k < list.length; k++) list[k].id: k};
    list.sort((a, b) {
      final (x, y) = (order(a), order(b));
      if (x.$1 != y.$1) return x.$1.compareTo(y.$1);
      if (x.$2 != y.$2) return x.$2.compareTo(y.$2);
      return at[a.id]!.compareTo(at[b.id]!);
    });
    groups.add(('Kitáb-i-Aqdas', [for (final p in list) p.id]));
  }
  return groups;
}

final _direction = RegExp(r'^(To be recited|God hath exempted|"The daily obligatory|\(|\d+\. )');

/// An obligatory prayer from a pack with its directions marked, shown in italics (GTK `directions()`, for texts that
/// are not bahai.org's).
Passage withDirections(Passage p) {
  if (!p.tags.any(obligatoryPrayers.contains)) return p;
  final spans = <(int, int)>[];
  var start = 0;
  for (final paragraph in p.text.split('\n\n')) {
    final text = paragraph.trim();
    if (start > 0 && text.isNotEmpty && (text.endsWith(':') || _direction.hasMatch(text))) {
      spans.add((start, start + paragraph.length));
    }
    start += paragraph.length + 2;
  }
  return spans.isEmpty ? p : p.copyWith(directions: spans);
}

const reflectionBooks = {'Gleanings from the Writings of Bahá’u’lláh', 'Prayers and Meditations'};

/// The passage-of-the-day order (GTK `passage_of_the_day()`): the short reflections, shuffled with Python's
/// `random.Random(1844)`.
List<String> dailyOrder(List<Passage> items) {
  final pool = [
    for (final i in items)
      if ((i.section == 'prayers' || i.section == 'hidden' || i.tags.any(reflectionBooks.contains)) && i.wordCount <= 500) i.id,
  ]..sort();
  final order = List.generate(pool.length, (k) => k);
  PythonRandom(1844).shuffle(order);
  return [for (final k in order) pool[k]];
}

/// Python's Mersenne Twister, as far as `random.Random(seed).shuffle()` needs it, so the passage of the day is the
/// same as in the GTK app.
class PythonRandom {
  PythonRandom(int seed) {
    _initByArray([seed]);
  }

  final _mt = List<int>.filled(624, 0);
  int _i = 625;

  void _initGenrand(int s) {
    _mt[0] = s & 0xffffffff;
    for (var i = 1; i < 624; i++) {
      final prev = _mt[i - 1] ^ (_mt[i - 1] >>> 30);
      _mt[i] = (_mul(1812433253, prev) + i) & 0xffffffff;
    }
    _i = 624;
  }

  void _initByArray(List<int> key) {
    _initGenrand(19650218);
    var i = 1, j = 0;
    for (var k = 624 > key.length ? 624 : key.length; k > 0; k--) {
      final prev = _mt[i - 1] ^ (_mt[i - 1] >>> 30);
      _mt[i] = ((_mt[i] ^ _mul(prev, 1664525)) + key[j] + j) & 0xffffffff;
      i++;
      j++;
      if (i >= 624) {
        _mt[0] = _mt[623];
        i = 1;
      }
      if (j >= key.length) j = 0;
    }
    for (var k = 623; k > 0; k--) {
      final prev = _mt[i - 1] ^ (_mt[i - 1] >>> 30);
      _mt[i] = ((_mt[i] ^ _mul(prev, 1566083941)) - i) & 0xffffffff;
      i++;
      if (i >= 624) {
        _mt[0] = _mt[623];
        i = 1;
      }
    }
    _mt[0] = 0x80000000;
  }

  /// (a * b) mod 2^32 without losing bits.
  static int _mul(int a, int b) {
    final lo = (a & 0xffff) * b;
    final hi = ((a >>> 16) * b) & 0xffff;
    return (lo + (hi << 16)) & 0xffffffff;
  }

  int _next() {
    if (_i >= 624) {
      for (var k = 0; k < 624; k++) {
        final y = (_mt[k] & 0x80000000) | (_mt[(k + 1) % 624] & 0x7fffffff);
        _mt[k] = _mt[(k + 397) % 624] ^ (y >>> 1) ^ ((y & 1) != 0 ? 0x9908b0df : 0);
      }
      _i = 0;
    }
    var y = _mt[_i++];
    y ^= y >>> 11;
    y ^= (y << 7) & 0x9d2c5680;
    y ^= (y << 15) & 0xefc60000;
    y ^= y >>> 18;
    return y & 0xffffffff;
  }

  int _bits(int k) => _next() >>> (32 - k);

  int _below(int n) {
    final k = n.bitLength;
    var r = _bits(k);
    while (r >= n) {
      r = _bits(k);
    }
    return r;
  }

  void shuffle(List<Object?> x) {
    for (var i = x.length - 1; i > 0; i--) {
      final j = _below(i + 1);
      final t = x[i];
      x[i] = x[j];
      x[j] = t;
    }
  }
}

/// The library file this app reads for a pack, in the converter's format (`assets/library/<id>.json`).
String packLibraryJson(Map<String, dynamic> pack, int language) {
  final items = packPassages(pack, language);
  return jsonEncode({
    'language': language,
    'items': [for (final p in items) p.toJson()],
    'daily': dailyOrder(items),
    'obligatory': [
      for (final (g, ids) in obligatoryGroups(items)) [g, ids],
    ],
  });
}
