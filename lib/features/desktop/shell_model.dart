import 'package:flutter/foundation.dart';

import '../../core/app/app_state.dart';
import '../../core/library/library.dart';
import '../../core/library/passage.dart';

/// The sidebar's sections, as in the GTK app's libadwaita window.
enum Section { home, prayers, writings, saved }

/// What the content pane shows.
enum Pane { home, library, reading, highlights }

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

  bool get inBook => section == Section.writings && book != null;

  void navigate(Section to) {
    section = to;
    book = null;
    filter = '';
    // A narrow window shows Home and the library at once; Prayers and Saved first show their contents list.
    showContent = to == Section.home || to == Section.writings;
    switch (to) {
      case Section.home:
        pane = Pane.home;
      case Section.writings:
        pane = Pane.library;
      case Section.prayers:
        final cats = app.library?.prayerCategories ?? const [];
        final last = _lastPrayer;
        final place = last == null ? null : app.library?.workOf(last);
        if (place != null) {
          _show(place.$1, place.$2);
        } else if (cats.isNotEmpty) {
          _show(cats.first, 0);
        } else {
          pane = Pane.reading;
          group = null;
        }
      case Section.saved:
        openSaved();
    }
    notifyListeners();
  }

  Passage? _lastPrayer;

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
    navigate(Section.writings);
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
  void openPassage(Passage p, {(int, int)? found, int? scrollTo}) {
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
    openIn(work, i, found: found, scrollTo: scrollTo);
  }

  void step(int delta) {
    final g = group;
    if (pane != Pane.reading || g == null) return;
    final to = index + delta;
    if (to < 0 || to >= g.passages.length) return;
    _show(g, to);
    notifyListeners();
  }

  void _show(Work work, int i, {(int, int)? found, int? scrollTo}) {
    group = work;
    index = i.clamp(0, work.passages.isEmpty ? 0 : work.passages.length - 1);
    pane = Pane.reading;
    this.found = found;
    this.scrollTo = scrollTo;
    turn++;
    final p = current;
    if (p == null) return;
    if (work.kind != 'saved') app.rememberPosition(work, p);
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
