// Syncing through a shared folder (sync step B), with two devices and one directory standing in for Syncthing's.
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/core/sync/folder_sync.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'disk_bundle.dart';
import 'helpers/temp.dart';

void main() {
  late Directory dir, shared;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('br-pdfrx-').path;
    await pdfrxFlutterInitialize();
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('br-sync-');
    shared = Directory('${dir.path}/Sync')..createSync();
  });
  tearDown(() => removeTemp(dir));

  Future<AppState> device(String name) => AppState.create(
    repository: LibraryRepository(bundle: DiskBundle()),
    store: SettingsStore(File('${dir.path}/$name/settings.json')),
  );
  List<String> files(Directory d) => [for (final f in d.listSync().whereType<File>()) f.uri.pathSegments.last]..sort();

  test('changes and deletions go both ways; each device writes only its own file', () async {
    final a = await device('a'), b = await device('b');
    await a.setSyncFolder(shared.path);
    await b.setSyncFolder(shared.path);
    expect(
      files(shared),
      [
        for (final s in [a, b]) '$notesPrefix${s.userData!.deviceId}.json',
      ]..sort(),
    );
    expect(a.settings.syncFolder, shared.path, reason: 'remembered on this device');

    await a.addHighlight(a.library!.byId['hidden:2']!, 0, 9, color: 'green', note: 'From the desktop');
    await a.syncNow();
    await b.syncNow();
    expect(b.settings.highlights.single.note, 'From the desktop');
    expect(b.lastSync!.changed, greaterThan(0));
    expect(b.lastSync!.devices, 1);

    await b.toggleSaved(b.library!.byId['hidden:3']!);
    await b.removeHighlight(b.settings.highlights.single);
    await b.syncNow();
    await a.syncNow();
    expect(a.settings.highlights, isEmpty, reason: 'the deletion arrived');
    expect(a.settings.saved, ['hidden:3']);

    // Nothing new: nothing read again, nothing written.
    await a.syncNow();
    expect((a.lastSync!.merged, a.lastSync!.wrote), (0, false));
    expect(files(shared).where((f) => f.startsWith('.')), isEmpty, reason: 'no temporary files left');
    a.dispose();
    b.dispose();
  });

  test('a file still arriving is tried again later; a conflict copy is merged like any other', () async {
    final a = await device('a'), b = await device('b');
    await a.setSyncFolder(shared.path);
    await a.addHighlight(a.library!.byId['hidden:2']!, 0, 9, color: 'green');
    await a.syncNow();
    final good = File('${shared.path}/$notesPrefix${a.userData!.deviceId}.json').readAsStringSync();
    File('${shared.path}/${notesPrefix}half.json').writeAsStringSync(good.substring(0, good.length ~/ 2));
    await b.setSyncFolder(shared.path);
    expect(b.syncProblem, contains('could not be read'));
    expect(b.settings.highlights, hasLength(1), reason: 'the whole file was merged');
    File('${shared.path}/${notesPrefix}half.json').writeAsStringSync(good.replaceFirst('"format"', ' "format"'));
    File('${shared.path}/$notesPrefix${a.userData!.deviceId}.sync-conflict-20261120.json').writeAsStringSync(good);
    await b.syncNow();
    expect(b.syncProblem, isNull);
    expect(b.lastSync!.merged, 2, reason: 'the finished file and the conflict copy');
    expect(b.settings.highlights, hasLength(1));
    a.dispose();
    b.dispose();
  });

  test('PDFs are shared by default; a book imported later goes out within seconds', () async {
    final a = await device('a');
    expect(a.settings.syncBooks, isTrue, reason: 'on unless turned off');
    await a.setSyncFolder(shared.path);
    expect(a.settings.toJson().containsKey('sync_books'), isFalse, reason: 'only "off" is written');
    final pdf = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final (book, _) = await a.study!.importBytes(pdf, 'worksheet.pdf');
    // The import itself schedules a sync a few seconds later (no waiting for the minute).
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(File('${shared.path}/$booksFolder/${book.doc.sha256}.pdf').existsSync(), isTrue);
    a.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('with books shared, a Study PDF goes through the folder and arrives whole', () async {
    final a = await device('a'), b = await device('b');
    final pdf = File('test/fixtures/worksheet.pdf').readAsBytesSync();
    final (book, _) = await a.study!.importBytes(pdf, 'worksheet.pdf');
    await a.setSyncFolder(shared.path, books: true);
    expect(a.lastSync!.booksOut, 1);
    final sha = book.doc.sha256;
    expect(File('${shared.path}/$booksFolder/$sha.pdf').readAsBytesSync(), pdf);
    await b.setSyncFolder(shared.path, books: true);
    expect(b.lastSync!.booksIn, 1);
    final copy = File('${b.studyBooksFolder().path}/$sha.pdf');
    expect(sha256.convert(copy.readAsBytesSync()).toString(), sha);
    expect(b.study!.library.single.name, 'worksheet');
    // With books turned off, PDFs stay put.
    final c = await device('c');
    await c.setSyncFolder(shared.path, books: false);
    expect(File('${c.studyBooksFolder().path}/$sha.pdf').existsSync(), isFalse);
    expect(c.study!.library.single.name, 'worksheet', reason: 'the marks come, the PDF does not');
    a.dispose();
    b.dispose();
    c.dispose();
  });
}
