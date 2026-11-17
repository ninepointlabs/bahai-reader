import 'dart:io';

import 'package:bahai_reader/core/marks/highlight.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-test'));
  tearDown(() => removeTemp(dir));

  test('settings round-trip with GTK-shaped highlight records', () async {
    final store = SettingsStore(File('${dir.path}/settings.json'));
    final s = Settings(theme: 'dark', saved: ['hidden:2'])
      ..highlights.add(makeHighlight('hidden:2', 'abc def ghi', 4, 7, today: '2026-11-15', note: 'n')!);
    await store.save(s);
    final (loaded, notice) = await store.load();
    expect(notice, isNull);
    expect(loaded.theme, 'dark');
    expect(loaded.saved, ['hidden:2']);
    expect(loaded.highlights.single.toJson(), {
      'id': 'hidden:2',
      'start': 4,
      'end': 7,
      'words': 'def',
      'color': 'yellow',
      'created': '2026-11-15',
      'note': 'n',
    });
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

  test('the store never points at the GTK settings file', () async {
    final store = await SettingsStore.standard();
    expect(store.file.path, isNot(gtkSettingsFile().path));
    expect(store.file.path, contains('bahai-reader-flutter'));
  }, skip: Platform.isLinux ? false : 'The GTK app and its settings file are Linux only');
}
