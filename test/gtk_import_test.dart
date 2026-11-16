import 'dart:convert';
import 'dart:io';

import 'package:bahai_reader/core/app/app_state.dart';
import 'package:bahai_reader/core/library/library_repository.dart';
import 'package:bahai_reader/core/settings/gtk_import.dart';
import 'package:bahai_reader/core/settings/settings_store.dart';
import 'package:bahai_reader/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp.dart';

import 'disk_bundle.dart';

/// A GTK settings.json with every key the GTK app (v0.2.3) writes, in its shapes.
Map<String, Object> gtkSettings() => {
  'section': 'hidden',
  'book': 'Gleanings from the Writings of Bahá’u’lláh',
  'last': 'hidden:2',
  'expanded': {'hidden/From the Arabic': true, 'prayers/Healing': false},
  'language': 1,
  'compare': 90,
  'sidebar_width': 454,
  'size': 24,
  'spacing': 12,
  'margin': 100,
  'theme': 'Sepia',
  'chrome_font': 'Monospace',
  'font': 'DejaVu Serif',
  'writings_by': 'author',
  'location': {'label': 'Haifa, Haifa District, Israel', 'lat': 32.82, 'lon': 34.99, 'tz': 'Asia/Jerusalem'},
  'clock_hours': {'sunrise': 360, 'noon': 720, 'sunset': 1080},
  'prayer': 'medium',
  'long_period': 'noon',
  'long_lead_hours': 3,
  'counter_target': 19,
  'reminders': {'prayer': true, 'feast': true, 'fast_daily': false},
  'keep_running': true,
  'reminders_sent': ['2026-11-15:short:noon:opens'],
  'keep_records': false,
  'records': {
    'said': ['2026-11-15:medium:morning', 'not a mark'],
    'fasted': ['2026-03-02'],
  },
  'counter_target_bad': 'ignored',
  'saved': ['hidden:2', 'gleanings:1', '90:hidden:7400'],
  'collections': [
    {
      'name': 'Morning',
      'items': ['hidden:2', 'prayers:15692'],
    },
    {
      'name': 'unsorted',
      'items': ['gleanings:1'],
    },
  ],
  'highlights': [
    {
      'id': 'hidden:2',
      'start': 0,
      'end': 9,
      'words': 'O SON OF ',
      'color': 'green',
      'created': '2026-11-01',
      'note': 'A note from GTK',
    },
    {'id': 'broken'},
  ],
  'highlight_color': 'blue',
  'positions': {'Riḍván Messages': 'ridvan:1019'},
  'recent': ['Riḍván Messages', 'God Passes By'],
};

void main() {
  late Directory dir, gtkDir;
  late File gtk;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('bahai-reader-flutter-import');
    // The GTK app's folder, as it is on disk: its settings and an older damaged copy beside it.
    gtkDir = Directory('${dir.path}/config/bahai-reader')..createSync(recursive: true);
    gtk = File('${gtkDir.path}/settings.json')..writeAsStringSync(jsonEncode(gtkSettings()));
    File('${gtkDir.path}/settings.json.bad').writeAsStringSync('{older damaged copy');
  });
  tearDown(() => removeTemp(dir));

  SettingsStore store() => SettingsStore(File('${dir.path}/flutter/settings.json'));
  Future<AppState> start({File? from}) => AppState.create(
    repository: LibraryRepository(bundle: DiskBundle()),
    store: store(),
    gtkSettings: from ?? gtk,
  );

  /// Every file in the GTK folder with its bytes and modification time, to compare before and after.
  Map<String, (String, DateTime)> snapshot() => {
    for (final f in gtkDir.listSync().whereType<File>()) f.path: (f.readAsStringSync(), f.lastModifiedSync()),
  };

  test(
    'first run imports highlights, notes, saved passages, collections and settings, and leaves GTK unchanged',
    () async {
      final before = snapshot();
      final s = await start();
      final st = s.settings;
      // Marks: the note travels with its highlight; the broken record is dropped.
      expect(st.highlights.single.toJson(), {
        'id': 'hidden:2',
        'start': 0,
        'end': 9,
        'words': 'O SON OF ',
        'color': 'green',
        'created': '2026-11-01',
        'note': 'A note from GTK',
      });
      expect(st.saved, [
        'hidden:2',
        'gleanings:1',
        '90:hidden:7400',
        'prayers:15692',
      ], reason: 'a passage filed in a collection counts as saved, as GTK cleaning makes it');
      expect(
        [for (final c in st.collections) c.toJson()],
        [
          {
            'name': 'Morning',
            'items': ['hidden:2', 'prayers:15692'],
          },
        ],
        reason: '"Unsorted" is not a collection; its passages stay saved',
      );
      expect(st.highlightColor, 'blue');
      // Settings.
      expect(st.theme, 'sepia');
      expect(st.textSize, 24);
      expect((st.spacing, st.margin, st.font, st.chromeFont), (12, 100, 'DejaVu Serif', 'Monospace'));
      expect(st.compare, 90);
      expect(st.language, 1);
      expect(st.location!.label, 'Haifa, Haifa District, Israel');
      expect(st.location!.zone, 'Asia/Jerusalem');
      expect(st.clockHours!.toJson(), {'sunrise': 360, 'noon': 720, 'sunset': 1080});
      expect((st.prayer, st.longPeriod, st.longLeadHours, st.counterTarget), ('medium', 'noon', 3, 19));
      expect(st.reminders, {'prayer': true, 'feast': true, 'fast_daily': false});
      expect(st.remindersSent, ['2026-11-15:short:noon:opens']);
      expect(st.keepRecords, isFalse);
      expect(st.said, contains('2026-11-15:medium:morning'));
      expect(st.said, isNot(contains('not a mark')));
      expect(st.positions, {'Riḍván Messages': 'ridvan:1019'});
      expect(st.recent, ['Riḍván Messages', 'God Passes By']);
      expect((st.last, st.section, st.book), ('hidden:2', 'hidden', 'Gleanings from the Writings of Bahá’u’lláh'));
      expect(st.expanded, {'writings/The Hidden Words/From the Arabic': true, 'prayers/Healing': false});
      // Not imported, on purpose.
      expect(st.keepRunning, isFalse, reason: 'would add a second login entry beside the GTK app’s');
      expect(s.lastImport!.settings, isNot(contains('keep_running')));
      expect(s.lastImport!.settings, isNot(contains('sidebar_width')));
      expect(st.gtkImport!['status'], 'imported');
      expect(s.notice, contains('Imported 1 highlight and notes, 4 saved passages, 1 collection and your settings'));
      // Stored in this app's own file, in the GTK record shapes.
      final saved = jsonDecode(store().file.readAsStringSync()) as Map;
      expect(saved['highlights'], [st.highlights.single.toJson()]);
      expect(saved['collections'], [
        {
          'name': 'Morning',
          'items': ['hidden:2', 'prayers:15692'],
        },
      ]);
      expect(saved['gtk_import'], isNotNull);
      // The GTK folder: same files, same bytes, same times. Nothing added (no .bad, no .tmp), nothing removed.
      expect(snapshot(), before);
    },
  );

  test('importing again adds nothing and keeps what was changed here', () async {
    final before = snapshot();
    var s = await start();
    // Changes made in this app after the import.
    final h = s.settings.highlights.single;
    await s.updateHighlight(h, note: 'Changed here', color: 'yellow');
    await s.setTheme('dark');
    await s.setTextSize(30);
    await s.setPrayer('short');
    s.settings.collections.first.items.remove('prayers:15692');
    s.settings.collections.add(Collection('Evening', ['gleanings:1']));
    await s.store.save(s.settings);
    // A second start: the import is done, so it does not run again.
    s = await start();
    expect(s.lastImport, isNull);
    expect(s.settings.theme, 'dark');
    // Asking for it again by hand: nothing duplicated, nothing set here replaced.
    for (var i = 0; i < 2; i++) {
      final r = await s.importGtkAgain(source: gtk);
      expect((r.highlights, r.saved, r.collections), (0, 0, 0));
      expect(r.settings, isEmpty);
      expect(r.message, 'Nothing new to import from the GTK Bahá’í Reader.');
      expect(s.settings.collections.first.items.where((i) => i == 'prayers:15692'), hasLength(1));
    }
    final st = s.settings;
    expect(st.highlights, hasLength(1));
    expect(st.highlights.single.note, 'Changed here');
    expect(st.highlights.single.color, 'yellow');
    expect((st.theme, st.textSize, st.prayer), ('dark', 30, 'short'));
    expect(st.saved.toSet().length, st.saved.length);
    expect(
      {for (final c in st.collections) c.name: c.items},
      {
        'Morning': ['hidden:2', 'prayers:15692'],
        'Evening': ['gleanings:1'],
      },
      reason: 'a passage in no collection here is filed as in GTK; one filed here (gleanings:1) stays where it is',
    );
    expect(snapshot(), before);
  });

  test('an existing settings file of this app keeps its settings; only empty ones are filled', () async {
    store().file
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'theme': 'light',
          'size': 18,
          'prayer': 'long',
          'saved': ['iqan:1'],
          'collections': [
            {
              'name': 'morning',
              'items': ['iqan:1'],
            },
          ],
        }),
      );
    final s = await start();
    final st = s.settings;
    expect((st.theme, st.textSize, st.prayer), ('light', 18, 'long'));
    expect(st.location, isNotNull, reason: 'no location here yet, so GTK’s is used');
    expect(st.saved.first, 'iqan:1');
    expect(st.saved, containsAll(['hidden:2', 'gleanings:1']));
    expect(
      [for (final c in st.collections) c.toJson()],
      [
        {
          'name': 'morning',
          'items': ['iqan:1', 'hidden:2', 'prayers:15692'],
        },
      ],
      reason: 'collections are matched by name, ignoring case',
    );
    expect(st.recent, isEmpty, reason: 'Continue reading is only taken on the first run');
  });

  test('a damaged GTK file imports nothing, is not changed, and the import is tried again next time', () async {
    gtk.writeAsStringSync('{"saved": ["hidden:2"');
    final before = snapshot();
    final s = await start();
    expect(s.settings.saved, isEmpty);
    expect(s.settings.gtkImport, isNull);
    expect(s.notice, contains('could not be read'));
    expect(s.lastImport!.status, 'damaged');
    expect(snapshot(), before, reason: 'not set aside as .bad: that is the GTK app’s own business');
    // Fixed later (for example by the GTK app itself): the next start imports it.
    gtk.writeAsStringSync(jsonEncode(gtkSettings()));
    final again = await start();
    expect(again.settings.saved, contains('hidden:2'));
    expect(again.settings.gtkImport!['status'], 'imported');
  });

  test('a GTK file that is not a settings object, or none at all, starts with defaults', () async {
    gtk.writeAsStringSync('[1, 2, 3]');
    var s = await start();
    expect(s.lastImport!.status, 'damaged');
    expect(s.error, isNull);
    gtk.deleteSync();
    s = await start(from: File('${gtkDir.path}/settings.json'));
    expect(s.lastImport!.status, 'missing');
    expect(s.settings.gtkImport!['status'], 'missing');
    expect(s.notice, isNull);
  });

  testWidgets('the desktop window says what was imported', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(start))!;
    await tester.pumpWidget(BahaiReaderApp(state: s, desktop: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('from the GTK Bahá’í Reader. Its own files were not changed.'), findsOneWidget);
    expect(s.notice, isNull, reason: 'shown once');
  });

  test('mergeGtk leaves the GTK data it is given unchanged', () {
    final data = gtkSettings();
    final copy = jsonEncode(data);
    mergeGtk(Settings(), data, fresh: true);
    expect(jsonEncode(data), copy);
  });
}
