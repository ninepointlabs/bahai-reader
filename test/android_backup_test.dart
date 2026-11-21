import 'dart:io';

import 'package:bahai_reader/core/settings/android_backup.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp.dart';

void main() {
  late Directory files;
  setUp(() => files = Directory.systemTemp.createTempSync('br-files-'));
  tearDown(() => removeTemp(files));

  Set<String> names(Directory d) =>
      d.existsSync() ? {for (final f in d.listSync()) f.uri.pathSegments.where((s) => s.isNotEmpty).last} : {};

  test('notes are in the backup by default; keeping them out moves them at the next start, and back again', () async {
    for (final n in [
      'settings.json',
      'settings.json.pre-userdata-2026-11-20',
      'userdata.sqlite',
      'userdata.sqlite-wal',
    ]) {
      File('${files.path}/$n').writeAsStringSync(n);
    }
    Directory('${files.path}/books').createSync();
    Directory('${files.path}/libraries').createSync();
    expect(notesInBackup(files), isTrue);
    expect((await userDataFolder(files)).path, files.path);

    await chooseNotesInBackup(files, false);
    expect(notesInBackup(files), isFalse);
    final out = await userDataFolder(files);
    expect(out.path, '${files.path}/$noBackupFolder');
    expect(names(out), {
      'settings.json',
      'settings.json.pre-userdata-2026-11-20',
      'userdata.sqlite',
      'userdata.sqlite-wal',
    });
    expect(names(files), {'backup-choice', 'books', 'libraries', noBackupFolder}, reason: 'books and libraries stay');
    expect(File('${out.path}/userdata.sqlite').readAsStringSync(), 'userdata.sqlite');
    expect((await userDataFolder(files)).path, out.path, reason: 'nothing more to move');

    await chooseNotesInBackup(files, true);
    expect((await userDataFolder(files)).path, files.path);
    expect(names(files), containsAll(['settings.json', 'userdata.sqlite', 'userdata.sqlite-wal']));
    expect(names(out), isEmpty);
  });

  test('a settings file already at the destination is never overwritten', () async {
    File('${files.path}/settings.json').writeAsStringSync('here');
    Directory('${files.path}/$noBackupFolder').createSync();
    File('${files.path}/$noBackupFolder/settings.json').writeAsStringSync('there');
    await chooseNotesInBackup(files, false);
    expect((await userDataFolder(files)).path, files.path, reason: 'both have one: stay put');
    expect(File('${files.path}/$noBackupFolder/settings.json').readAsStringSync(), 'there');
  });

  test('a new install that keeps notes out starts in nobackup/', () async {
    await chooseNotesInBackup(files, false);
    final d = await userDataFolder(files);
    expect(d.path, '${files.path}/$noBackupFolder');
    expect(d.existsSync(), isTrue);
  });
}
