import 'passage.dart';

/// The notice bahai.org's terms of use ask for (GTK `BAHAI_ORG_NOTICE`).
const bahaiOrgNotice = 'Copyright © Bahá’í International Community, bahai.org';

/// The passage, or a selected part of it, followed by its citation, for pasting elsewhere (GTK `clipping()`).
String clipping(Passage item, [String? excerpt]) {
  var text = (excerpt ?? item.text).trim();
  var cite = item.citation;
  if (cite.isNotEmpty) {
    text = text.split('— $cite').first.trim();
    if (text.isEmpty) text = item.text;
  }
  // Prayers carry only an author; the category is the nearest thing to a reference, unless an official prayer names its book.
  if (item.isPrayer && item.tags.isNotEmpty && item.officialBook == null) {
    const notice = '. $bahaiOrgNotice';
    final official = cite.endsWith(notice);
    final base = official ? cite.substring(0, cite.length - notice.length) : cite;
    cite = [base, 'Prayers', item.tags.first].where((s) => s.isNotEmpty).join(', ') + (official ? notice : '');
  }
  return cite.isNotEmpty ? '$text\n\n— $cite' : text;
}
