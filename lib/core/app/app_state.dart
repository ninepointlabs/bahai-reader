import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import 'theme.dart';

import 'package:timezone/timezone.dart' as tz;

import '../calendar/badi.dart';
import '../calendar/cities.dart';
import '../calendar/reminders.dart';
import '../calendar/today.dart';
import '../calendar/zones.dart';
import '../library/library.dart';
import '../library/downloads.dart' hide checkLanguages;
import '../library/downloads.dart' as downloads show checkLanguages;
import '../library/library_repository.dart';
import '../library/passage.dart';
import '../marks/highlight.dart';
import '../platform/locator.dart';
import '../platform/notifier.dart';
import '../platform/window_control.dart';
import '../search/fold.dart';
import '../search/search_index.dart';
import '../settings/gtk_import.dart';
import '../settings/settings_store.dart';

/// The app's shared state: the chosen language's library, settings, highlights and saved passages.
/// Features read it through [AppScope] and change it through its methods, which save as they go.
class AppState extends ChangeNotifier {
  AppState({required this.repository, required this.store, required this.settings, this.notice});

  final LibraryRepository repository;
  final SettingsStore store;
  final Settings settings;

  /// A message to show once (e.g. a settings file that could not be read).
  String? notice;

  List<LanguageInfo> languages = const [];
  Library? library;
  Folder? folder;
  final Map<int, Library> _loaded = {};
  Future<SearchIndex>? _search;
  bool loading = true;

  /// Completes once every library that holds a stored mark's language is loaded, so ids made in another language
  /// can be followed.
  Future<void> marksReady = Future.value();
  String? error;

  /// [gtkSettings]: the GTK app's settings file to import on the first run (default: its real place on Linux; none
  /// elsewhere). It is only read.
  static Future<AppState> create({LibraryRepository? repository, SettingsStore? store, File? gtkSettings}) async {
    initTimeZones(); // before the settings, which check a saved location's time zone
    final s = store ?? await SettingsStore.standard();
    final fresh = await s.isNew();
    final (settings, notice) = await s.load();
    final state = AppState(repository: repository ?? LibraryRepository(), store: s, settings: settings, notice: notice);
    // Tests never read the real GTK file unless they pass one.
    final gtk = gtkSettings ?? (Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST') ? gtkSettingsFile() : null);
    if (gtk != null && settings.gtkImport == null) await state._firstRunImport(gtk, fresh: fresh);
    await state._start();
    return state;
  }

  /// What the first-run import did, for tests and the settings page.
  GtkImport? lastImport;

  /// The first-run import from the GTK app (see `gtk_import.dart` for the rule). Done once: a missing GTK file counts as
  /// done; a damaged one is tried again at the next start and never changed.
  Future<void> _firstRunImport(File gtk, {required bool fresh}) async {
    final result = lastImport = await importGtk(settings, source: gtk, fresh: fresh);
    if (result.done) settings.gtkImport = {'at': DateTime.now().toIso8601String(), 'status': result.status};
    final message = result.message;
    if (message != null) _addNotice(message);
    await store.save(settings);
  }

  Future<void> _start() async {
    try {
      languages = await repository.languages();
      folder = Folder(await repository.foldTable());
      calendar = BadiCalendar.fromJson(jsonDecode(await repository.calendarTable()));
      if (!languages.any((l) => l.id == settings.language)) {
        // As the GTK app says it: the language chosen there (or here) is not on this computer, or cannot be read.
        final info = await repository.info(settings.language);
        final damaged = await repository.damagedPack(settings.language);
        _addNotice(damaged != null
            ? 'The downloaded ${info.english} library could not be read, so English is shown. Download it again in ⋮ → Languages & offline libraries.'
            : 'The ${info.english} library is not downloaded, so English is shown.');
        settings.language = 1;
      }
      await _use(settings.language);
      compareLibrary; // Side by side: start reading the other language
      // Libraries that hold marks made in other languages, so they can follow into this one. Loaded in the background;
      // [marksReady] completes when they are in.
      marksReady = Future.wait([
        for (final l in {
          for (final h in settings.highlights) languageOf(h.id),
          for (final id in settings.saved) languageOf(id),
        })
          if (l != settings.language && languages.any((x) => x.id == l))
            repository.load(l).then((lib) {
              _loaded[l] = lib;
              _followCache.clear();
              notifyListeners();
            }),
      ]);
    } catch (e) {
      error = 'The bundled library could not be loaded: $e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _use(int language) async {
    final lib = await repository.load(language);
    _loaded[language] = lib;
    library = lib;
    _search = null;
    _followCache.clear();
  }

  LanguageInfo get language => languages.firstWhere(
    (l) => l.id == settings.language,
    orElse: () => const LanguageInfo(id: 1, name: 'English', english: 'English'),
  );

  LanguageInfo languageInfo(int id) => languages.firstWhere(
    (l) => l.id == id,
    orElse: () => LanguageInfo(id: id, name: 'Language $id', english: 'Language $id'),
  );

  Future<void> setLanguage(int id) async {
    if (id == settings.language) return;
    loading = true;
    notifyListeners();
    final before = settings.language;
    try {
      settings.language = id;
      await _use(id);
    } catch (_) {
      settings.language = before;
      await _use(before);
      loading = false;
      notifyListeners();
      rethrow;
    } finally {
      loading = false;
    }
    _compare = null;
    await _save();
  }

  void _addNotice(String text) => notice = notice == null ? text : '$notice\n$text';

  // ----- Languages & offline libraries -----
  /// Downloading or checking the language list right now (one at a time).
  bool downloading = false;

  /// The full BahaiPrayers.net catalog of languages and what each offers.
  Future<Map<String, List<Map<String, dynamic>>>> catalog() => repository.catalog();

  /// True when a language can be read without downloading: bundled, or a usable pack in this app's or the GTK app's folder.
  bool offline(int id) => languages.any((l) => l.id == id);

  /// Downloads (or downloads again) every collection of a language into this app's own folder, then reads it.
  /// Throws with a sentence for people if it fails; what was there before is kept.
  Future<void> download(int id, {void Function(String)? progress, Fetch? fetch}) async {
    if (downloading) return;
    downloading = true;
    notifyListeners();
    try {
      await downloadLanguage(id, await catalog(), repository.folders, progress: progress, fetch: fetch ?? fetchJson);
      repository.forget(id);
      _loaded.remove(id);
      _compare = null;
      languages = await repository.languages();
    } catch (e) {
      throw DownloadProblem(downloadProblem(e));
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  /// Fetches the language list again (only when asked).
  Future<void> checkLanguages({Fetch? fetch}) async {
    if (downloading) return;
    downloading = true;
    notifyListeners();
    try {
      await downloads.checkLanguages(repository.folders, fetch: fetch ?? fetchJson);
      repository.forgetCatalog();
    } catch (e) {
      throw DownloadProblem(downloadProblem(e));
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  // ----- Side by side -----
  (int, Library?)? _compare;

  /// The languages that can be shown beside the passage: English and every other language on this computer, except
  /// the one being read (GTK `compare_languages()`).
  List<LanguageInfo> get compareLanguages => [
    for (final l in languages)
      if (l.id != settings.language) l,
  ];

  /// The library shown beside the passage, once loaded; null when Side by side is off, or while it loads.
  Library? get compareLibrary {
    final id = settings.compare;
    if (id == null || id == settings.language) return null;
    if (_compare?.$1 != id) {
      _compare = (id, null);
      repository.load(id).then((lib) {
        if (_compare?.$1 == id) _compare = (id, lib);
        notifyListeners();
      }, onError: (Object _) {
        if (_compare?.$1 == id) _compare = (id, Library(id, const []));
        notifyListeners();
      });
    }
    return _compare!.$2;
  }

  Future<void> setCompare(int? id) async {
    settings.compare = id;
    compareLibrary; // starts reading it now, before the reading view asks
    await _save();
  }

  // ----- Today, the calendar and the obligatory prayers -----
  BadiCalendar calendar = BadiCalendar(const []);

  /// A fixed time for tests; otherwise the clock.
  DateTime? fixedNow;

  /// The time now at the saved place, or on this computer.
  tz.TZDateTime now() => localNow(settings.place, fixedNow);

  /// Times as the desktop's clock shows them (12-hour in the US and a few other regions, else 24-hour).
  late bool twelveHour = twelveHourRegions.contains(_region(Platform.localeName));
  static String _region(String locale) {
    final parts = locale.split(RegExp(r'[_.@-]'));
    return parts.length > 1 ? parts[1].toUpperCase() : '';
  }

  String clock(tz.TZDateTime m) => formatClock(m, twelveHour: twelveHour);

  TodayContext? todayContext() {
    final lib = library;
    if (lib == null) return null;
    return TodayContext(calendar: calendar, library: lib, settings: settings, moment: now(), clock: clock);
  }

  /// "Said" for an obligatory prayer's window: the one place it changes (the Today card and the reading view).
  Future<void> markSaid(String key, bool active) async {
    if (active && !settings.said.contains(key)) settings.said.add(key);
    if (!active) settings.said.remove(key);
    settings.said = pruneSaid(settings.said, dayOf(now()), keepHistory: settings.keepRecords);
    await _save();
    await _remindersChanged();
  }

  /// The long prayer's mark, worked out at the click: with "24 hours since last said" the 24 hours run from now.
  Future<void> markLong(bool active) =>
      markSaid(longWindow(settings.longPeriod, now(), settings.place, settings.said).key, active);

  Future<void> markFasted(String key, bool active) async {
    if (active && !settings.fasted.contains(key)) settings.fasted.add(key);
    if (!active) settings.fasted.remove(key);
    settings.fasted = pruneSaid(settings.fasted, dayOf(now()), keepHistory: settings.keepRecords);
    await _save();
  }

  /// The window to mark for the obligatory prayer being read, or null for other passages and "Don't track".
  Window? saidWindow(Passage? p) {
    final chosen = settings.prayer;
    if (p == null || chosen == 'none') return null;
    final prayer = prayerNames.entries.where((e) => p.tags.contains(e.value)).firstOrNull?.key;
    if (prayer == null) return null;
    if (prayer == 'long') return longWindow(settings.longPeriod, now(), settings.place, settings.said);
    return currentWindow(prayer, now(), settings.place);
  }

  Future<void> setLocation(Place? place) async {
    settings.location = place;
    await _save();
    await _remindersChanged();
  }

  Future<void> setClockHours(ClockHours? hours) async {
    settings.clockHours = hours;
    await _save();
    await _remindersChanged();
  }

  Future<void> setPrayer(String prayer) async {
    settings.prayer = prayer;
    await _save();
    await _remindersChanged();
  }

  Future<void> setLongPeriod(String period) async {
    settings.longPeriod = period;
    await _save();
    await _remindersChanged();
  }

  Future<void> setKeepRecords(bool keep) async {
    settings.keepRecords = keep;
    if (!keep) {
      settings.said = pruneSaid(settings.said, dayOf(now()), keepHistory: false);
      settings.fasted = pruneSaid(settings.fasted, dayOf(now()), keepHistory: false);
    }
    await _save();
  }

  Future<void> clearRecords() async {
    settings.said = [];
    settings.fasted = [];
    await _save();
  }

  Future<void> setCounterTarget(int target) async {
    settings.counterTarget = target;
    await _save();
  }

  // ----- reminders -----
  /// Where reminders are shown; [NoNotifier] until [startReminders] (and on platforms without notifications).
  Notifier notifier = const NoNotifier();
  WindowControl window = const WindowControl();

  /// The login entry for keeping reminders running (Linux), or null where there is none.
  Autostart? autostart;

  /// Why the login entry could not be changed, or "Starts when you log in.", for Location & reminders.
  String? keepRunningMessage;
  Timer? _reminderTimer;
  StreamSubscription<NotificationAction>? _clicks;
  final _openRequests = StreamController<String>.broadcast();

  /// What a notification asked to open: `today` or `prayer:<name>`. The window listens and goes there.
  Stream<String> get openRequests => _openRequests.stream;

  /// Checks every 30 seconds what is due (GTK `tick()`): a long timer would not survive suspend or a clock change.
  /// Where the system schedules reminders (Android), they are handed over again now, when the app comes back to the
  /// front, every hour while it is open, and whenever a setting or a Said mark changes them.
  void startReminders(Notifier n, {Autostart? autostart}) {
    notifier = n;
    this.autostart = autostart;
    _clicks?.cancel();
    _clicks = n.actions.listen((a) => a == 'pending' ? takePendingActions() : notificationAction(a));
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(Duration(seconds: n.schedules ? 3600 : 30), (_) => sendDueReminders());
    if (n.schedules) {
      _lifecycle?.dispose();
      _lifecycle = AppLifecycleListener(
        onResume: () async {
          await takePendingActions();
          await sendDueReminders();
        },
      );
      remindersStarted = takePendingActions().then((_) => sendDueReminders());
    } else {
      window.setKeepRunning(settings.keepRunning);
      sendDueReminders();
    }
  }

  AppLifecycleListener? _lifecycle;

  /// Done once reminders were first handed over at start (phones), so [remindersMayBeLate] is known.
  Future<void> remindersStarted = Future.value();

  /// Reminders are on but may arrive late, because the phone has not allowed them at the minute.
  bool get remindersMayBeLate => notifier.exactTimes == false && settings.reminders.values.any((on) => on);

  /// Where "Use my location" can ask the device (phones); null elsewhere.
  Locator? locator;

  /// Sets the location from the device: rounded to about a kilometre, named after the nearest bundled city within
  /// 25 km, in the device's time zone. Returns why not, or null when set.
  Future<String?> useDeviceLocation() async {
    final l = locator;
    if (l == null) return 'Finding your location isn’t available here.';
    String? problem;
    final at = await l.locate((p) => problem = p);
    if (at == null) return problem ?? 'Couldn’t find where you are.';
    final near = nearestCity(await cities(), at.lat, at.lon, withinKm: 25);
    final place = Place.clean({
      'label': near == null ? '' : 'Near ${near.label}',
      'lat': at.lat,
      'lon': at.lon,
      'tz': tz.local.name,
    });
    if (place == null) return 'This device’s time zone isn’t known to the app. Search for your city instead.';
    await setLocation(place);
    return null;
  }

  /// Clicks on notifications made while the app was closed or in the background.
  Future<void> takePendingActions() async {
    for (final a in await notifier.takePending()) {
      await notificationAction(a);
    }
  }

  /// After a change that alters which reminders there are, on phones: hand them over again.
  Future<void> _remindersChanged() async {
    if (notifier.schedules) await sendDueReminders();
  }

  static final _saidKey = RegExp(
    r'^\d{4}-\d\d-\d\d:((short|medium):(morning|noon|evening)|long:(sunset|noon|midnight|at:\d+))$',
  );

  /// Sends what is due now, each at most once; what went stale (after a sleep) is marked and skipped. On phones, also
  /// hands over the week ahead.
  Future<void> sendDueReminders() async {
    final moment = now();
    if (notifier.schedules) {
      final (later, due) = upcomingReminders(
        calendar,
        settings.reminderSettings,
        moment,
        settings.place,
        clock,
        settings.remindersSent,
        settings.said,
      );
      final before = (notifier.unavailable, notifier.exactTimes);
      for (final r in due) {
        await notifier.send(r);
      }
      await notifier.schedule(later);
      // What was handed over is not handed over again as "due now" once its time comes.
      settings.remindersSent = pruneSent(
        {...settings.remindersSent, ...due.map((r) => r.id), ...later.map((r) => r.id)}.toList(),
        dayOf(moment),
      );
      await _save(notify: (notifier.unavailable, notifier.exactTimes) != before);
      return;
    }
    final (due, marked) = dueReminders(
      calendar,
      settings.reminderSettings,
      moment,
      settings.place,
      clock,
      settings.remindersSent,
      settings.said,
    );
    if (marked.isEmpty) return;
    settings.remindersSent = pruneSent([...settings.remindersSent, ...marked], dayOf(moment));
    final before = notifier.unavailable;
    for (final r in due) {
      await notifier.send(r);
    }
    await _save(notify: notifier.unavailable != before);
  }

  /// A click on a notification: "Said today" marks it without opening the window; anything else opens the window.
  Future<void> notificationAction(NotificationAction action) async {
    if (action.startsWith('said:')) {
      final key = action.substring(5);
      if (!_saidKey.hasMatch(key)) return;
      await markSaid(key, true);
      await notifier.withdraw('prayer:${key.split(':')[1]}');
    } else if (action.startsWith('open:') && notifier.schedules) {
      // Android opened the app for it: already in front.
      _openRequests.add(action.substring(5));
    } else if (action.startsWith('open:')) {
      await window.present();
      _openRequests.add(action.substring(5));
    }
  }

  Future<void> setReminder(String key, bool on) async {
    if (!reminderSwitches.contains(key)) return;
    settings.reminders[key] = on;
    if (on) await notifier.requestPermission();
    await _save();
    await sendDueReminders();
  }

  /// The phone offered "Alarms & reminders" once at start; it is not offered at start again.
  Future<void> markAskedExactTimes() async {
    settings.askedExactTimes = true;
    await _save(notify: false);
  }

  Future<void> setLongLead(int hours) async {
    settings.longLeadHours = longLead(hours);
    await _save();
    await sendDueReminders();
  }

  /// Keep reminders running when the window is closed: closing then hides the window, and a login entry starts the
  /// app hidden. Off removes the entry and closing quits again.
  Future<void> setKeepRunning(bool keep) async {
    settings.keepRunning = keep;
    await _save();
    await window.setKeepRunning(keep);
    final entry = autostart;
    keepRunningMessage = entry == null
        ? (keep ? 'There is no login entry on this system, so reminders run while the app is open.' : null)
        : await entry.set(keep) ?? (keep ? 'Starts when you log in.' : null);
    notifyListeners();
  }

  Future<List<City>>? _cities;

  /// The bundled city list, loaded when first searched.
  Future<List<City>> cities() => _cities ??= repository.cityList().then((raw) => compute(parseCities, raw));

  // ----- appearance -----
  /// The live Omarchy theme's palette, when there is one (Linux only; see [watchOmarchyTheme]).
  Palette? omarchy;
  String? _omarchySource;
  Timer? _themeTimer;

  /// Follows the Omarchy theme as the GTK app does: its `colors.toml` is re-read every two seconds and the palette
  /// changes when the file does. Only a local file is read.
  void watchOmarchyTheme() {
    void tick() {
      final found = readOmarchyPalette();
      if (found?.$2 == _omarchySource) return;
      _omarchySource = found?.$2;
      omarchy = found?.$1;
      notifyListeners();
    }

    tick();
    _themeTimer?.cancel();
    _themeTimer = Timer.periodic(const Duration(seconds: 2), (_) => tick());
  }

  @override
  void dispose() {
    _themeTimer?.cancel();
    _reminderTimer?.cancel();
    _clicks?.cancel();
    _lifecycle?.dispose();
    _openRequests.close();
    super.dispose();
  }

  /// The palette chosen in settings, or null to follow the system's light or dark.
  Palette? get fixedPalette => switch (settings.theme) {
    'light' => Palette.light,
    'dark' => Palette.dark,
    'sepia' => Palette.sepia,
    _ => omarchy,
  };

  ThemeMode get themeMode {
    final fixed = fixedPalette;
    if (fixed != null) return fixed.isDark ? ThemeMode.dark : ThemeMode.light;
    return ThemeMode.system;
  }

  Future<void> setTheme(String theme) async {
    settings.theme = theme;
    await _save();
  }

  Future<void> setReading({String? font, String? chromeFont, int? spacing, int? margin, bool clearFont = false}) async {
    if (font != null || clearFont) settings.font = clearFont ? null : font;
    if (chromeFont != null) settings.chromeFont = chromeFont;
    if (spacing != null) settings.spacing = spacing.clamp(0, 20);
    if (margin != null) settings.margin = margin.clamp(24, 160);
    await _save();
  }

  List<String>? _fonts;

  /// The font families installed on this computer, for Aa → Reading font (Linux: fontconfig's list); the default
  /// faces where it cannot be listed.
  Future<List<String>> installedFonts() async {
    if (_fonts != null) return _fonts!;
    final found = <String>{};
    if (Platform.isLinux) {
      try {
        final r = await Process.run('fc-list', [':', 'family']);
        for (final line in '${r.stdout}'.split('\n')) {
          final name = line.split(',').first.trim();
          if (name.isNotEmpty) found.add(name);
        }
      } on ProcessException {
        // No fontconfig tools: the defaults below.
      }
    }
    if (found.isEmpty) found.addAll(readingFonts.where((f) => f != 'serif'));
    return _fonts = found.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> setTextSize(double size) async {
    settings.textSize = size.clamp(15, 36);
    await _save();
  }

  Future<SearchIndex> searchIndex() => _search ??= SearchIndex.build(library!, folder!);

  // ----- positions -----
  /// Where a work was left, and (for books) the Continue reading order, newest first.
  void rememberPosition(Work work, Passage p) {
    final recent = work.kind == 'writings'
        ? [work.title, ...settings.recent.where((b) => b != work.title)].take(Settings.recentBooks).toList()
        : settings.recent;
    if (settings.positions[work.title] == p.id && (recent.isEmpty || settings.recent.firstOrNull == recent.first)) {
      return;
    }
    settings.positions[work.title] = p.id;
    settings.recent = recent;
    _save(notify: false);
  }

  /// Saved passages that are in this language's library (following ids saved in another language), in saved order.
  List<Passage> get savedPassages {
    final seen = <String>{};
    return [
      for (final id in settings.saved)
        if (passageOf(id) case final p? when seen.add(p.id)) p,
    ];
  }

  // ----- following stored ids into the current language -----
  final Map<String, Passage?> _followCache = {};

  /// The current library's passage for a stored id (saved passage or highlight), following an id made in another
  /// language by its `match`. Null if that passage is not in this library.
  Passage? passageOf(String key) {
    final lib = library;
    if (lib == null) return null;
    return _followCache.putIfAbsent(
      key,
      () => follow(key, lib.byId, lib.byMatch, (l) => _loaded[l]?.matches ?? const <String, String>{}),
    );
  }

  // ----- saved passages -----
  bool isSaved(Passage p) => settings.saved.any((id) => id == p.id || passageOf(id)?.id == p.id);

  Future<void> toggleSaved(Passage p) async {
    final keys = savedKeys(p);
    if (keys.isNotEmpty) {
      // Remove the stored id(s) that mean this passage, in whichever language they were saved, and take it out of its
      // collection too (GTK `bookmark()`).
      settings.saved.removeWhere(keys.contains);
      for (final c in settings.collections) {
        c.items.removeWhere(keys.contains);
      }
    } else {
      settings.saved.add(p.id);
    }
    await _save();
  }

  /// The stored ids under which a passage is saved: its own id, or the same passage's id in another language.
  List<String> savedKeys(Passage p) => [
    for (final id in settings.saved)
      if (id == p.id || passageOf(id)?.id == p.id) id,
  ];

  // ----- collections (GTK `saved.py`) -----
  /// The collection a stored id is filed in, or null (Unsorted).
  String? collectionOf(String key) => settings.collections.where((c) => c.items.contains(key)).firstOrNull?.name;

  /// Saved passages by collection, in the collections' own order, then Unsorted; in this language (a passage saved in
  /// another language is shown as the passage numbered the same here), each once.
  List<(String, List<Passage>)> filed() {
    final seen = <String>{};
    List<Passage> passages(Iterable<String> keys) => [
      for (final k in keys)
        if (passageOf(k) case final p? when seen.add(p.id)) p,
    ];
    return [
      for (final c in settings.collections) (c.name, passages(c.items)),
      (unsorted, passages(settings.saved)),
    ];
  }

  /// Files a saved passage in the named collection, or in none (Unsorted).
  Future<void> moveSaved(String key, String? name) async {
    if (!settings.saved.contains(key) || name == collectionOf(key)) return;
    for (final c in settings.collections) {
      c.items.remove(key);
      if (c.name == name) c.items.add(key);
    }
    await _save();
  }

  String? _nameProblem(String name, {String? current}) {
    if (name.isEmpty) return 'Type a name for the collection.';
    if (name.toLowerCase() == unsorted.toLowerCase()) {
      return '“$unsorted” is where passages outside a collection go; choose another name.';
    }
    if (settings.collections.any((c) => c.name.toLowerCase() == name.toLowerCase() && c.name != current)) {
      return 'There is already a collection called “$name”.';
    }
    return null;
  }

  /// Returns a problem to show, or null once created.
  Future<String?> createCollection(String name) async {
    name = collectionName(name);
    final problem = _nameProblem(name);
    if (problem != null) return problem;
    settings.collections.add(Collection(name));
    await _save();
    return null;
  }

  Future<String?> renameCollection(String old, String name) async {
    name = collectionName(name);
    final problem = _nameProblem(name, current: old);
    if (problem != null) return problem;
    for (final c in settings.collections) {
      if (c.name == old) c.name = name;
    }
    final open = settings.expanded.remove('saved/$old');
    if (open != null) settings.expanded['saved/$name'] = open;
    await _save();
    return null;
  }

  /// Removes the collection only; its passages stay saved, under Unsorted.
  Future<void> deleteCollection(String name) async {
    settings.collections.removeWhere((c) => c.name == name);
    settings.expanded.remove('saved/$name');
    await _save();
  }

  /// A contents group opened or closed by hand, remembered (GTK `expanded`).
  void setExpanded(String path, bool open) {
    settings.expanded[path] = open;
    _save(notify: false);
  }

  /// Where the window is, for the next start (GTK `section`, `book`, `last`).
  void rememberPlace({String? section, String? book, String? last}) {
    if (section == settings.section && book == settings.book && (last == null || last == settings.last)) return;
    settings.section = section;
    settings.book = book;
    if (last != null) settings.last = last;
    _save(notify: false);
  }

  /// Removes one stored id from the saved list, exactly as stored.
  Future<void> removeSaved(String id) async {
    settings.saved.remove(id);
    for (final c in settings.collections) {
      c.items.remove(id);
    }
    await _save();
  }

  // ----- highlights -----
  List<Highlight> get highlights => settings.highlights;

  /// Highlights stored under this passage's own id.
  List<Highlight> highlightsOf(Passage p) => ofPassage(settings.highlights, p.id);

  /// Highlights made on this passage in another language: shown as a passage-level marker with the note, never as a
  /// guessed word range.
  List<Highlight> followedHighlights(Passage p) => [
    for (final h in settings.highlights)
      if (h.id != p.id && passageOf(h.id)?.id == p.id) h,
  ];

  Future<Highlight?> addHighlight(Passage p, int start, int end, {String? color, String? note}) async {
    final record = makeHighlight(p.id, p.text, start, end, color: color ?? settings.highlightColor, note: note);
    if (record == null) return null;
    settings.highlights = [...addHighlightTo(settings.highlights, record)];
    if (color != null) settings.highlightColor = color;
    await _save();
    return record;
  }

  /// The stored record a (possibly older copy of a) highlight refers to: same passage, range and words.
  int _find(Highlight h) =>
      settings.highlights.indexWhere((r) => r.id == h.id && r.start == h.start && r.end == h.end && r.words == h.words);

  Future<void> updateHighlight(Highlight old, {String? color, String? note, bool clearNote = false}) async {
    final i = _find(old);
    if (i < 0) return;
    settings.highlights[i] = settings.highlights[i].copyWith(
      color: color,
      note: cleanNote(note),
      clearNote: clearNote || (note != null && cleanNote(note) == null),
    );
    await _save();
  }

  Future<void> removeHighlight(Highlight h) async {
    final i = _find(h);
    if (i < 0) return;
    settings.highlights.removeAt(i);
    await _save();
  }

  /// When the text moved, a drawn highlight follows it (GTK `paint_highlights()` does the same).
  void reanchor(Highlight h, (int, int) place) {
    final i = _find(h);
    if (i < 0 || (h.start, h.end) == place) return;
    settings.highlights[i] = h.copyWith(start: place.$1, end: place.$2);
    _save(notify: false);
  }

  /// Settings → Import from the GTK app again: merges its marks and fills settings that have no value here; never
  /// overwrites a setting made here (see `gtk_import.dart`).
  Future<GtkImport> importGtkAgain({File? source}) async {
    final result = await importGtk(settings, source: source, fresh: false);
    if (result.done) settings.gtkImport = {'at': DateTime.now().toIso8601String(), 'status': result.status};
    _followCache.clear();
    await _start();
    await _save();
    return result;
  }

  Future<void> _save({bool notify = true}) async {
    if (notify) notifyListeners();
    await store.save(settings);
  }
}

/// A failed download, as a sentence for people.
class DownloadProblem implements Exception {
  DownloadProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// [addHighlight] from the marks module, under a name that does not clash with [AppState.addHighlight].
List<Highlight> addHighlightTo(List<Highlight> records, Highlight record) => addHighlight(records, record);

/// The reading font as chosen in Aa (or the default faces), for the text, Today and the counter.
TextStyle readingFace(BuildContext context) {
  final fonts = readingFontsFor(AppScope.of(context).settings.font);
  return TextStyle(fontFamily: fonts.first, fontFamilyFallback: fonts.sublist(1));
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
