/// The user-data store: everything a person makes in the app (highlights and their notes, saved passages and
/// collections, reading positions, Continue reading, Said/Fasted records) and the personal choices that should follow
/// them to another device, in one SQLite file, `userdata.sqlite`, beside `settings.json`.
///
/// Built to be synced one day (nothing here syncs yet):
/// * every record has a permanent id: a random UUIDv7, or a UUIDv5 of its meaning where two devices making "the same"
///   record must end up with one (`saved:<passage id>`, `pos:<work>`);
/// * every record carries `created_at`, `updated_at` (Unix ms), `hlc` (a hybrid logical clock stamp, see `ids.dart`),
///   the `device_id` that last changed it, and `deleted_at`: a deletion is a tombstone, never an erased row, so it can
///   reach other devices;
/// * no file paths are stored; passages are named by their stable ids.
///
/// The app keeps working on its in-memory [Settings]; [save] compares them with what is stored and writes only the
/// records that changed, in one transaction. [loadInto] puts the stored records back into a [Settings].
///
/// Moving in ([migrate]): the first start of a version with this store copies `settings.json` to
/// `settings.json.pre-userdata-<date>`, copies the marks into the store in one transaction, reads them back and checks
/// they are identical before committing. The keys that moved are then frozen in `settings.json` (see
/// [Settings.legacy]), so an older version opened on it still finds the marks as they were.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../settings/settings_store.dart';
import 'ids.dart';

/// The store's schema version (`PRAGMA user_version`).
const userDataSchema = 2;

/// `userdata_version` in `settings.json` once the marks have moved into the store. Not the store's schema version.
const movedMarker = 1;

/// Schema 2: the Study section's tables; highlight colour `magenta` became `pink` (five colours).

/// The columns every synced table has, after `id`.
const _sync =
    'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, hlc TEXT NOT NULL, device_id TEXT NOT NULL, '
    'deleted_at INTEGER';

/// Each synced table's own columns (after the common ones), in the order [_Row.values] holds them.
const _tables = <String, List<String>>{
  'passage_highlight': ['passage_id', 'start', 'end', 'words', 'color', 'note', 'created', 'sort'],
  'collection': ['name', 'sort'],
  'saved_passage': ['passage_id', 'collection_id', 'sort', 'collection_sort'],
  'reading_position': ['work_key', 'passage_id'],
  'recent_book': ['work_key', 'opened_at'],
  'day_record': ['kind', 'key', 'sort'],
  'user_pref': ['key', 'value'],
  // ----- Study (schema 2). Books are files identified by SHA-256; a "run" is one time through a book, and owns every
  // mark made in it. Positions are PDF points from the page's top-left corner; pages are 1-based.
  'doc_file': ['sha256', 'file_name', 'title', 'page_count', 'byte_size', 'pdf_doc_id'],
  'study_book': ['label', 'doc_id', 'current_run_id', 'sort', 'removed_at'],
  'study_run': ['book_id', 'ordinal', 'name', 'started_at', 'finished_at', 'locked'],
  'doc_highlight': [
    'run_id', 'doc_id', 'page', 'rects', 'char_start', 'char_end', 'quote', 'prefix', 'suffix', 'color', 'note', //
  ],
  'doc_bookmark': ['run_id', 'doc_id', 'page', 'y', 'name'],
  'doc_note': ['book_id', 'run_id', 'text'],
  'answer': [
    'run_id', 'doc_id', 'page', 'kind', 'x', 'y', 'w', 'h', 'pitch', 'lines', 'indent', 'size', 'context', //
    'slot_key', 'text',
  ],
  'doc_view': ['run_id', 'doc_id', 'page', 'offset', 'zoom'],
};

/// The Study tables, which are read and written record by record ([UserDataStore.put]) rather than from [Settings].
const studyTables = [
  'doc_file',
  'study_book',
  'study_run',
  'doc_highlight',
  'doc_bookmark',
  'doc_note',
  'answer',
  'doc_view',
];

const _schema =
    '''
CREATE TABLE IF NOT EXISTS passage_highlight (id TEXT PRIMARY KEY, $_sync,
  passage_id TEXT NOT NULL, start INTEGER NOT NULL, "end" INTEGER NOT NULL, words TEXT NOT NULL, color TEXT NOT NULL,
  note TEXT, created TEXT, sort INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS collection (id TEXT PRIMARY KEY, $_sync, name TEXT NOT NULL, sort INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS saved_passage (id TEXT PRIMARY KEY, $_sync,
  passage_id TEXT NOT NULL, collection_id TEXT, sort INTEGER NOT NULL, collection_sort INTEGER);
CREATE TABLE IF NOT EXISTS reading_position (id TEXT PRIMARY KEY, $_sync, work_key TEXT NOT NULL, passage_id TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS recent_book (id TEXT PRIMARY KEY, $_sync, work_key TEXT NOT NULL, opened_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS day_record (id TEXT PRIMARY KEY, $_sync, kind TEXT NOT NULL, key TEXT NOT NULL, sort INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS user_pref (id TEXT PRIMARY KEY, $_sync, key TEXT NOT NULL, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS local_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS doc_file (id TEXT PRIMARY KEY, $_sync, sha256 TEXT NOT NULL, file_name TEXT, title TEXT,
  page_count INTEGER, byte_size INTEGER, pdf_doc_id TEXT);
CREATE TABLE IF NOT EXISTS study_book (id TEXT PRIMARY KEY, $_sync, label TEXT, doc_id TEXT NOT NULL,
  current_run_id TEXT, sort INTEGER, removed_at INTEGER);
CREATE TABLE IF NOT EXISTS study_run (id TEXT PRIMARY KEY, $_sync, book_id TEXT NOT NULL, ordinal INTEGER NOT NULL,
  name TEXT NOT NULL, started_at INTEGER, finished_at INTEGER, locked INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS doc_highlight (id TEXT PRIMARY KEY, $_sync, run_id TEXT NOT NULL, doc_id TEXT NOT NULL,
  page INTEGER NOT NULL, rects TEXT NOT NULL, char_start INTEGER, char_end INTEGER, quote TEXT, prefix TEXT,
  suffix TEXT, color TEXT NOT NULL, note TEXT);
CREATE TABLE IF NOT EXISTS doc_bookmark (id TEXT PRIMARY KEY, $_sync, run_id TEXT NOT NULL, doc_id TEXT NOT NULL,
  page INTEGER NOT NULL, y REAL, name TEXT);
CREATE TABLE IF NOT EXISTS doc_note (id TEXT PRIMARY KEY, $_sync, book_id TEXT NOT NULL, run_id TEXT NOT NULL,
  text TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS answer (id TEXT PRIMARY KEY, $_sync, run_id TEXT NOT NULL, doc_id TEXT NOT NULL,
  page INTEGER NOT NULL, kind TEXT NOT NULL, x REAL, y REAL, w REAL, h REAL, pitch REAL, lines INTEGER,
  indent REAL, size REAL, context TEXT, slot_key TEXT, text TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS doc_view (id TEXT PRIMARY KEY, $_sync, run_id TEXT NOT NULL, doc_id TEXT NOT NULL,
  page INTEGER, offset REAL, zoom REAL);
''';

/// The personal choices kept as `user_pref` records, by their `settings.json` key.
const prefKeys = ['prayer', 'long_period', 'keep_records', 'counter_target', 'highlight_color'];

class _Row {
  _Row(this.values, this.createdAt, {this.deleted = false});
  final List<Object?> values;
  final int createdAt;
  final bool deleted;
}

/// The store could not be used; the app keeps its marks in `settings.json` as before.
class UserDataProblem implements Exception {
  UserDataProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

class UserDataStore {
  UserDataStore._(this.file, this._db, this.hlc);

  /// `userdata.sqlite`.
  final File file;
  final Database _db;
  final Hlc hlc;

  /// What is stored, by table and id (tombstones included), so [save] writes only what changed.
  final Map<String, Map<String, _Row>> _cache = {};

  /// For tests: the clock, in Unix ms.
  int Function() clock = () => DateTime.now().millisecondsSinceEpoch;

  String get deviceId => hlc.device;

  /// The store beside [settingsFile]. Throws [UserDataProblem] if SQLite or the file cannot be opened.
  static UserDataStore open(File settingsFile) {
    final file = File('${settingsFile.parent.path}/userdata.sqlite');
    Database db;
    try {
      file.parent.createSync(recursive: true);
      db = sqlite3.open(file.path);
    } catch (e) {
      throw UserDataProblem('the store could not be opened ($e)');
    }
    try {
      db.execute('PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL;');
      final version = db.select('PRAGMA user_version').first.values.first as int;
      if (version > userDataSchema) {
        throw UserDataProblem('it was written by a newer version of the app (schema $version)');
      }
      db.execute(_schema);
      String? meta(String k) =>
          db.select('SELECT value FROM local_meta WHERE key = ?', [k]).firstOrNull?['value'] as String?;
      var device = meta('device_id');
      if (device == null) {
        device = uuidV7();
        db.execute('INSERT INTO local_meta (key, value) VALUES (?, ?)', ['device_id', device]);
      }
      final clock = Hlc(device);
      final last = meta('hlc');
      if (last != null) clock.observe(last);
      final store = UserDataStore._(file, db, clock);
      if (version == 1) store._fiveColours();
      db.execute('PRAGMA user_version = $userDataSchema');
      store._fill();
      return store;
    } catch (e) {
      db.close();
      if (e is UserDataProblem) rethrow;
      throw UserDataProblem('the store could not be read ($e)');
    }
  }

  void close() => _db.close();

  /// Schema 1 → 2: the fourth highlight colour, `magenta`, is called `pink` now that there are five.
  void _fiveColours() {
    final now = clock();
    final stamp = hlc.next(now);
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        "UPDATE passage_highlight SET color = 'pink', updated_at = ?, hlc = ?, device_id = ? WHERE color = 'magenta'",
        [now, stamp, deviceId],
      );
      _db.execute(
        "UPDATE user_pref SET value = '\"pink\"', updated_at = ?, hlc = ?, device_id = ? "
        "WHERE key = 'highlight_color' AND value = '\"magenta\"'",
        [now, stamp, deviceId],
      );
      _db.execute('INSERT OR REPLACE INTO local_meta (key, value) VALUES (?, ?)', ['hlc', hlc.stamp]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ----- records, one at a time (the Study tables) -----

  bool _inTransaction = false;

  /// Runs [body] in one transaction: every [put] and [remove] in it is stored together or not at all.
  T batch<T>(T Function() body) {
    if (_inTransaction) return body();
    late T result;
    _inTransaction = true;
    try {
      _transaction(() => result = body());
    } finally {
      _inTransaction = false;
    }
    return result;
  }

  /// The live records of [table], each with its `id`, `created_at` and `updated_at`.
  List<Map<String, Object?>> records(String table) {
    final cols = _tables[table]!;
    return [
      for (final MapEntry(key: id, value: row) in _cache[table]!.entries)
        if (!row.deleted)
          {'id': id, 'created_at': row.createdAt, for (var i = 0; i < cols.length; i++) cols[i]: row.values[i]},
    ];
  }

  /// One live record, or null.
  Map<String, Object?>? record(String table, String id) {
    final row = _cache[table]![id];
    if (row == null || row.deleted) return null;
    final cols = _tables[table]!;
    return {'id': id, 'created_at': row.createdAt, for (var i = 0; i < cols.length; i++) cols[i]: row.values[i]};
  }

  /// Writes a record (all of [table]'s columns, from [values]; missing ones are null) if it changed. A tombstoned
  /// record with the same id comes back.
  void put(String table, String id, Map<String, Object?> values) {
    final cols = _tables[table]!;
    final list = [for (final c in cols) values[c]];
    batch(() => _put(table, id, list, clock()));
  }

  /// Makes a record a tombstone.
  void remove(String table, String id) {
    final row = _cache[table]![id];
    if (row == null || row.deleted) return;
    batch(() {
      final now = clock();
      _db.execute('UPDATE $table SET deleted_at = ?, updated_at = ?, hlc = ?, device_id = ? WHERE id = ?', [
        now,
        now,
        hlc.next(now),
        deviceId,
        id,
      ]);
      _cache[table]![id] = _Row(row.values, row.createdAt, deleted: true);
    });
  }

  void _put(String table, String id, List<Object?> values, int now) {
    final rows = _cache[table]!;
    final old = rows[id];
    if (old != null && !old.deleted && _same(old.values, values)) return;
    final cols = _tables[table]!;
    final quoted = cols.map((c) => '"$c"').join(', ');
    final marks = List.filled(cols.length, '?').join(', ');
    final created = old?.createdAt ?? now;
    _db.execute(
      'INSERT OR REPLACE INTO $table (id, created_at, updated_at, hlc, device_id, deleted_at, $quoted) '
      'VALUES (?, ?, ?, ?, ?, NULL, $marks)',
      [id, created, now, hlc.next(now), deviceId, ...values],
    );
    rows[id] = _Row(values, created);
  }

  /// When the marks were moved in from `settings.json` (ISO time), or null if they have not been yet.
  String? get migratedAt =>
      _db.select('SELECT value FROM local_meta WHERE key = ?', ['migrated_at']).firstOrNull?['value'] as String?;

  void _fill() {
    _cache.clear();
    for (final MapEntry(key: table, value: cols) in _tables.entries) {
      final rows = _cache[table] = {};
      final quoted = cols.map((c) => '"$c"').join(', ');
      for (final r in _db.select('SELECT id, created_at, deleted_at, $quoted FROM $table')) {
        rows[r['id'] as String] = _Row(
          [for (final c in cols) r[c]],
          r['created_at'] as int,
          deleted: r['deleted_at'] != null,
        );
      }
    }
  }

  Iterable<(String, List<Object?>)> _live(String table) sync* {
    for (final e in _cache[table]!.entries) {
      if (!e.value.deleted) yield (e.key, e.value.values);
    }
  }

  // ----- reading -----

  /// The stored records in `settings.json`'s shape (the [Settings.userDataKeys]), with `uid` on highlights and
  /// collections.
  Map<String, Object> toJson() {
    int bySort(List<Object?> a, List<Object?> b, int i) => (a[i] as int).compareTo(b[i] as int);

    final highlights = _live('passage_highlight').toList()
      ..sort((a, b) {
        final c = bySort(a.$2, b.$2, 7);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final collections = _live('collection').toList()
      ..sort((a, b) {
        final c = bySort(a.$2, b.$2, 1);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final saved = _live('saved_passage').toList()
      ..sort((a, b) {
        final c = bySort(a.$2, b.$2, 2);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final liveCollections = {for (final c in collections) c.$1};
    List<String> itemsOf(String uid) {
      final items = [
        for (final s in saved)
          if (s.$2[1] == uid) s,
      ]..sort((a, b) => ((a.$2[3] as int?) ?? 0).compareTo((b.$2[3] as int?) ?? 0));
      return [for (final s in items) s.$2[0] as String];
    }

    final recent = _live('recent_book').toList()..sort((a, b) => (b.$2[1] as int).compareTo(a.$2[1] as int));
    List<String> records(String kind) {
      final rows = [
        for (final r in _live('day_record'))
          if (r.$2[0] == kind) r,
      ]..sort((a, b) => bySort(a.$2, b.$2, 2));
      return [for (final r in rows) r.$2[1] as String];
    }

    final out = <String, Object>{
      'highlights': [
        for (final (uid, v) in highlights)
          {
            'id': v[0]!,
            'start': v[1]!,
            'end': v[2]!,
            'words': v[3]!,
            'color': v[4]!,
            'created': ?v[6],
            'note': ?v[5],
            'uid': uid,
          },
      ],
      'saved': [for (final s in saved) s.$2[0] as String],
      'positions': {for (final (_, v) in _live('reading_position')) v[0] as String: v[1] as String},
      'recent': [for (final r in recent) r.$2[0] as String],
      'records': {'said': records('said'), 'fasted': records('fasted')},
      'collections': [
        for (final (uid, v) in collections)
          if (liveCollections.contains(uid)) {'name': v[0]!, 'items': itemsOf(uid), 'uid': uid},
      ],
    };
    for (final (_, v) in _live('user_pref')) {
      if (prefKeys.contains(v[0])) {
        final value = jsonDecode(v[1] as String);
        if (value != null) out[v[0] as String] = value;
      }
    }
    return out;
  }

  /// Replaces the [Settings.userDataKeys] of [into] with what is stored, cleaned as `settings.json` would be.
  void loadInto(Settings into) {
    final clean = Settings.fromJson(toJson());
    into
      ..highlights = clean.highlights
      ..saved = clean.saved
      ..collections = clean.collections
      ..positions = clean.positions
      ..recent = clean.recent
      ..said = clean.said
      ..fasted = clean.fasted
      ..prayer = clean.prayer
      ..longPeriod = clean.longPeriod
      ..keepRecords = clean.keepRecords
      ..counterTarget = clean.counterTarget
      ..highlightColor = clean.highlightColor;
  }

  // ----- writing -----

  /// Stores [from]'s marks: records that changed are written, records that are gone become tombstones, all in one
  /// transaction. Highlights and collections that have no `uid` yet are given one (in [from] too).
  void save(Settings from) => _transaction(() => _write(from));

  void _transaction(void Function() body) {
    final stamp = hlc.stamp;
    _db.execute('BEGIN IMMEDIATE');
    try {
      body();
      if (hlc.stamp != stamp) {
        _db.execute('INSERT OR REPLACE INTO local_meta (key, value) VALUES (?, ?)', ['hlc', hlc.stamp]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      _fill(); // the cache may hold rows that were rolled back
      rethrow;
    }
  }

  void _write(Settings s) {
    final now = clock();

    // Highlights: a random id each, given once.
    for (var i = 0; i < s.highlights.length; i++) {
      if (s.highlights[i].uid == null) s.highlights[i] = s.highlights[i].withUid(uuidV7());
    }
    final hOrder = _order([for (final h in s.highlights) h.uid!], 'passage_highlight', 7, now);
    _sync('passage_highlight', {
      for (final h in s.highlights) h.uid!: [h.id, h.start, h.end, h.words, h.color, h.note, h.created, hOrder[h.uid!]],
    }, now);

    // Collections: named by their first name, so two devices creating the same collection make one.
    for (final c in s.collections) {
      c.uid ??= uuidV5('collection:${c.name.toLowerCase()}');
    }
    final collections = <String, Collection>{};
    for (final c in s.collections) {
      collections.putIfAbsent(c.uid!, () => c);
    }
    final cOrder = _order(collections.keys.toList(), 'collection', 1, now);
    _sync('collection', {
      for (final MapEntry(key: uid, value: c) in collections.entries) uid: [c.name, cOrder[uid]],
    }, now);

    // Saved passages, each in one collection at most (the first that lists it); a passage filed in a collection is
    // saved, as `cleanCollections()` makes it.
    final filedIn = <String, String>{};
    final inCollection = <String, List<String>>{};
    for (final MapEntry(key: uid, value: c) in collections.entries) {
      for (final item in c.items) {
        if (filedIn.containsKey(item)) continue;
        filedIn[item] = uid;
        (inCollection[uid] ??= []).add(item);
      }
    }
    final savedIds = <String>[
      ...{...s.saved, ...filedIn.keys},
    ];
    String savedId(String passage) => uuidV5('saved:$passage');
    final sOrder = _order([for (final p in savedIds) savedId(p)], 'saved_passage', 2, now);
    final ciOrder = <String, int>{};
    for (final MapEntry(key: uid, value: items) in inCollection.entries) {
      final ids = [for (final p in items) savedId(p)];
      final existing = {
        for (final id in ids)
          if (_cache['saved_passage']![id] case final r? when !r.deleted && r.values[1] == uid) id: r.values[3] as int?,
      };
      ciOrder.addAll(
        _stamps(ids, {
          for (final e in existing.entries)
            if (e.value != null) e.key: e.value!,
        }, now),
      );
    }
    _sync('saved_passage', {
      for (final p in savedIds)
        savedId(p): [p, filedIn[p], sOrder[savedId(p)], filedIn.containsKey(p) ? ciOrder[savedId(p)] : null],
    }, now);

    _sync('reading_position', {
      for (final MapEntry(key: work, value: passage) in s.positions.entries) uuidV5('pos:$work'): [work, passage],
    }, now);

    // Continue reading, newest first: opened_at grows towards the front.
    final recentIds = [for (final w in s.recent) uuidV5('recent:$w')];
    final rOrder = _order(recentIds.reversed.toList(), 'recent_book', 1, now);
    _sync('recent_book', {
      for (final w in s.recent) uuidV5('recent:$w'): [w, rOrder[uuidV5('recent:$w')]],
    }, now);

    final days = <String, List<Object?>>{};
    for (final (kind, list) in [('said', s.said), ('fasted', s.fasted)]) {
      final ids = <String>[];
      final keys = <String, String>{};
      for (final k in list) {
        final id = uuidV5('$kind:$k');
        if (keys.containsKey(id)) continue;
        keys[id] = k;
        ids.add(id);
      }
      final order = _order(ids, 'day_record', 2, now);
      for (final id in ids) {
        days[id] = [kind, keys[id], order[id]];
      }
    }
    _sync('day_record', days, now);

    final prefs = s.userDataJson();
    _sync('user_pref', {
      for (final k in prefKeys)
        if (prefs.containsKey(k)) uuidV5('pref:$k'): [k, jsonEncode(prefs[k])],
    }, now);
  }

  /// Sort stamps for [ids] in this order, keeping each stored stamp (column [col] of [table]) that still fits.
  Map<String, int> _order(List<String> ids, String table, int col, int now) {
    final rows = _cache[table]!;
    return _stamps(ids, {
      for (final id in ids)
        if (rows[id] case final r? when !r.deleted && r.values[col] is int) id: r.values[col] as int,
    }, now);
  }

  /// Strictly increasing stamps along [ids]. A stored stamp is kept while it is larger than the one before it, so a
  /// reorder or insertion rewrites as few records as possible; a new or moved record gets the current time (or just
  /// after the record before it).
  static Map<String, int> _stamps(List<String> ids, Map<String, int> old, int now) {
    final out = <String, int>{};
    int? prev;
    for (final id in ids) {
      final s = old[id];
      final v = s != null && (prev == null || s > prev) ? s : (prev == null || now > prev ? now : prev + 1);
      out[id] = prev = v;
    }
    return out;
  }

  /// Makes [table] hold exactly [want] (id → values): changed or new records are written, records not wanted become
  /// tombstones.
  void _sync(String table, Map<String, List<Object?>> want, int now) {
    final rows = _cache[table]!;
    for (final MapEntry(key: id, value: values) in want.entries) {
      _put(table, id, values, now);
    }
    for (final MapEntry(key: id, value: old) in rows.entries.toList()) {
      if (old.deleted || want.containsKey(id)) continue;
      _db.execute('UPDATE $table SET deleted_at = ?, updated_at = ?, hlc = ?, device_id = ? WHERE id = ?', [
        now,
        now,
        hlc.next(now),
        deviceId,
        id,
      ]);
      rows[id] = _Row(old.values, old.createdAt, deleted: true);
    }
  }

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ----- moving in from settings.json -----

  /// Moves [settings]' marks in, once: keeps a copy of [settingsFile] (if it exists), writes every record, reads them
  /// back and compares them with [settings]; only an exact match is committed. Throws [UserDataProblem] (nothing
  /// stored) otherwise. Afterwards [settings] has [Settings.userdataVersion] set and the moved keys frozen in
  /// [Settings.legacy]; the caller saves `settings.json`.
  Future<void> migrate(Settings settings, File settingsFile) async {
    if (migratedAt != null) return;
    final before = Settings.fromJson(settings.userDataJson()).userDataJson();
    // What the file itself says, kept unchanged in it (an older version reads it as it wrote it: `magenta`, say).
    var frozen = before;
    if (await settingsFile.exists()) {
      try {
        final raw = jsonDecode(await settingsFile.readAsString());
        if (raw is Map && raw['userdata_version'] == null) {
          frozen = {
            for (final k in Settings.userDataKeys)
              if (raw[k] != null) k: raw[k] as Object,
          };
        }
      } on FormatException {
        // an unreadable file was set aside by SettingsStore.load(); keep the cleaned values
      }
      final day = DateTime.now().toIso8601String().substring(0, 10);
      var copy = File('${settingsFile.path}.pre-userdata-$day');
      for (var n = 1; await copy.exists(); n++) {
        copy = File('${settingsFile.path}.pre-userdata-$day.$n');
      }
      await settingsFile.copy(copy.path);
    }
    try {
      _transaction(() {
        _write(settings);
        final stored = toJson();
        for (final h in stored['highlights'] as List) {
          (h as Map).remove('uid');
        }
        for (final c in stored['collections'] as List) {
          (c as Map).remove('uid');
        }
        final after = Settings.fromJson(stored).userDataJson();
        if (canonicalJson(after) != canonicalJson(before)) {
          throw UserDataProblem('the stored copy did not match');
        }
        _db.execute('INSERT OR REPLACE INTO local_meta (key, value) VALUES (?, ?)', [
          'migrated_at',
          DateTime.now().toUtc().toIso8601String(),
        ]);
      });
    } on UserDataProblem {
      rethrow;
    } catch (e) {
      throw UserDataProblem('the marks could not be stored ($e)');
    }
    settings
      ..legacy = Map.of(frozen)
      ..userdataVersion = movedMarker;
  }

  /// For tests and checks: counts of live records by table.
  Map<String, int> counts() => {
    for (final t in _tables.keys)
      if (!studyTables.contains(t)) t: _live(t).length,
  };

  /// For tests and checks: one record's sync columns.
  Map<String, Object?>? syncInfo(String table, String id) {
    final r = _db.select('SELECT created_at, updated_at, hlc, device_id, deleted_at FROM $table WHERE id = ?', [id]);
    return r.isEmpty ? null : Map.of(r.first);
  }
}

/// JSON with object keys sorted (and Said/Fasted lists without repeats), for comparing two stores' contents.
String canonicalJson(Object? value) {
  Object? norm(Object? v) => switch (v) {
    Map m => {for (final k in (m.keys.map((k) => '$k').toList()..sort())) k: norm(m[k])},
    List l => [for (final x in l) norm(x)],
    _ => v,
  };
  final v = norm(value);
  if (v is Map && v['records'] is Map) {
    final r = v['records'] as Map;
    v['records'] = {for (final e in r.entries) e.key: e.value is List ? (e.value as List).toSet().toList() : e.value};
  }
  return jsonEncode(v);
}
