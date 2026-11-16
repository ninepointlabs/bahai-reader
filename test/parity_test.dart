import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/app/about.dart';
import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/calendar/badi.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/library/packs.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show settle;
import 'disk_bundle.dart';

/// The Amharic pack relabelled as language 4, standing in for a language this build does not bundle.
Map<String, dynamic> pack4() {
  Object? relabel(Object? v) => switch (v) {
    Map m => {for (final e in m.entries) e.key: e.key == 'LanguageId' && e.value == 90 ? 4 : relabel(e.value)},
    List l => [for (final x in l) relabel(x)],
    _ => v,
  };
  return (relabel(jsonDecode(File('test/fixtures/pack-90.json').readAsStringSync())) as Map).cast<String, dynamic>();
}

/// The bundled catalog, saying language 4 offers prayers and the Hidden Words.
Map<String, List<Map<String, dynamic>>> catalog4() {
  final data = jsonDecode(File('assets/library/languages.json').readAsStringSync()) as Map;
  return {
    for (final e in data.entries)
      e.key as String: [
        for (final r in e.value as List)
          if ((r as Map)['Id'] != 4) r.cast<String, dynamic>(),
        if (e.key == 'prayers' || e.key == 'hidden')
          {'Id': 4, 'Name': 'Español', 'English': 'Spanish', 'IsLeftToRight': true},
      ],
  };
}

Map<String, (String, DateTime)> snapshot(Directory d) => {
  for (final f in d.listSync(recursive: true).whereType<File>()) f.path: (f.readAsStringSync(), f.lastModifiedSync()),
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-parity'));
  tearDown(() => dir.deleteSync(recursive: true));

  SettingsStore store() => SettingsStore(File('${dir.path}/settings.json'));
  PackFolders folders() =>
      PackFolders(own: Directory('${dir.path}/own/libraries'), gtk: Directory('${dir.path}/gtk/libraries'));
  Future<AppState> state() => AppState.create(
    repository: LibraryRepository(bundle: DiskBundle(), folders: folders()),
    store: store(),
  );

  void wide(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test(
    'collections: create, name checks, file, rename, delete; unsaving takes a passage out of its collection',
    () async {
      final s = await state();
      final lib = s.library!;
      final a = lib.byId['hidden:1']!, b = lib.byId['hidden:2']!, c = lib.byId['prayers:15692']!;
      for (final p in [a, b, c]) {
        await s.toggleSaved(p);
      }
      expect(await s.createCollection('  Morning   prayers '), isNull);
      expect(s.settings.collections.single.name, 'Morning prayers', reason: 'spaces tidied');
      expect(await s.createCollection(''), 'Type a name for the collection.');
      expect(await s.createCollection('unsorted'), contains('is where passages outside a collection go'));
      expect(await s.createCollection('MORNING PRAYERS'), 'There is already a collection called “MORNING PRAYERS”.');
      await s.moveSaved('hidden:2', 'Morning prayers');
      expect(s.collectionOf('hidden:2'), 'Morning prayers');
      expect(
        [
          for (final (n, ps) in s.filed()) '$n: ${[for (final p in ps) p.id].join(' ')}',
        ],
        ['Morning prayers: hidden:2', 'Unsorted: hidden:1 prayers:15692'],
      );
      s.setExpanded('saved/Morning prayers', true);
      expect(await s.renameCollection('Morning prayers', 'Dawn'), isNull);
      expect(s.settings.expanded, {'saved/Dawn': true});
      await s.moveSaved('hidden:2', null);
      expect(s.collectionOf('hidden:2'), isNull);
      await s.moveSaved('hidden:2', 'Dawn');
      await s.deleteCollection('Dawn');
      expect(s.settings.saved, contains('hidden:2'), reason: 'deleting a collection keeps its passages saved');
      await s.createCollection('Evening');
      await s.moveSaved('hidden:1', 'Evening');
      await s.toggleSaved(a);
      expect(s.settings.collections.single.items, isEmpty);
      // Stored as the GTK app stores them.
      final saved = jsonDecode(store().file.readAsStringSync()) as Map;
      expect(saved['collections'], [
        {'name': 'Evening', 'items': []},
      ]);
    },
  );

  test('a language downloaded by the GTK app is read from its folder, which is left unchanged', () async {
    final gtk = Directory('${dir.path}/gtk/libraries')..createSync(recursive: true);
    File('${gtk.path}/4.json').writeAsStringSync(jsonEncode(pack4()));
    File('${gtk.path}/7.json').writeAsStringSync('{"prayers": "damaged"}');
    final before = snapshot(gtk);
    final s = await state();
    expect([for (final l in s.languages) l.id], [1, 90, 4], reason: 'the damaged pack (7) is not offered');
    await s.setLanguage(4);
    expect(s.library!.byId['4:hidden:7400'], isNotNull);
    expect(s.library!.byId['4:hidden:7400']!.match, 'hidden:True:2');
    expect(snapshot(gtk), before);
    expect(Directory('${dir.path}/own').existsSync(), isFalse, reason: 'reading writes nothing');
  });

  test('a saved language that cannot be read falls back to English and says so', () async {
    store().file.writeAsStringSync(jsonEncode({'language': 4}));
    final s = await state();
    expect(s.settings.language, 1);
    expect(s.notice, contains('library is not downloaded, so English is shown'));
  });

  test('Download & use fetches every collection offered, keeps it in this app’s folder only, and a failure keeps what was there', () async {
    final own = Directory('${dir.path}/own/libraries');
    final s = await state();
    final pack = pack4();
    final asked = <String>[];
    Future<Object?> fetch(String endpoint) async {
      asked.add(endpoint);
      if (endpoint.startsWith('prayersystembylanguage')) return pack['prayers'];
      if (endpoint.startsWith('HiddensByLanguage')) return pack['hidden'];
      throw StateError('not offered: $endpoint');
    }

    // The catalog this app keeps after "Check available languages", saying language 4 has prayers and Hidden Words.
    own.createSync(recursive: true);
    File('${own.path}/languages.json').writeAsStringSync(jsonEncode(catalog4()));
    s.repository.forgetCatalog();
    final progress = <String>[];
    await s.download(4, progress: progress.add, fetch: fetch);
    expect(asked, ['prayersystembylanguage?html=true&languageid=4', 'HiddensByLanguage?languageid=4']);
    expect(progress, ['Downloading Prayers…', 'Downloading The Hidden Words…']);
    expect(checkPack(jsonDecode(File('${own.path}/4.json').readAsStringSync()), 4), isNotNull);
    expect(s.offline(4), isTrue);
    await s.setLanguage(4);
    expect(s.library!.passages, isNotEmpty);
    expect(Directory('${dir.path}/gtk').existsSync(), isFalse, reason: 'the GTK app’s folder is never written');
    // Updating again with no connection: the pack stays as it was.
    final kept = File('${own.path}/4.json').readAsStringSync();
    await expectLater(
      s.download(4, fetch: (_) async => throw const SocketException('offline')),
      throwsA(isA<DownloadProblem>().having((e) => e.message, 'message', contains('Could not reach bahaiprayers.net'))),
    );
    expect(File('${own.path}/4.json').readAsStringSync(), kept);
    expect(own.listSync().where((f) => f.path.contains('.download-')), isEmpty, reason: 'no temporary file left');
  });

  test('Check available languages keeps the new list; an unusable answer keeps the old one', () async {
    final s = await state();
    final good = catalog4();
    await s.checkLanguages(
      fetch: (endpoint) async => good[{for (final e in languageEndpoints.entries) e.value: e.key}[endpoint]],
    );
    expect((await s.catalog())['prayers']!.any((r) => r['Id'] == 4), isTrue);
    final file = File('${dir.path}/own/libraries/languages.json');
    final kept = file.readAsStringSync();
    await expectLater(s.checkLanguages(fetch: (_) async => []), throwsA(isA<DownloadProblem>()));
    expect(file.readAsStringSync(), kept);
  });

  testWidgets('Side by side shows the same passage in the other language, or says why not', (tester) async {
    wide(tester);
    final s = (await tester.runAsync(state))!;
    await tester.runAsync(() => s.setCompare(90));
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true, openId: 'hidden:2'));
    await settle(tester);
    expect(find.text('አማርኛ'.toUpperCase()), findsOneWidget);
    final amharic = s.languageInfo(90);
    expect(amharic.english, 'Ethiopian/Amharic');
    expect(find.textContaining('የ', findRichText: true), findsWidgets, reason: 'the Amharic text is shown');
    // A prayer has no shared numbering.
    await tester.pumpWidget(BahaiReaderApp(key: UniqueKey(), state: s, desktop: true, openId: 'prayers:15692'));
    await settle(tester);
    expect(find.text('Additional Prayers Revealed by ‘Abdu’l‑Bahá'), findsWidgets, reason: 'the prayer is open');
    expect(find.textContaining('cannot be shown side by side'), findsOneWidget);
  });

  testWidgets('the window opens where it was left: section, book and passage', (tester) async {
    wide(tester);
    store().file.writeAsStringSync(jsonEncode({'section': 'hidden', 'last': 'hidden:5'}));
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    expect(find.text('Arabic no. 5'), findsWidgets);
    expect(find.text('The Hidden Words · 5 of 153'), findsOneWidget);
  });

  testWidgets('Ctrl+R opens a random passage of the day’s kind; Aa settings are kept', (tester) async {
    wide(tester);
    final s = (await tester.runAsync(state))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.textContaining('Random passage · '), findsOneWidget);
    expect(s.library!.reflections.map((p) => p.id), contains(s.settings.last));
    s.setReading(font: 'DejaVu Serif', spacing: 14, margin: 120, chromeFont: 'Monospace');
    await tester.pumpAndSettle();
    final st = s.settings;
    expect((st.font, st.spacing, st.margin, st.chromeFont), ('DejaVu Serif', 14, 120, 'Monospace'));
    expect(st.toJson()['spacing'], 14, reason: 'under the GTK key');
    final text = tester.widgetList<SelectableText>(find.byType(SelectableText)).first;
    expect(text.textSpan?.style?.fontFamily ?? text.style?.fontFamily, 'DejaVu Serif');
  });

  test('the counter tells screen readers only at every nineteenth and at the target', () {
    final c = Counter(19);
    final told = <int>[];
    for (var i = 0; i < 40; i++) {
      c.add();
      if (c.milestone) told.add(c.count);
    }
    expect(told.first, 19);
    expect('$c', '19 of 19', reason: 'the counter stops at its target');
  });

  test('the version is the one in pubspec.yaml', () {
    final version = RegExp(
      r'^version: (\S+?)(\+\d+)?$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())![1];
    expect(appVersion, version);
    expect(usage(), contains('--version'));
  });
}
