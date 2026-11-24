// Notes backup and merge between two devices (sync step A): each record keeps the version changed last, deletions too.
import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/core/userdata/userdata_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'disk_bundle.dart';
import 'helpers/temp.dart';

/// A device's records without what is its own (when and where it exported).
String contents(AppState s) {
  final e = s.exportNotes()!;
  final tables = (e['tables'] as Map).map(
    (t, rows) => MapEntry(t, [
      for (final r in rows as List)
        {
          for (final MapEntry(key: k, value: v) in (r as Map).entries)
            if (k != 'device_id') k: v,
        },
    ]),
  );
  return jsonEncode(tables);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('br-backup-'));
  tearDown(() => removeTemp(dir));

  Future<AppState> device(String name) => AppState.create(
    repository: LibraryRepository(bundle: DiskBundle()),
    store: SettingsStore(File('${dir.path}/$name/settings.json')),
  );

  test(
    'one device\'s notes arrive on another; merging again changes nothing; both ways they become the same',
    () async {
      final a = await device('a'), b = await device('b');
      final lib = a.library!;
      await a.addHighlight(lib.byId['hidden:2']!, 0, 9, color: 'green', note: 'From the desktop');
      await a.toggleSaved(lib.byId['hidden:3']!);
      await a.createCollection('Morning');
      await a.moveSaved('hidden:3', 'Morning');
      final study = a.study!;
      final (book, _) = study.store.addBook(sha256: 'aa11', fileName: 'Workbook.pdf', byteSize: 1, pageCount: 2);
      study.store.addNote(book, study.store.currentRun(book).id, 'Study note');

      final r1 = await b.mergeNotes(jsonDecode(jsonEncode(a.exportNotes()!)) as Map<String, Object?>);
      expect(r1.added, greaterThan(5));
      expect(b.settings.highlights.single.note, 'From the desktop', reason: 'in the app, not only in the store');
      expect(b.settings.collections.single.items, ['hidden:3']);
      expect(b.study!.library.single.name, 'Workbook');
      expect(b.study!.store.notes(b.study!.store.currentRun(b.study!.library.single).id).single.text, 'Study note');
      expect((await b.mergeNotes(a.exportNotes()!)).changed, 0, reason: 'merging the same file again');

      // Both change things; then they exchange files both ways.
      await b.updateHighlight(b.settings.highlights.single, note: 'Edited on the phone');
      await b.removeSaved('hidden:3');
      await a.addHighlight(lib.byId['hidden:5']!, 0, 4, color: 'blue');
      final fromA = a.exportNotes()!, fromB = b.exportNotes()!;
      await a.mergeNotes(fromB);
      await b.mergeNotes(fromA);
      expect(contents(a), contents(b), reason: 'the same records on both');
      expect(
        {for (final h in a.settings.highlights) h.id: h.note},
        {'hidden:2': 'Edited on the phone', 'hidden:5': null},
      );
      expect(a.settings.saved, isNot(contains('hidden:3')), reason: 'the deletion arrived');
      expect(a.settings.collections.single.items, isEmpty);
      a.dispose();
      b.dispose();
    },
  );

  test('the same mark changed on both: the later change wins on both', () async {
    final a = await device('a'), b = await device('b');
    await a.addHighlight(a.library!.byId['hidden:2']!, 0, 9, color: 'green');
    await b.mergeNotes(a.exportNotes()!);
    await a.updateHighlight(a.settings.highlights.single, note: 'first');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.updateHighlight(b.settings.highlights.single, note: 'second, later');
    final fromA = a.exportNotes()!, fromB = b.exportNotes()!;
    await a.mergeNotes(fromB);
    await b.mergeNotes(fromA);
    expect(a.settings.highlights.single.note, 'second, later');
    expect(b.settings.highlights.single.note, 'second, later');
    a.dispose();
    b.dispose();
  });

  test('something that is not a notes backup, or one from a newer version, is refused and changes nothing', () async {
    final a = await device('a');
    final before = contents(a);
    await expectLater(a.mergeNotes({'format': 'other'}), throwsA(isA<UserDataProblem>()));
    final newer = a.exportNotes()!..['schema'] = userDataSchema + 1;
    await expectLater(
      a.mergeNotes(newer),
      throwsA(isA<UserDataProblem>().having((e) => '$e', 'message', contains('newer version'))),
    );
    // Rows it cannot use are skipped; the rest is merged.
    final odd = jsonDecode(jsonEncode(a.exportNotes()!)) as Map<String, Object?>; // as read from a file
    (odd['tables'] as Map)['passage_highlight'] = [
      {'id': 7},
      'not a row',
    ];
    (odd['tables'] as Map)['a_future_table'] = [
      {'id': 'x', 'hlc': 'z', 'created_at': 1, 'updated_at': 1},
    ];
    expect((await a.mergeNotes(odd)).changed, 0);
    expect(contents(a), before);
    a.dispose();
  });
}
