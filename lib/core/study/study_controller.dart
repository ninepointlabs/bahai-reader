/// The Study section's state, shared by the desktop and phone layouts: the library of imported books, the book open
/// in the reader (its PDF, its pages' text and answer lines, the run being read) and the changes made to it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import 'carry.dart';
import 'dogear_import.dart';
import 'editions.dart';
import 'importer.dart';
import 'page_data.dart';
import 'study_search.dart';
import 'study_store.dart';

/// The reader's side panels.
enum StudyPanel { contents, highlights, bookmarks, answers, notes }

/// An entry of the PDF's own table of contents, flattened with its depth.
class OutlineEntry {
  const OutlineEntry(this.title, this.page, this.depth);
  final String title;
  final int page;
  final int depth;
}

class StudyController extends ChangeNotifier {
  StudyController(this.store, this.books, {this.readColor, this.writeColor});

  final StudyStore store;

  /// The app's own copies of imported books.
  final Directory books;
  final String Function()? readColor;
  final void Function(String)? writeColor;

  /// The colour new highlights get: the last one used (shared with the rest of the app).
  String get color => readColor?.call() ?? 'yellow';
  set color(String c) => writeColor?.call(c);

  List<StudyBook> get library => sortBooks(store, store.books, sort);

  /// The library's order (Recent, Title, Most marked, Added).
  StudySort sort = StudySort.recent;

  /// The library shows one category's books (its id), the uncategorized ones (''), or all (null).
  String? categoryFilter;

  /// Accent- and apostrophe-insensitive folding for searching marks (the app's, once its table is read).
  String Function(String)? fold;

  void setSort(StudySort s) {
    sort = s;
    notifyListeners();
  }

  void setCategoryFilter(String? id) {
    categoryFilter = id;
    notifyListeners();
  }

  List<StudyCategory> get categories => store.categories;
  List<StudyCategory> categoriesOf(StudyBook b) => store.categoriesOf(b);

  void setCategories(StudyBook b, Iterable<StudyCategory> cs) {
    store.setCategories(b, cs);
    notifyListeners();
  }

  StudyCategory addCategory(String name) {
    final c = store.category(name);
    notifyListeners();
    return c;
  }

  void renameCategory(StudyCategory c, String name) {
    store.renameCategory(c, name);
    if (!store.categories.any((x) => x.id == categoryFilter)) categoryFilter = null;
    notifyListeners();
  }

  void deleteCategory(StudyCategory c) {
    store.deleteCategory(c);
    if (categoryFilter == c.id) categoryFilter = null;
    notifyListeners();
  }

  /// Marks whose text contains [query], in every book and time through.
  List<MarkHit> search(String query) => searchMarks(store, query, fold: fold);

  /// A page (and place on it) to show once the reader is ready, instead of the place last reached.
  (int, double)? jump;

  /// Opens a book at a mark: its run (if not the current one) and its page.
  Future<void> openAt(StudyBook b, {StudyRun? run, int? page, double y = 0}) async {
    await open(b);
    if (run != null && run.id != this.run?.id) viewRun(run);
    if (page != null && page > 0) {
      this.page = page;
      jump = (page, y);
      goTo?.call(page, y: y);
      notifyListeners();
    }
  }

  List<StudyBook> get removed => store.removed;

  // ----- the open book -----

  StudyBook? book;

  /// The run on show: the book's current run, or an earlier one opened to look at.
  StudyRun? run;
  PdfDocument? document;
  List<OutlineEntry> outline = const [];
  StudyPanel panel = StudyPanel.contents;

  /// A problem opening the book, to show instead of it.
  String? problem;

  final Map<int, PageData> _pages = {};
  final Map<int, Future<PageData>> _loading = {};

  /// Asks the reader to show a page (1-based) and a place on it, in points from the top; set by the reader.
  void Function(int page, {double y})? goTo;

  /// The page on show, 1-based (set by the reader as it scrolls).
  int page = 1;

  File fileOf(StudyBook b) => bookFile(books, b.doc.sha256);

  /// The run on show cannot be changed: it is finished (and not unlocked for this session), or nothing is open.
  bool get readOnly {
    final r = run;
    return r == null || !store.editable(r);
  }

  /// The book's runs, oldest first.
  List<StudyRun> get runs => book == null ? const [] : store.runsOf(book!);

  /// Whether the run on show is the one being worked on (not an earlier one opened to look at).
  bool get onCurrentRun => book != null && run != null && store.currentRun(book!).id == run!.id;

  /// Another run whose answers are shown beside (or under) this run's, or null.
  StudyRun? compare;

  /// The Answers panel lists every time through's answers by question, instead of the run on show's.
  bool answersAllRuns = false;

  void setAnswersAllRuns(bool all) {
    answersAllRuns = all;
    notifyListeners();
  }

  /// Shows another run of the book (an earlier one is read-only until unlocked).
  void viewRun(StudyRun r) {
    editing = null;
    run = store.run(r.id) ?? r;
    if (compare?.id == run!.id) compare = null;
    notifyListeners();
  }

  void backToCurrent() {
    final b = book;
    if (b != null) viewRun(store.currentRun(b));
  }

  /// Starts a new, empty time through the book; the run that was current is finished and locked.
  StudyRun? startNewRun({String? name}) {
    final b = book;
    if (b == null) return null;
    editing = null;
    final r = store.startRun(b, name: name);
    book = store.book(b.id);
    run = r;
    compare = null;
    notifyListeners();
    return r;
  }

  /// Lets a finished run be changed until the book is closed.
  void unlockRun() {
    final r = run;
    if (r == null) return;
    store.unlocked.add(r.id);
    notifyListeners();
  }

  void renameRun(StudyRun r, String name) {
    store.renameRun(r, name);
    if (run?.id == r.id) run = store.run(r.id);
    if (compare?.id == r.id) compare = store.run(r.id);
    notifyListeners();
  }

  /// Deletes an earlier run with its marks (never the current one).
  void deleteRun(StudyRun r) {
    final b = book;
    if (b == null) return;
    store.deleteRun(b, r);
    if (compare?.id == r.id) compare = null;
    if (run?.id == r.id) run = store.currentRun(b);
    notifyListeners();
  }

  void setCompare(StudyRun? r) {
    compare = r == null || r.id == run?.id ? null : r;
    notifyListeners();
  }

  /// Every run's answer to the same printed question blank, oldest run first.
  List<(StudyRun, Answer)> history(String slotKey) => book == null ? const [] : store.history(book!, slotKey);

  /// Opens a book at its current run and the place reached in it.
  Future<void> open(StudyBook b) async {
    await close(notify: false);
    book = b;
    run = store.currentRun(b);
    problem = null;
    page = store.view(run!.id)?.page ?? 1;
    notifyListeners();
    final file = fileOf(b);
    if (!await file.exists()) {
      problem = 'The app’s copy of “${b.name}” is missing. Import the PDF again to read it.';
      notifyListeners();
      return;
    }
    try {
      final doc = await PdfDocument.openFile(file.path);
      if (book?.id != b.id) {
        await doc.dispose();
        return;
      }
      document = doc;
      outline = _flatten(await doc.loadOutline(), 0);
    } catch (e) {
      problem = '“${b.name}” could not be opened ($e).';
    }
    notifyListeners();
  }

  static List<OutlineEntry> _flatten(List<PdfOutlineNode> nodes, int depth) => [
    for (final n in nodes) ...[
      if (n.dest?.pageNumber case final p?) OutlineEntry(n.title.trim(), p, depth),
      ..._flatten(n.children, depth + 1),
    ],
  ];

  Future<void> close({bool notify = true}) async {
    final doc = document;
    document = null;
    book = null;
    run = null;
    outline = const [];
    _pages.clear();
    _loading.clear();
    editing = null;
    goTo = null;
    compare = null;
    store.unlocked.clear();
    if (doc != null) await doc.dispose();
    if (notify) notifyListeners();
  }

  /// A page's text and answer lines, once read (null until then; [pageData] reads it).
  PageData? pageIfLoaded(int number) => _pages[number];

  Future<PageData?> pageData(int number) {
    final doc = document;
    if (doc == null || number < 1 || number > doc.pages.length) return Future.value(null);
    final done = _pages[number];
    if (done != null) return Future.value(done);
    return _loading.putIfAbsent(number, () async {
      final data = await PageData.load(doc.pages[number - 1]);
      if (document == doc) {
        _pages[number] = data;
        notifyListeners();
      }
      return data;
    });
  }

  /// The name of the page in the PDF's own contents: the last entry starting on or before it.
  String contentsNameFor(int pageNumber) {
    String? name;
    for (final e in outline) {
      if (e.page <= pageNumber) name = e.title;
    }
    return name ?? 'Page $pageNumber';
  }

  // ----- importing -----

  /// Imports a PDF (its bytes and file name), adds it to the library and returns the book and whether it is new.
  Future<(StudyBook, bool)> importBytes(Uint8List bytes, String fileName) async => add(await prepare(bytes, fileName));

  /// Copies a PDF into the app and looks at it: the book it already is (the same file), or a book it looks like
  /// another edition of. Nothing is added to the library yet.
  Future<ImportCheck> prepare(Uint8List bytes, String fileName) async {
    final file = await importPdfBytes(bytes, fileName, books);
    var pages = 0;
    try {
      final doc = await PdfDocument.openFile(file.copy.path);
      pages = doc.pages.length;
      await doc.dispose();
    } catch (_) {
      // Counted when it opens; a damaged file still shows in the library with its problem.
    }
    final facts = FileFacts(sha256: file.sha256, fileName: file.fileName, pageCount: pages, pdfDocId: file.pdfDocId);
    final same = store.books.where((b) => b.doc.sha256 == file.sha256).firstOrNull;
    return ImportCheck(file, pages, same: same, other: same == null ? store.otherEditionOf(facts) : null);
  }

  /// Adds a checked import to the library as a book of its own; [notSameAs] records "not the same book".
  (StudyBook, bool) add(ImportCheck c, {StudyBook? notSameAs}) {
    if (notSameAs != null) store.decline(c.file.sha256, notSameAs.id);
    final result = store.addBook(
      sha256: c.file.sha256,
      fileName: c.file.fileName,
      byteSize: c.file.byteSize,
      pageCount: c.pages,
      pdfDocId: c.file.pdfDocId,
    );
    notifyListeners();
    return result;
  }

  /// Moves [b] to the edition in [c]: finds every mark of every time through in it and puts it there; what is not
  /// found stays listed as unplaced. The old edition's copy is kept.
  Future<CarryPlan> moveToEdition(StudyBook b, ImportCheck c, {void Function(String)? progress}) async {
    final wasOpen = book?.id == b.id;
    if (wasOpen) await close(notify: false);
    final doc = await PdfDocument.openFile(c.file.copy.path);
    try {
      progress?.call('Reading the new edition…');
      final pages = [for (final p in doc.pages) await PageData.load(p, rules: false)];
      final outline = [for (final e in _flatten(await doc.loadOutline(), 0)) (e.title, e.page)];
      final plan = await planCarry(
        store: store,
        book: b,
        pages: pages,
        outline: outline,
        withRules: (n) => PageData.load(doc.pages[n - 1]),
        progress: progress,
      );
      store.moveToEdition(b, {
        'sha256': c.file.sha256,
        'file_name': c.file.fileName,
        'title': '',
        'page_count': c.pages,
        'byte_size': c.file.byteSize,
        'pdf_doc_id': c.file.pdfDocId,
      }, plan.updates);
      return plan;
    } finally {
      await doc.dispose();
      notifyListeners();
      if (wasOpen) {
        final again = store.book(b.id);
        if (again != null) await open(again);
      }
    }
  }

  // ----- Dogear -----

  /// Where Dogear keeps its library (Linux only); tests point it elsewhere.
  Directory? Function() dogearFolder = () => Platform.isLinux ? dogearLibrary() : null;

  /// Dogear's marks for [b] (the same file, or another edition of it), unless already brought in (or [again]).
  DogearDoc? dogearFor(StudyBook b, {bool again = false}) {
    final dir = dogearFolder();
    if (dir == null) return null;
    final d = findDogear(readDogear(dir), b);
    if (d == null || (!again && store.dogearDone(d.sha256, b.id))) return null;
    return d;
  }

  /// "Not now"/"never": Dogear's marks for [b] are not offered again after an import.
  void skipDogear(StudyBook b, DogearDoc d) => store.markDogearDone(d.sha256, b.id);

  /// Brings Dogear's marks for [b] in (see `dogear_import.dart`).
  Future<DogearReport> bringInDogear(StudyBook b, DogearDoc d) async {
    final wasOpen = book?.id == b.id;
    if (wasOpen) await close(notify: false);
    final doc = await PdfDocument.openFile(fileOf(b).path);
    try {
      final pages = [for (final p in doc.pages) await PageData.load(p, rules: false)];
      final outline = [for (final e in _flatten(await doc.loadOutline(), 0)) (e.title, e.page)];
      return await importDogear(
        store,
        b,
        d,
        pages: pages,
        outline: outline,
        withRules: (n) => PageData.load(doc.pages[n - 1]),
      );
    } finally {
      await doc.dispose();
      notifyListeners();
      if (wasOpen) {
        final again = store.book(b.id);
        if (again != null) await open(again);
      }
    }
  }

  /// The run on show's marks that are not on the book's file yet (after moving to another edition).
  ({List<DocHighlight> highlights, List<Answer> answers, List<DocBookmark> bookmarks}) get unplaced =>
      book == null || run == null
      ? (highlights: const [], answers: const [], bookmarks: const [])
      : store.unplaced(book!, run!.id);

  /// An unplaced answer waiting for a tap on the line where it goes.
  Answer? placing;

  void startPlacing(Answer? a) {
    placing = a;
    notifyListeners();
  }

  /// Puts the answer being placed at [place] (with this edition's question) and drops its unplaced record.
  void place(AnswerPlace place, {String context = '', int ordinal = 0}) {
    final a = placing;
    placing = null;
    if (a == null || run == null || book == null) return notifyListeners();
    store.putAnswer(
      run!.id,
      book!.docId,
      place,
      a.text,
      context: context.isEmpty ? a.context : context,
      ordinal: ordinal,
    );
    store.dropUnplaced('answer', a.id);
    notifyListeners();
  }

  void dropUnplaced(String table, String id) {
    store.dropUnplaced(table, id);
    notifyListeners();
  }

  // ----- the library -----

  void rename(StudyBook b, String label) {
    store.rename(b, label);
    if (book?.id == b.id) book = store.book(b.id);
    notifyListeners();
  }

  Future<void> remove(StudyBook b) async {
    if (book?.id == b.id) await close(notify: false);
    store.remove(b);
    notifyListeners();
  }

  void restore(StudyBook b) {
    store.restore(b);
    notifyListeners();
  }

  /// Deletes a removed book, its marks and (when no other book uses it) the app's copy of its file.
  Future<void> deleteForever(StudyBook b) async {
    final orphan = store.deleteForever(b);
    if (orphan != null) {
      final f = bookFile(books, orphan);
      if (await f.exists()) await f.delete();
    }
    notifyListeners();
  }

  // ----- marks in the run on show -----

  String get _runId => run!.id;
  String get _docId => book!.docId;

  /// The run on show's marks on the book's file (marks still to be placed after a move to another edition are left
  /// out; see [unplaced]).
  List<DocHighlight> get highlights => run == null
      ? const []
      : [
          for (final h in store.highlights(_runId))
            if (h.docId == _docId) h,
        ];
  List<DocBookmark> get bookmarks => run == null
      ? const []
      : [
          for (final b in store.bookmarks(_runId))
            if (b.docId == _docId) b,
        ];
  List<Answer> get answers => run == null
      ? const []
      : [
          for (final a in store.answers(_runId))
            if (a.docId == _docId) a,
        ];
  List<DocNote> get notes => run == null ? const [] : store.notes(_runId);

  T _change<T>(T Function() body) {
    final out = body();
    notifyListeners();
    return out;
  }

  DocHighlight? highlight(PageData p, int start, int end, {String? color, String? note}) => _change(() {
    final c = color ?? this.color;
    if (color != null) this.color = color;
    return store.addHighlight(_runId, _docId, p, start, end, color: c, note: note);
  });

  void recolor(DocHighlight h, String color) => _change(() {
    this.color = color;
    store.updateHighlight(h, color: color);
  });

  void setNote(DocHighlight h, String note) =>
      _change(() => store.updateHighlight(h, note: note, clearNote: note.trim().isEmpty));

  void unhighlight(DocHighlight h) => _change(() => store.removeHighlight(h));

  DocBookmark? bookmarkOn(int pageNumber) => run == null ? null : store.bookmarkOn(_runId, _docId, pageNumber);

  /// Bookmarks the page (named after its contents entry), or removes its bookmark.
  void toggleBookmark(int pageNumber) => _change(() {
    final b = bookmarkOn(pageNumber);
    if (b != null) {
      store.removeBookmark(b);
    } else {
      store.addBookmark(_runId, _docId, pageNumber, contentsNameFor(pageNumber));
    }
  });

  void renameBookmark(DocBookmark b, String name) => _change(() => store.renameBookmark(b, name));
  void removeBookmark(DocBookmark b) => _change(() => store.removeBookmark(b));

  DocNote? addNote(String text) => _change(() => store.addNote(book!, _runId, text));
  void updateNote(DocNote n, String text) => _change(() => store.updateNote(n, text));
  void removeNote(DocNote n) => _change(() => store.removeNote(n));

  /// The answer being typed, if any.
  AnswerEdit? editing;

  Answer? answerAt(AnswerPlace place) {
    if (run == null) return null;
    final key = place.key(_docId);
    return answers.where((a) => a.place.key(_docId) == key).firstOrNull;
  }

  void startAnswer(AnswerEdit e) {
    editing = e;
    notifyListeners();
  }

  /// Stores what was typed (empty removes the answer) and stops editing.
  void finishAnswer(String text) {
    final e = editing;
    editing = null;
    if (e != null && !readOnly) {
      store.putAnswer(_runId, _docId, e.place, text, context: e.context, ordinal: e.ordinal);
    }
    notifyListeners();
  }

  /// Stores what is typed so far without stopping (so nothing is lost if the app closes while typing).
  void keepAnswer(String text) {
    final e = editing;
    if (e == null || readOnly) return;
    store.putAnswer(_runId, _docId, e.place, text, context: e.context, ordinal: e.ordinal);
  }

  void resizeAnswer(Answer a, double size) => _change(() => store.resizeAnswer(a, size));

  void moveBox(Answer a, {required double x, required double y, required double w, required double h}) =>
      _change(() => store.moveAnswerBox(a, x: x, y: y, w: w, h: h));

  Timer? _viewTimer;

  /// Remembers the place reached, a moment after scrolling stops.
  void rememberView(int pageNumber, {double offset = 0, double zoom = 1}) {
    page = pageNumber;
    final r = run, b = book;
    if (r == null || b == null) return;
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(milliseconds: 600), () {
      store.saveView(r.id, b.docId, DocView(page: pageNumber, offset: offset, zoom: zoom));
    });
  }

  /// After records changed underneath (a merged backup): an open book that is gone is closed, the rest redrawn.
  Future<void> refresh() async {
    final b = book;
    if (b != null && store.book(b.id) == null) {
      await close();
      return;
    }
    if (b != null) book = store.book(b.id);
    final r = run;
    if (r != null) run = store.run(r.id) ?? (book == null ? null : store.currentRun(book!));
    notifyListeners();
  }

  void setPanel(StudyPanel p) {
    panel = p;
    notifyListeners();
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    document?.dispose();
    super.dispose();
  }
}

/// An import looked at before it is added: the file, its page count, and the book it already is or may be another
/// edition of.
class ImportCheck {
  const ImportCheck(this.file, this.pages, {this.same, this.other});
  final ImportedFile file;
  final int pages;
  final StudyBook? same, other;
}

/// An answer being typed: where, the printed question, and which of its blanks.
class AnswerEdit {
  const AnswerEdit({required this.place, required this.context, required this.ordinal, this.text = ''});
  final AnswerPlace place;
  final String context;
  final int ordinal;
  final String text;
}
