Patch release of Bahá’í Reader.

v0.1.5 adds five reading features and a round of fixes.

- New: **Copy** (Ctrl+Shift+C) puts the passage on the clipboard with its citation: author, book and paragraph or Hidden Word number, or a prayer’s author and category. Selected words are copied with the citation too.
- New: an **Obligatory prayers** section with the short, medium and long obligatory prayers, followed by Kitáb-i-Aqdas ¶6 and the notes and Questions and Answers linked to it.
- New: **collections** for saved passages. Create, rename and delete them, and move passages between them. Existing saved passages are kept as they are, under Unsorted.
- New: **Today** (Ctrl+T) opens a passage of the day, the same all day and different each day. **Random** (Ctrl+R) opens a random passage. Both work offline.
- New: **Side by side** (Aa menu) shows the passage beside English or any downloaded language, paired by paragraph or Hidden Word number. It works offline. Prayers, Days of Remembrance and Riḍván messages cannot be paired.
- Changed: search ignores accents, apostrophes and hyphens, so `Bahaullah` finds Bahá’u’lláh. Searching no longer moves your reading position. Alt+Left/Right and Ctrl+Page Up/Down move between passages.
- Changed: a damaged settings file never stops the app from starting, and never loses saved passages. It is kept as a numbered `settings.json.bad` backup.
- Changed: the contents list follows the reading palette, the current passage and keyboard focus are easier to see, and the Epistle to the Son of the Wolf is listed under Writings.

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
