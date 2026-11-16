import 'package:flutter/foundation.dart';

import '../../core/app/app_state.dart';
import '../../core/library/library.dart';
import '../../core/library/passage.dart';

/// The sidebar's sections, as in the GTK app's libadwaita window.
enum Section { home, today, prayers, obligatory, writings, saved }

/// What the content pane shows.
enum Pane { home, today, library, prayers, reading, highlights, counter }

/// The sidebar row each section belongs to: Today is part of Home, the obligatory prayers of Prayers (GTK `NAV_OF`).
Section navOf(Section s) => switch (s) {
      Section.today => Section.home,
      Section.obligatory => Section.prayers,
      _ => s,
    };

/// Where the desktop window is: the sidebar section, the book open in it, the passage on show and its group.
/// Kept apart from [AppState], which holds what is saved; this is only the window's state.
class ShellModel extends ChangeNotifier {
  ShellModel(this.app);
  final AppState app;

  Section section = Section.home;
  Pane pane = Pane.home;

  /// The book whose contents the sidebar shows (Writings), or null.
  Work? book;


  /// The passages Previous/Next walk through: the book, the prayer category or the saved list.
  Work? group;
  int index = 0;

  /// A search match to mark and scroll to in the passage on show.
  (int, int)? found;

  /// A highlight to scroll to in the passage on show (opened from Highlights & notes).
  int? scrollTo;

  /// What the passage was opened as ("Passage of the day", "Prayers for Naw-Rúz"), shown before its place.
  String? label;

  /// Where the counter goes back to.
  Pane _counterReturn = Pane.home;

  /// The sidebar's own filter ("Search this section…").
  String filter = '';

  bool sidebarShown = true;
  bool focusMode = false;

  /// In a narrow window the sidebar and the content take turns: true shows the content.
  bool showContent = true;

  /// Bumped on every change of passage, so the reading view can scroll back to the top.
  int turn = 0;

  Passage? get current {
    final g = group;
    if (pane != Pane.reading || g == null || g.passages.isEmpty) return null;
    return g.passages[index.clamp(0, g.passages.length - 1)];
  }

  /// The sidebar shows one book (or the obligatory prayers), with a Back button.
  bool get inBook => (section == Section.writings && book != null) || section == Section.obligatory;

  void navigate(Section to) {
    section = to;
    book = null;
    filter = '';
    // A narrow window shows Home and the library at once; Prayers and Saved first show their contents list.
    showContent = to == Section.home || to == Section.writings || to == Section.today;
    switch (to) {
      case Section.home:
        pane = Pane.home;
      case Section.today:
        pane = Pane.today;
      case Section.obligatory:
        final groups = app.library?.obligatoryGroups ?? const [];
        if (groups.isNotEmpty && groups.first.passages.isNotEmpty) {
          _show(groups.first, 0);
        } else {
          pane = Pane.reading;
          group = null;
        }
      case Section.writings:
        pane = Pane.library;
      case Section.prayers:
        // The sidebar's topics are the index; the page waits, with shortcuts, until a prayer is chosen.
        pane = Pane.prayers;
      case Section.saved:
        openSaved();
    }
    notifyListeners();
  }

  Passage? _lastPrayer;

  /// The prayer last read in this window, for "Continue" on the Prayers page.
  Passage? get lastPrayer => _lastPrayer;

  /// A book from the library: its contents in the sidebar, at the passage last read in it.
  void openBook(Work work, {int? at}) {
    section = Section.writings;
    book = work;
    filter = '';
    final last = app.settings.positions[work.title];
    final i = at ?? (last == null ? 0 : work.passages.indexWhere((p) => p.id == last));
    _show(work, i < 0 ? 0 : i);
    showContent = true;
    notifyListeners();
  }

  void leaveBook() {
    navigate(section == Section.obligatory ? Section.prayers : Section.writings);
    showContent = false;
    notifyListeners();
  }

  /// Saved: the first saved passage (or an empty page saying how to save one).
  void openSaved({int at = 0}) {
    section = Section.saved;
    book = null;
    final saved = savedWork();
    group = saved;
    index = at.clamp(0, saved.passages.isEmpty ? 0 : saved.passages.length - 1);
    pane = Pane.reading;
    found = null;
    turn++;
  }

  Work savedWork() => Work(title: 'Saved', kind: 'saved', passages: app.savedPassages);

  void showHighlights() {
    section = Section.saved;
    pane = Pane.highlights;
    showContent = true;
    notifyListeners();
  }

  /// Opens a passage of [work] (the book, category or saved list it was picked from).
  void openIn(Work work, int i, {(int, int)? found, int? scrollTo}) {
    _show(work, i, found: found, scrollTo: scrollTo);
    showContent = true;
    notifyListeners();
  }

  /// Opens any passage of the library where it belongs: its book (in Writings) or its prayer category (in Prayers).
  void openPassage(Passage p, {(int, int)? found, int? scrollTo, String? label}) {
    final place = app.library?.workOf(p);
    if (place == null) return;
    final (work, i) = place;
    if (work.kind == 'writings') {
      section = Section.writings;
      book = work;
    } else {
      section = Section.prayers;
      book = null;
    }
    filter = '';
    _show(work, i, found: found, scrollTo: scrollTo, label: label);
    showContent = true;
    notifyListeners();
  }

  void step(int delta) {
    final g = group;
    if (pane != Pane.reading || g == null) return;
    final to = index + delta;
    if (to < 0 || to >= g.passages.length) return;
    _show(g, to);
    notifyListeners();
  }

  /// A passage of the Obligatory prayers section, among its group (so Next stays among them).
  void openObligatory(Passage p, {String? label}) {
    final groups = app.library?.obligatoryGroups ?? const [];
    final g = groups.where((g) => g.passages.any((q) => q.id == p.id)).firstOrNull;
    section = Section.obligatory;
    book = null;
    filter = '';
    final work = g ?? Work(title: 'Obligatory prayers', kind: 'obligatory', passages: [p]);
    _show(work, work.passages.indexWhere((q) => q.id == p.id), label: label);
    showContent = true;
    notifyListeners();
  }

  /// A passage opened from Today: [work] is the group Previous/Next walk, [label] says why it was opened.
  void openFromToday(Work work, int i, {required Section section, Work? book, String? label}) {
    this.section = section;
    this.book = book;
    filter = '';
    _show(work, i, label: label);
    showContent = true;
    notifyListeners();
  }

  void showCounter() {
    if (pane != Pane.counter) _counterReturn = pane;
    pane = Pane.counter;
    showContent = true;
    notifyListeners();
  }

  void leaveCounter() {
    pane = _counterReturn == Pane.reading && current == null ? Pane.home : _counterReturn;
    if (pane == Pane.counter) pane = Pane.home;
    notifyListeners();
  }

  void _show(Work work, int i, {(int, int)? found, int? scrollTo, String? label}) {
    this.label = label;
    group = work;
    index = i.clamp(0, work.passages.isEmpty ? 0 : work.passages.length - 1);
    pane = Pane.reading;
    this.found = found;
    this.scrollTo = scrollTo;
    turn++;
    final p = current;
    if (p == null) return;
    if (work.kind == 'writings' || work.kind == 'prayers') app.rememberPosition(work, p);
    if (p.isPrayer) _lastPrayer = p;
  }

  void setFilter(String text) {
    filter = text;
    notifyListeners();
  }

  void toggleSidebar({required bool narrow}) {
    if (narrow) {
      showContent = !showContent;
    } else {
      sidebarShown = !sidebarShown;
    }
    notifyListeners();
  }

  void setFocusMode(bool on) {
    focusMode = on;
    notifyListeners();
  }

  /// After the language changes: the same place, in the new library where it can be found.
  void languageChanged() {
    final p = current;
    book = null;
    group = null;
    if (p != null && p.match != null) {
      final other = app.library?.byMatch[p.match];
      if (other != null) {
        openPassage(other);
        return;
      }
    }
    navigate(section);
  }

  /// Saved changed (a passage saved or unsaved): keep the saved list in step while it is on show.
  void savedChanged() {
    if (section != Section.saved || group?.kind != 'saved') return;
    final id = current?.id;
    final saved = savedWork();
    group = saved;
    final i = id == null ? -1 : saved.passages.indexWhere((p) => p.id == id);
    index = i < 0 ? index.clamp(0, saved.passages.isEmpty ? 0 : saved.passages.length - 1) : i;
    notifyListeners();
  }
}
