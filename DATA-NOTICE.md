# Content attribution

This file is adapted from the GTK Bahá’í Reader's DATA-NOTICE.md (https://github.com/ninepointlabs/bahai-reader).
In this repository the texts are in assets/library/ (English as 1.json, other bundled languages as <id>.json),
converted from the GTK app's data/ folder and already-downloaded language packs by scripts/convert_library.py.
Where this notice names the GTK app's data/ files, their content is in assets/library/1.json.

The prayer and writings collections are supplied by BahaiPrayers.net, except the bahai.org
texts listed below. In English, the app shows bahai.org's text in their place
wherever bahai.org publishes the same passage (see below); BahaiPrayers.net's text is shown for the
rest, and for every other language:
https://bahaiprayers.net/Developer

Its developer page expressly permits consuming these feeds in apps and websites.
The bundled snapshots were downloaded September 13, 2026. Texts and translations
remain subject to their respective rights; they are not covered by this project's
MIT software license. No ownership of these writings or translations is claimed.
The app preserves the source text while converting HTML presentation to paragraphs.
For content corrections, contact the provider through https://bahaiprayers.net/.

This is an independent community project, not an official publication of a Bahá’í
institution or of Omarchy. Translations (for example the Amharic library bundled here, downloaded earlier by the
GTK app) come from the same provider; this experiment does not download anything.

# Bahá’í Reference Library (bahai.org)

data/uhj-messages.json (messages of the Universal House of Justice), data/shoghi-effendi.json (works
of Shoghi Effendi) and data/bahai-org-books.json (bahai.org's text of the books and prayers the app
also has from BahaiPrayers.net) are taken from the Bahá’í Reference Library,
https://www.bahai.org/library/. Copyright © Bahá’í International Community. Each passage names its
author, and its citation in the app and on copied text ends with
"Copyright © Bahá’í International Community, bahai.org".

They are used under the terms of use at https://www.bahai.org/legal (last updated 5 September 2022),
which ask that the content not be used in a way that misrepresents the intent of the original source,
that it carry the notice "Copyright © Bahá’í International Community" with attribution to the source
and the individual author, and that any use for a commercial purpose have permission before use; the
Bahá’í International Community may withdraw permission at any time. These texts are not covered by this
project's MIT software license, no ownership is claimed, and no permission beyond those published terms
has been sought or obtained. This app is free and is not sold. Should permission be withdrawn, the three
files can be deleted and the app works without them (showing BahaiPrayers.net's text again). In this
experiment, run scripts/convert_library.py --without-bahai-org to rebuild assets/library/1.json from
BahaiPrayers.net's text only; the app works the same with it.

The texts are copied as published: words, punctuation, diacritics, headings, dates and footnotes are
not changed, shortened or summarised. Only the presentation is converted for the native reader:
paragraphs become plain paragraphs; italics, bold, underlined transliteration (Ma<u>sh</u>riq) and
indented quotations are kept as styling; footnote markers are shown as superscript numbers with the
notes after the passage that cites them; numbered list items and bahai.org's own paragraph numbers are kept; text bahai.org's
stylesheet shows in capitals is in capitals; table cells are separated by tabs.

Where bahai.org publishes a text the app also had from BahaiPrayers.net, the official text is shown
instead, under the same id, place and numbering, so saved passages keep working: the 73 Riḍván
messages (recorded in data/uhj-messages.json under "replacements"), and the Hidden Words, Gleanings,
Prayers and Meditations, Tablets of Bahá’u’lláh, the Kitáb-i-Íqán, the Kitáb-i-Aqdas, the Epistle to
the Son of the Wolf, Some Answered Questions, Days of Remembrance and 455 of the 472 prayers
(data/bahai-org-books.json, which records each book's source, what was matched, what bahai.org has
revised, and what was kept and why). Passages are matched by their words; where the app's copy joins
pieces bahai.org prints apart (an obligatory prayer with the guidance printed before the prayers),
bahai.org's pieces are shown in the app's arrangement. Text bahai.org prints in a book but the app
never had (introductions, glossaries, a book's title page) is not added; short official lines the
app's copy lacked (a part's opening invocation) are. Prayers are looked for in Bahá’í Prayers, then in
further bahai.org books that print them (other prayer books, Gleanings, Tablets of Bahá’u’lláh, the
Epistle, Selections from the Writings of the Báb, Light of the World, The Promulgation of Universal
Peace and three compilations); a prayer's citation names the book its text was taken from. The app's
closing line naming a prayer's printed source ("Gleanings, CXXXVIII", with a page) is not kept, as the
official text has no such line and no page numbers.

Each passage records its source URL, the SHA-256 of the downloaded file and the download date.
The GTK app's scripts/import-bahai-library.py downloads and rebuilds them by hand; neither app ever connects to bahai.org,
and this experiment makes no network connections at all at runtime.

# Data not included

The GTK app also ships Badí‘ calendar dates (data/badi-dates.json, credited to the Bahá’í World Centre and the
Universal House of Justice; Copyright © Bahá’í International Community) and a GeoNames city list (CC BY 4.0).
This experiment does not include or use them. See the GTK app's DATA-NOTICE.md for their notices.

# This experiment

This app is free and is not sold. The software code is under the MIT License (LICENSE); the texts and translations
are not, and are not relicensed by it.
