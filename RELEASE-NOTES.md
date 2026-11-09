Patch release of Bahá’í Reader.

v0.1.9 brings the official texts from the Bahá’í Reference Library at bahai.org to the English library.

- New: **Official texts from bahai.org** in Writings (English): 515 messages of the Universal House of Justice and seven works of Shoghi Effendi (The Advent of Divine Justice, Bahá’í Administration, Citadel of Faith, God Passes By, The Promised Day Is Come, The World Order of Bahá’u’lláh, This Decisive Hour). Footnotes, headings and underlined transliteration are kept; each passage carries “Copyright © Bahá’í International Community, bahai.org”. Bundled; the app does not connect to bahai.org.
- Changed: **the Riḍván messages now show the official bahai.org text.** Saved passages keep working. Eight messages that bahai.org does not class as Riḍván messages (Naw-Rúz and other dates) moved to Messages of the Universal House of Justice, under their bahai.org dates.
- Changed: **the English books and prayers now show bahai.org’s official text** wherever bahai.org has the same passage: the Hidden Words, Gleanings, Prayers and Meditations, Tablets of Bahá’u’lláh, the Kitáb-i-Íqán, the Kitáb-i-Aqdas, the Epistle, Some Answered Questions, Days of Remembrance and 455 of 472 prayers, found in *Bahá’í Prayers* and in other bahai.org books that print them; a prayer's citation names that book. bahai.org’s numbering, footnotes, diacritics and italics come with it. Saved passages keep working.
- New: **Group by book or by author** in Writings, from the list above the search box.
- New: **Narrow windows**: below 700 px the contents list and the right pane take turns, and the window can shrink to 320 px.
- New: **Passage headings and position**: “Arabic no. 1”, “Paragraph 4”, and “1 of 71” between Previous and Next.
- Fixed: neither pane can be dragged below its minimum width, so neither can disappear.

The bahai.org texts are not covered by the app’s MIT license; see DATA-NOTICE.md.

v0.1.8 added the Today view: the Badí‘ date, sun and prayer times, Feasts and Holy Days, the Fast, the Alláh-u-Abhá counter and reminders. v0.1.7 added every Kitáb-i-Aqdas paragraph on obligatory prayer to the Obligatory prayers section. v0.1.6 showed the directions in the obligatory prayers in italics. v0.1.5 added Copy with citation (Ctrl+Shift+C), the Obligatory prayers section, collections for saved passages, Today and Random passages (Ctrl+T, Ctrl+R), and two languages side by side.

- Ten English collections included for offline reading.
- Downloadable language libraries with 112 prayer languages in the catalog.
- Collapsible contents, saved passages, prayer word counts, and offline search.
- Adjustable sidebar, reading typography, palettes, and smooth wheel scrolling.
- Live Omarchy theme integration with standalone GTK support on other Linux desktops.

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli). `add` only starts tracking the repository; `install` installs the package and asks for your password:

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
autonomix-cli install bahai-reader
```

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, `.AppImage` for a portable launcher, or `.flatpak` for any distribution with Flatpak. The packages are architecture-independent; the AppImage launcher is x86_64. All but the Flatpak require a host Python 3.11+ with PyGObject, GTK 4.8+, and its introspection data. Package managers install dependencies for the native packages; install them separately before using the AppImage.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md. This is an independent community app. The online AI search is not integrated.
