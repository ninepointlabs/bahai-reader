/// Moving a book's marks to another edition of it: every run's highlights (found by their words and the text around
/// them), answers (by their printed question and which blank of it they were), bookmarks (by the contents entry they
/// are named after, else the same page) and places reached. What cannot be found is left unplaced, never dropped.
library;

import 'dart:convert';

import 'editions.dart';
import 'page_data.dart';
import 'study_store.dart';

class CarryPlan {
  final List<(String, String, Map<String, Object?>)> updates = [];
  int highlights = 0, answers = 0, bookmarks = 0;
  int lostHighlights = 0, lostAnswers = 0;

  int get placed => highlights + answers + bookmarks;
  int get unplaced => lostHighlights + lostAnswers;
}

/// Works out where [book]'s marks go in the other edition, whose pages' text is [pages] (without answer lines) and
/// whose contents are [outline]. [withRules] reads one page of it with its answer lines.
Future<CarryPlan> planCarry({
  required StudyStore store,
  required StudyBook book,
  required List<PageData> pages,
  required List<(String, int)> outline,
  required Future<PageData> Function(int page) withRules,
  void Function(String)? progress,
}) async {
  final plan = CarryPlan();
  final count = pages.length;
  int clamp(int p) => p.clamp(1, count < 1 ? 1 : count);
  final ruled = <int, PageData>{};
  Future<List<PageData>> ruledPages(Iterable<int> numbers) async => [
    for (final n in numbers)
      if (n >= 1 && n <= count) ruled[n] ??= await withRules(n),
  ];
  final runs = store.runsOf(book);
  for (final run in runs) {
    for (final h in store.highlights(run.id)) {
      if (h.docId != book.docId) continue; // already unplaced from an earlier move
      final found = findQuote(pages, h.quote, prefix: h.prefix, suffix: h.suffix, hintPage: h.page);
      if (found == null) {
        plan.lostHighlights++;
        continue;
      }
      final (page, s, e) = found;
      final p = pages[page - 1];
      plan.updates.add((
        'doc_highlight',
        h.id,
        {
          'page': page,
          'rects': jsonEncode([for (final b in p.boxesFor(s, e)) b.toJson()]),
          'char_start': s,
          'char_end': e,
          'prefix': p.text.substring((s - 32).clamp(0, s), s),
          'suffix': p.text.substring(e, (e + 32).clamp(e, p.text.length)),
        },
      ));
      plan.highlights++;
    }
    for (final a in store.answers(run.id)) {
      if (a.docId != book.docId) continue;
      final place = a.place;
      if (place.kind == 'box') {
        // A box placed by hand stays where it was on its page (as Dogear keeps brought-over marks).
        plan.updates.add(('answer', a.id, {'page': clamp(place.page)}));
        plan.answers++;
        continue;
      }
      final ordinal = int.tryParse(a.slotKey.split('#').last) ?? 0;
      progress?.call('Finding your answers… page ${place.page} of $count');
      var found = findSlot(
        await ruledPages([for (var d = -2; d <= 2; d++) place.page + d]),
        a.context,
        ordinal: ordinal,
        hintPage: place.page,
      );
      if (found == null && a.context.isNotEmpty) {
        found = findSlot(
          await ruledPages([for (var n = 1; n <= count; n++) n]),
          a.context,
          ordinal: ordinal,
          hintPage: place.page,
        );
      }
      if (found == null) {
        plan.lostAnswers++;
        continue;
      }
      final (page, index) = found;
      final slot = slotAt(ruled[page]!, index);
      plan.updates.add((
        'answer',
        a.id,
        {
          'page': page,
          'x': slot.x,
          'y': slot.y,
          'w': slot.w,
          'pitch': slot.pitch,
          'lines': slot.lines,
          'indent': slot.indent,
        },
      ));
      plan.answers++;
    }
    for (final m in store.bookmarks(run.id)) {
      if (m.docId != book.docId) continue;
      plan.updates.add(('doc_bookmark', m.id, {'page': pageNamed(outline, m.name) ?? clamp(m.page)}));
      plan.bookmarks++;
    }
    final view = store.view(run.id);
    if (view != null) plan.updates.add(('doc_view', uuidForView(run.id), {'page': clamp(view.page)}));
  }
  return plan;
}

/// The id of a run's "place reached" record (as [StudyStore.saveView] makes it).
String uuidForView(String runId) => StudyStore.viewId(runId);
