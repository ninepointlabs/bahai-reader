import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/core/userdata/ids.dart';
import 'package:bahai_reader/core/userdata/userdata_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'disk_bundle.dart';
import 'helpers/stored.dart';
import 'helpers/temp.dart';

/// A settings file as the app wrote it before the user-data store: marks of every kind, personal choices and device
/// settings.
Map<String, Object?> before() => {
  'theme': 'sepia',
  'language': 1,
  'size': 24,
  'highlight_color': 'green',
  'highlights': [
    {
      'id': 'hidden:2',
      'start': 0,
      'end': 9,
      'words': 'O SON OF ',
      'color': 'green',
      'created': '2026-11-01',
      'note': 'First',
    },
    {'id': 'hidden:1', 'start': 3, 'end': 8, 'words': 'SON O', 'color': 'magenta'},
    {'id': '90:hidden:7400', 'start': 1, 'end': 4, 'words': 'abc', 'color': 'blue', 'created': '2026-11-03T10:00:00'},
  ],
  'saved': ['iqan:1', 'hidden:2', 'gleanings:1', 'prayers:15692'],
  'positions': {'Riḍván Messages': 'ridvan:1019', 'The Hidden Words': 'hidden:7'},
  'recent': ['The Hidden Words', 'Riḍván Messages', 'God Passes By'],
  'imported_gtk': true,
  'prayer': 'medium',
  'long_period': 'noon',
  'keep_records': false,
  'records': {
    'said': ['2026-11-15:medium:morning', '2026-11-15:medium:noon'],
    'fasted': ['2026-03-02'],
  },
  'counter_target': 19,
  'reminders': {'prayer': true},
  'reminders_sent': ['2026-11-15:short:noon:opens'],
  'keep_running': false,
  'collections': [
    {
      'name': 'Evening',
      'items': ['prayers:15692'],
    },
    {
      'name': 'Morning',
      'items': ['hidden:2', 'gleanings:1'],
    },
  ],
  'expanded': {'prayers/Healing': false},
  'last': 'hidden:2',
  'section': 'writings',
  'book': 'The Hidden Words',
  'gtk_import': {'at': '2026-11-16T10:00:00', 'status': 'imported'},
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('br-userdata-'));
  tearDown(() => removeTemp(dir));

  File settingsFile() => File('${dir.path}/settings.json');
  Future<AppState> start() => AppState.create(
    repository: LibraryRepository(bundle: DiskBundle()),
    store: SettingsStore(settingsFile()),
  );
  Map<String, Object?> onDisk() => (jsonDecode(settingsFile().readAsStringSync()) as Map).cast();

  /// The user-data part of a settings map, cleaned the way the app reads it.
  String marksOf(Map<String, Object?> json) => canonicalJson(Settings.fromJson(json).userDataJson());

  group('ids', () {
    test('UUIDv5 is RFC 9562 (python.org in the DNS namespace) and the same on every call', () {
      expect(uuidV5('python.org', '6ba7b810-9dad-11d1-80b4-00c04fd430c8'), '886313e1-3b8a-5372-9b90-0c9aee199e5d');
      expect(uuidV5('saved:hidden:2'), uuidV5('saved:hidden:2'));
      expect(uuidV5('saved:hidden:2'), isNot(uuidV5('saved:hidden:3')));
    });

    test('UUIDv7 carries its time and version, and is random', () {
      final at = DateTime.utc(2026, 11, 20, 12);
      final a = uuidV7(at), b = uuidV7(at);
      expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(int.parse(a.replaceAll('-', '').substring(0, 12), radix: 16), at.millisecondsSinceEpoch);
      expect(a, isNot(b));
    });

    test('the hybrid clock orders changes within a millisecond and after a clock that went back', () {
      final c = Hlc('dev');
      final s1 = c.next(1000), s2 = c.next(1000), s3 = c.next(900), s4 = c.next(2000);
      expect([s1, s2, s3, s4], orderedEquals(([s1, s2, s3, s4]..sort())));
      expect({s1, s2, s3, s4}, hasLength(4));
      c.observe(Hlc('other', wall: 5000, counter: 3).stamp);
      expect(c.next(2001).compareTo(Hlc('other', wall: 5000, counter: 3).stamp), greaterThan(0));
    });
  });

  test('first start moves every mark into the store, unchanged, and keeps settings.json as it was', () async {
    final original = const JsonEncoder.withIndent(' ').convert(before());
    settingsFile().writeAsStringSync(original);
    final s = await start();

    // In memory: the same marks as before.
    expect(canonicalJson(s.settings.userDataJson()), marksOf(before()));
    // In the store, read by a connection of its own: the same marks, in the same order, in the GTK shapes.
    expect(canonicalJson(storedMarks(settingsFile())), marksOf(before()));
    expect(s.userData!.counts(), {
      'passage_highlight': 3,
      'collection': 2,
      'saved_passage': 4,
      'reading_position': 2,
      'recent_book': 3,
      'day_record': 3,
      'user_pref': 5,
    });
    // A byte-for-byte copy of the old file.
    final day = DateTime.now().toIso8601String().substring(0, 10);
    expect(File('${settingsFile().path}.pre-userdata-$day').readAsStringSync(), original);
    // settings.json: device settings as before, the moved keys frozen as they were, and the version.
    final disk = onDisk();
    expect(disk['userdata_version'], 1);
    for (final k in Settings.userDataKeys) {
      expect(jsonEncode(disk[k]), jsonEncode((Settings.fromJson(before()).userDataJson())[k]), reason: k);
    }
    for (final k in ['theme', 'size', 'reminders', 'reminders_sent', 'expanded', 'last', 'section', 'book']) {
      expect(disk[k], before()[k], reason: k);
    }
    // Every record carries the sync columns.
    final info = s.userData!.syncInfo('saved_passage', uuidV5('saved:hidden:2'))!;
    expect(info['device_id'], s.userData!.deviceId);
    expect(info['deleted_at'], isNull);
    expect(info['hlc'], endsWith(s.userData!.deviceId));
    expect(info['created_at'], isA<int>());
    await s.marksReady;
    s.dispose();
  });

  test('changes after the move are kept in the store across starts; settings.json copies stay frozen', () async {
    settingsFile().writeAsStringSync(jsonEncode(before()));
    var s = await start();
    final frozen = {for (final k in Settings.userDataKeys) k: jsonEncode(onDisk()[k])};
    final lib = s.library!;
    await s.addHighlight(lib.byId['hidden:3']!, 0, 5, color: 'blue', note: 'New');
    await s.removeHighlight(s.settings.highlights.firstWhere((h) => h.id == 'hidden:1'));
    await s.updateHighlight(s.settings.highlights.firstWhere((h) => h.id == 'hidden:2'), note: 'Edited');
    await s.toggleSaved(lib.byId['gleanings:1']!); // was saved, in Morning
    await s.createCollection('Night');
    await s.renameCollection('Evening', 'Dusk');
    await s.setPrayer('long');
    await s.setTheme('dark');
    final book = lib.books.firstWhere((w) => w.title == 'God Passes By');
    s.rememberPosition(book, book.passages.first);
    final now = canonicalJson(s.settings.userDataJson());
    await s.marksReady;
    s.dispose();

    s = await start();
    expect(canonicalJson(s.settings.userDataJson()), now);
    expect(s.settings.highlights.where((h) => h.id == 'hidden:2').single.note, 'Edited');
    expect(s.settings.highlights.any((h) => h.id == 'hidden:1'), isFalse);
    expect(s.settings.saved, isNot(contains('gleanings:1')));
    expect([for (final c in s.settings.collections) c.name], ['Dusk', 'Morning', 'Night']);
    expect(s.settings.collections.first.uid, uuidV5('collection:evening'), reason: 'a rename keeps the id');
    expect(s.settings.prayer, 'long');
    expect(s.settings.theme, 'dark');
    for (final k in Settings.userDataKeys) {
      expect(jsonEncode(onDisk()[k]), frozen[k], reason: '$k stays as it was at the move');
    }
    await s.marksReady;
    s.dispose();
  });

  test('a deletion is a tombstone; saving again unchanged writes nothing; saving again revives it', () async {
    settingsFile().writeAsStringSync(jsonEncode(before()));
    final s = await start();
    final data = s.userData!;
    final id = uuidV5('saved:iqan:1');
    final first = data.syncInfo('saved_passage', id)!;
    await s.removeSaved('iqan:1');
    final gone = data.syncInfo('saved_passage', id)!;
    expect(gone['deleted_at'], isNotNull, reason: 'kept, so the deletion can reach another device');
    expect((gone['hlc'] as String).compareTo(first['hlc'] as String), greaterThan(0));
    await s.save();
    expect(data.syncInfo('saved_passage', id), gone, reason: 'nothing changed, nothing written');
    final h = s.settings.highlights.first.uid!;
    final hInfo = data.syncInfo('passage_highlight', h);
    await s.save();
    expect(data.syncInfo('passage_highlight', h), hInfo);
    await s.toggleSaved(s.library!.byId['iqan:1']!);
    final back = data.syncInfo('saved_passage', id)!;
    expect(back['deleted_at'], isNull);
    expect(back['created_at'], first['created_at'], reason: 'the same record, brought back');
    await s.marksReady;
    s.dispose();
  });

  test('two devices saving the same passage make the same record; their devices differ', () async {
    final a = Directory('${dir.path}/a')..createSync(), b = Directory('${dir.path}/b')..createSync();
    final ids = <String>[];
    for (final d in [a, b]) {
      final s = await AppState.create(
        repository: LibraryRepository(bundle: DiskBundle()),
        store: SettingsStore(File('${d.path}/settings.json')),
      );
      await s.toggleSaved(s.library!.byId['hidden:2']!);
      expect(s.userData!.syncInfo('saved_passage', uuidV5('saved:hidden:2')), isNotNull);
      ids.add(s.userData!.deviceId);
      await s.marksReady;
      s.dispose();
    }
    expect(ids.toSet(), hasLength(2));
  });

  test('marks made by an older version after the move are merged in, nothing lost', () async {
    settingsFile().writeAsStringSync(jsonEncode(before()));
    var s = await start();
    await s.addHighlight(s.library!.byId['hidden:3']!, 0, 5, note: 'Made in 1.1');
    await s.marksReady;
    s.dispose();
    // An older version opens the file: it sees the frozen marks, adds one, and writes the file without the version.
    final older = onDisk()..remove('userdata_version');
    (older['highlights'] as List).add({
      'id': 'hidden:4',
      'start': 0,
      'end': 3,
      'words': 'O S',
      'color': 'yellow',
      'note': 'Made in 1.0',
    });
    (older['saved'] as List).add('hidden:4');
    settingsFile().writeAsStringSync(jsonEncode(older));

    s = await start();
    final notes = {for (final h in s.settings.highlights) h.id: h.note};
    expect(notes['hidden:3'], 'Made in 1.1');
    expect(notes['hidden:4'], 'Made in 1.0');
    expect(notes['hidden:2'], 'First');
    expect(s.settings.saved, contains('hidden:4'));
    expect(onDisk()['userdata_version'], 1);
    expect(storedMarks(settingsFile())['saved'], contains('hidden:4'));
    await s.marksReady;
    s.dispose();
  });

  test(
    'if the store cannot be opened, the marks stay in settings.json, it says so, and the next start moves them',
    () async {
      settingsFile().writeAsStringSync(jsonEncode(before()));
      final blocker = Directory('${dir.path}/userdata.sqlite')..createSync();
      var s = await start();
      expect(s.userData, isNull);
      expect(s.notice, contains('kept in the settings file this time'));
      await s.toggleSaved(s.library!.byId['hidden:3']!);
      expect(onDisk()['userdata_version'], isNull);
      expect(onDisk()['saved'], contains('hidden:3'), reason: 'saved the old way');
      await s.marksReady;
      s.dispose();

      blocker.deleteSync();
      s = await start();
      expect(s.userData, isNotNull);
      expect(storedMarks(settingsFile())['saved'], contains('hidden:3'));
      await s.marksReady;
      s.dispose();
    },
  );

  test('a store from a newer version is left alone; the marks stay in settings.json', () async {
    settingsFile().writeAsStringSync(jsonEncode(before()));
    sqlite3.open('${dir.path}/userdata.sqlite')
      ..execute('PRAGMA user_version = 99')
      ..close();
    final s = await start();
    expect(s.userData, isNull);
    expect(s.notice, contains('newer version'));
    expect(canonicalJson(s.settings.userDataJson()), marksOf(before()));
    await s.marksReady;
    s.dispose();
  });

  test('a fresh install starts an empty store and keeps the version in settings.json', () async {
    final s = await start();
    expect(s.userData!.counts()['passage_highlight'], 0);
    expect(s.userData!.migratedAt, isNotNull);
    expect(onDisk()['userdata_version'], 1);
    expect(
      dir.listSync().map((f) => f.uri.pathSegments.last),
      isNot(contains(startsWith('settings.json.pre-userdata'))),
    );
    await s.marksReady;
    s.dispose();
  });
}
