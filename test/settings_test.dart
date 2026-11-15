import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/marks/highlight.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('settings round-trip with GTK-shaped highlight records', () async {
    final store = SettingsStore(File('${dir.path}/settings.json'));
    final s = Settings(theme: 'dark', saved: ['hidden:2'])
      ..highlights.add(makeHighlight('hidden:2', 'abc def ghi', 4, 7, today: '2026-11-15', note: 'n')!);
    await store.save(s);
    final (loaded, notice) = await store.load();
    expect(notice, isNull);
    expect(loaded.theme, 'dark');
    expect(loaded.saved, ['hidden:2']);
    expect(loaded.highlights.single.toJson(),
        {'id': 'hidden:2', 'start': 4, 'end': 7, 'words': 'def', 'color': 'yellow', 'created': '2026-11-15', 'note': 'n'});
  });

  test('an unreadable settings file is set aside, never overwritten', () async {
    final file = File('${dir.path}/settings.json')..writeAsStringSync('{broken');
    File('${dir.path}/settings.json.bad').writeAsStringSync('older');
    final (s, notice) = await SettingsStore(file).load();
    expect(s.saved, isEmpty);
    expect(notice, isNotNull);
    expect(File('${dir.path}/settings.json.bad').readAsStringSync(), 'older');
    expect(File('${dir.path}/settings.json.bad.1').readAsStringSync(), '{broken');
  });

  test('GTK import copies highlights and saved ids and leaves the GTK file untouched', () async {
    final gtk = File('${dir.path}/gtk-settings.json');
    final original = jsonEncode({
      'theme': 'Omarchy',
      'saved': ['hidden:2', '4:hidden:687', 5],
      'highlights': [
        {'id': 'hidden:2', 'start': 10, 'end': 24, 'words': 'the quoted text', 'color': 'yellow', 'created': '2026-11-15'},
        {'id': 'bad'},
      ],
    });
    gtk.writeAsStringSync(original);
    final modified = gtk.lastModifiedSync();
    final s = Settings(saved: ['hidden:2']);
    expect(await importFromGtk(s, source: gtk), (1, 1));
    expect(s.saved, ['hidden:2', '4:hidden:687']);
    expect(await importFromGtk(s, source: gtk), (0, 0), reason: 'importing twice adds nothing');
    expect(gtk.readAsStringSync(), original);
    expect(gtk.lastModifiedSync(), modified);
  });

  test('the store never points at the GTK settings file', () async {
    final store = await SettingsStore.standard();
    expect(store.file.path, isNot(gtkSettingsFile().path));
    expect(store.file.path, contains('bahai-reader-flutter'));
  });
}
