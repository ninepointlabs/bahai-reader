Bug-fix release of Bahá’í Reader.

- Fixed: **a very long note with no spaces no longer breaks the window.** Saved → Highlights & notes now wraps notes anywhere and lists the first 600 characters of each; before, a long unbroken note could leave Home or the classic window blank until the app was restarted. Notes are still kept in full.
- Fixed: **highlights, notes and saved passages follow you into another language.** On the passage with the same numbering (as Side by side pairs them), saved passages show as saved, and a highlight is shown above the translated text with its note, since its words cannot be marked on a translation. Prayers, Days of Remembrance, Riḍván messages and the English-only bahai.org texts stay with their own language. Nothing stored is rewritten.
- Improved: **the note editor counts characters** and stops at the 5,000-character limit; a paste keeps what fits.

v0.2.2 gave notes, the highlight bar and menus an edge in dark themes, so a note opened over the text no longer looks like a hole cut in it.

v0.2.1 made the app open as the new version after an update, even when reminders kept the old one running in the background. **If you are updating from 0.2.0 or earlier with reminders running**, quit the app once after updating (or log out and in); from 0.2.1 on this happens by itself.

v0.2.0 was a redesign: a new libadwaita window (Debian 12 keeps the earlier one), a library of books in place of the long list of Writings, search across all the texts (Ctrl+K), progress through each book, highlights and notes, focus mode, and the desktop's own font for the interface. The texts, and how they are set on the page, are unchanged.

- New: **a libadwaita window** on systems with libadwaita 1.4 or newer (Debian 13, Ubuntu 24.04, Fedora 43, Arch/Omarchy, and the Flatpak). The sidebar has **Home, Prayers, Writings and Saved**. Below 700 px the sidebar and the reader take turns. Colours follow the Omarchy theme, or the chosen palette, through libadwaita’s own colours. **Debian 12** (libadwaita 1.2) keeps the earlier window, with the same texts and features it had.
- New: **Home**: the Badí‘ date, the obligatory prayer and the passage of the day at a glance; **Continue reading**, with the last three books you read at the passage you left; and the **library**.
- New: **Writings is a library of books**, grouped by author, in place of one list of 2,901 passages. Opening a book shows its parts and chapters in the sidebar.
- New: **Search the texts** (Ctrl+K): everything, or only the open book, offline, without regard to accents or apostrophes. Results are grouped by book, and each opens at the match.
- New: **progress through the book** under the text (“5% of the book”), and the book and part above the heading.
- New: **highlights and notes**: select words for four colours and a note (Ctrl+H). Saved → Highlights & notes lists them all. They are kept in your settings, never in the texts.
- New: **focus mode** (F11), a **keyboard shortcuts** window (Ctrl+?), and Location, Languages and Collections as libadwaita settings dialogs.
- Changed: **the interface uses your desktop’s font** instead of monospace. Aa → Interface font → Monospace brings the old look back. The reading font is unchanged.
- Changed: **clearer labels**:
  - the obligatory prayers are listed as Short, Medium and Long
  - a prayer is headed by its category, not “Prayer”
  - subtitles no longer repeat the heading
  - the six section buttons are now one compact list
  - Random passage is in the ⋮ menu
- Changed: **the reading footer**: the text fades out above a divider instead of running under Previous/Next, and the citation follows the text directly.
- Improved: **screen readers**: every control now has a name. Checked with Orca 51.1.
- Fixed: on Ubuntu 24.04 (libadwaita 1.5), a dialog closed while it was still opening stayed on screen.

To use the earlier window anyway, start the app with `BAHAI_READER_SHELL=classic`.

v0.1.9 brought the official texts from the Bahá’í Reference Library at bahai.org to the English library, grouping by author and narrow windows. v0.1.8 added the Today view: the Badí‘ date, sun and prayer times, Feasts and Holy Days, the Fast, the Alláh-u-Abhá counter and reminders. v0.1.7 added every Kitáb-i-Aqdas paragraph on obligatory prayer to the Obligatory prayers section. v0.1.6 showed the directions in the obligatory prayers in italics. v0.1.5 added Copy with citation (Ctrl+Shift+C), the Obligatory prayers section, collections for saved passages, Today and Random passages (Ctrl+T, Ctrl+R), and two languages side by side.

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

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, `.AppImage` for a portable launcher, or `.flatpak` for any distribution with Flatpak. The packages are architecture-independent; the AppImage launcher is x86_64. All but the Flatpak require a host Python 3.11+ with PyGObject, GTK 4.8+, and its introspection data; libadwaita 1.4+ gives the new window (the packages depend on libadwaita). Package managers install dependencies for the native packages; install them separately before using the AppImage.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md. This is an independent community app. The online AI search is not integrated.
