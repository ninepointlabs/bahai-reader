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
import '../library/library_repository.dart';
import '../library/passage.dart';
import '../marks/highlight.dart';
import '../platform/notifier.dart';
import '../platform/window_control.dart';
import '../search/fold.dart';
import '../search/search_index.dart';
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

  static Future<AppState> create({LibraryRepository? repository, SettingsStore? store}) async {
    initTimeZones(); // before the settings, which check a saved location's time zone
    final s = store ?? await SettingsStore.standard();
    final (settings, notice) = await s.load();
    final state = AppState(repository: repository ?? LibraryRepository(), store: s, settings: settings, notice: notice);
    await state._start();
    return state;
  }

  Future<void> _start() async {
    try {
      languages = await repository.languages();
      folder = Folder(await repository.foldTable());
      calendar = BadiCalendar.fromJson(jsonDecode(await repository.calendarTable()));
      if (!languages.any((l) => l.id == settings.language)) settings.language = 1;
      await _use(settings.language);
      // Libraries that hold marks made in other languages, so they can follow into this one. Loaded in the background;
      // [marksReady] completes when they are in.
      marksReady = Future.wait([
        for (final l in {for (final h in settings.highlights) languageOf(h.id), for (final id in settings.saved) languageOf(id)})
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

  LanguageInfo get language => languages.firstWhere((l) => l.id == settings.language,
      orElse: () => const LanguageInfo(id: 1, name: 'English', english: 'English'));

  LanguageInfo languageInfo(int id) =>
      languages.firstWhere((l) => l.id == id, orElse: () => LanguageInfo(id: id, name: 'Language $id', english: 'Language $id'));

  Future<void> setLanguage(int id) async {
    if (id == settings.language) return;
    loading = true;
    notifyListeners();
    settings.language = id;
    await _use(id);
    loading = false;
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
  }

  Future<void> setClockHours(ClockHours? hours) async {
    settings.clockHours = hours;
    await _save();
  }

  Future<void> setPrayer(String prayer) async {
    settings.prayer = prayer;
    await _save();
  }

  Future<void> setLongPeriod(String period) async {
    settings.longPeriod = period;
    await _save();
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
  void startReminders(Notifier n, {Autostart? autostart}) {
    notifier = n;
    this.autostart = autostart;
    _clicks?.cancel();
    _clicks = n.actions.listen(notificationAction);
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(const Duration(seconds: 30), (_) => sendDueReminders());
    window.setKeepRunning(settings.keepRunning);
    sendDueReminders();
  }

  static final _saidKey = RegExp(r'^\d{4}-\d\d-\d\d:((short|medium):(morning|noon|evening)|long:(sunset|noon|midnight|at:\d+))$');

  /// Sends what is due now, each at most once; what went stale (after a sleep) is marked and skipped.
  Future<void> sendDueReminders() async {
    final moment = now();
    final (due, marked) = dueReminders(
        calendar, settings.reminderSettings, moment, settings.place, clock, settings.remindersSent, settings.said);
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
    } else if (action.startsWith('open:')) {
      await window.present();
      _openRequests.add(action.substring(5));
    }
  }

  Future<void> setReminder(String key, bool on) async {
    if (!reminderSwitches.contains(key)) return;
    settings.reminders[key] = on;
    await _save();
    await sendDueReminders();
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
    if (settings.positions[work.title] == p.id && (recent.isEmpty || settings.recent.firstOrNull == recent.first)) return;
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
        key, () => follow(key, lib.byId, lib.byMatch, (l) => _loaded[l]?.matches ?? const <String, String>{}));
  }

  // ----- saved passages -----
  bool isSaved(Passage p) => settings.saved.any((id) => id == p.id || passageOf(id)?.id == p.id);

  Future<void> toggleSaved(Passage p) async {
    if (isSaved(p)) {
      // Remove the stored id(s) that mean this passage, in whichever language they were saved.
      settings.saved.removeWhere((id) => id == p.id || passageOf(id)?.id == p.id);
    } else {
      settings.saved.add(p.id);
    }
    await _save();
  }

  /// Removes one stored id from the saved list, exactly as stored.
  Future<void> removeSaved(String id) async {
    settings.saved.remove(id);
    await _save();
  }

  // ----- highlights -----
  List<Highlight> get highlights => settings.highlights;

  /// Highlights stored under this passage's own id.
  List<Highlight> highlightsOf(Passage p) => ofPassage(settings.highlights, p.id);

  /// Highlights made on this passage in another language: shown as a passage-level marker with the note, never as a
  /// guessed word range.
  List<Highlight> followedHighlights(Passage p) =>
      [for (final h in settings.highlights) if (h.id != p.id && passageOf(h.id)?.id == p.id) h];

  Future<Highlight?> addHighlight(Passage p, int start, int end, {String? color, String? note}) async {
    final record = makeHighlight(p.id, p.text, start, end, color: color ?? settings.highlightColor, note: note);
    if (record == null) return null;
    settings.highlights = [...addHighlightTo(settings.highlights, record)];
    if (color != null) settings.highlightColor = color;
    await _save();
    return record;
  }

  /// The stored record a (possibly older copy of a) highlight refers to: same passage, range and words.
  int _find(Highlight h) => settings.highlights
      .indexWhere((r) => r.id == h.id && r.start == h.start && r.end == h.end && r.words == h.words);

  Future<void> updateHighlight(Highlight old, {String? color, String? note, bool clearNote = false}) async {
    final i = _find(old);
    if (i < 0) return;
    settings.highlights[i] = settings.highlights[i].copyWith(color: color, note: cleanNote(note), clearNote: clearNote || (note != null && cleanNote(note) == null));
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

  Future<(int, int)> importGtkMarks() async {
    final result = await importFromGtk(settings);
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

/// [addHighlight] from the marks module, under a name that does not clash with [AppState.addHighlight].
List<Highlight> addHighlightTo(List<Highlight> records, Highlight record) => addHighlight(records, record);

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
