# Content attribution

The prayer and writings collections in data/ are supplied by BahaiPrayers.net, except the bahai.org
texts and the other files listed below:
https://bahaiprayers.net/Developer

Its developer page expressly permits consuming these feeds in apps and websites.
The bundled snapshots were downloaded September 13, 2026. Texts and translations
remain subject to their respective rights; they are not covered by this project's
MIT software license. No ownership of these writings or translations is claimed.
The app preserves the source text while converting HTML presentation to paragraphs.
For content corrections, contact the provider through https://bahaiprayers.net/.

This is an independent community project, not an official publication of a Bahá’í
institution or of Omarchy. Downloaded translations come from the same provider.

# Bahá’í Reference Library (bahai.org)

data/uhj-messages.json (messages of the Universal House of Justice) and data/shoghi-effendi.json
(works of Shoghi Effendi) are taken from the Bahá’í Reference Library, https://www.bahai.org/library/.
Copyright © Bahá’í International Community. Each passage names its author (the Universal House of
Justice or Shoghi Effendi), and its citation in the app and on copied text ends with
"Copyright © Bahá’í International Community, bahai.org".

They are used under the terms of use at https://www.bahai.org/legal (last updated 5 September 2022),
which ask that the content not be used in a way that misrepresents the intent of the original source,
that it carry the notice "Copyright © Bahá’í International Community" with attribution to the source
and the individual author, and that any use for a commercial purpose have permission before use; the
Bahá’í International Community may withdraw permission at any time. These texts are not covered by this
project's MIT software license, no ownership is claimed, and no permission beyond those published terms
has been sought or obtained. This app is free and is not sold. Should permission be withdrawn, the two
files can be deleted and the app works without them.

The texts are copied as published: words, punctuation, diacritics, headings, dates and footnotes are
not changed, shortened or summarised. Only the presentation is converted for the native reader:
paragraphs become plain paragraphs; italics, bold, underlined transliteration (Ma<u>sh</u>riq) and
indented quotations are kept as styling; footnote markers are shown as superscript numbers with the
notes after the passage that cites them; numbered list items keep their numbers; table cells are
separated by tabs. Where bahai.org publishes a text the app also had from BahaiPrayers.net (the 73
Riḍván messages), the official bahai.org text is shown instead, under the same id so saved
passages keep working; each match is recorded in data/uhj-messages.json under "replacements".

Each passage records its source URL, the SHA-256 of the downloaded file and the download date.
scripts/import-bahai-library.py downloads and rebuilds them by hand; the app never connects to bahai.org.

# Badí‘ calendar dates

data/badi-dates.json transcribes table A of "Badí‘ dates 172 to 221 B.E.", prepared by an
ad hoc committee at the Bahá’í World Centre using data provided by Her Majesty’s Nautical
Almanac Office, and sent with the letter of the Universal House of Justice of
11 December 2014. It was transcribed from the copy at
https://bahai-library.com/pdf/uhj/uhj_bahai_dates_172-221.pdf
and every row was compared, with no differences, with a second copy of the table,
50-year-Holy-Day-Calendar.pdf (file created 11 December 2014):
https://drive.google.com/open?id=1wdXQI4mc23_aMdfDOAFe22q1tQWtZU-2
The rules for the other dates are in the message of the Universal House of
Justice of 10 July 2014:
https://www.bahai.org/library/authoritative-texts/the-universal-house-of-justice/messages/20140710_001/20140710_001.xhtml
Copyright © Bahá’í International Community. The dates are credited to the Bahá’í World
Centre and the Universal House of Justice; they are not covered by this project's MIT
software license.

The Today card quotes a letter written on behalf of the Universal House of Justice, dated
17 December 1990, on the Long Obligatory Prayer, as reproduced in a memorandum of 2 January 1998:
https://bahai-library.com/uhj_contacting_obligatory_exemptions
Copyright © Bahá’í International Community.

The clock times setting rests on ¶10 and Note 17 of the Kitáb-i-Aqdas, and on a letter written on
behalf of the Universal House of Justice to a National Spiritual Assembly, dated 27 July 1976,
which leaves the matter to the Assembly. The app paraphrases it and sets no hours of its own.

# City list

data/cities.json is a trimmed copy of the GeoNames cities15000 list: name, ASCII name,
country, region, latitude, longitude and time zone, with coordinates rounded to 2 decimals
and everything else removed. City data © GeoNames (https://www.geonames.org/), licensed under
the Creative Commons Attribution 4.0 License:
https://creativecommons.org/licenses/by/4.0/
GeoNames provides the data "as is" and does not endorse this app. The list is searched on
this computer only.

# Sun times

Sunrise, solar noon and sunset use the public-domain NOAA solar calculation
(https://gml.noaa.gov/grad/solcalc/calcdetails.html), computed on this computer.
