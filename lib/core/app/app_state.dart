import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

import '../library/library.dart';
import '../library/library_repository.dart';
import '../library/passage.dart';
import '../marks/highlight.dart';
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
