# STATUS — Bahá’í Reader Flutter experiment (v0)

Date: 2026-11-15 · Machine: TUF (Linux, Omarchy/Hyprland) · Flutter 3.47.9 stable, Dart 3.13.7 (the existing
user-local install; nothing was reinstalled and no sudo was used).

**This is an experiment, not a replacement.** The real app: https://github.com/ninepointlabs/bahai-reader ·
https://bahaireader.org

## Update: desktop layout matched to the GTK app (2026-11-15, later)

Asked for: “make the desktop version match the GTK version’s UI more”. Built from the GTK app’s own code
(`shell.py`, `theme.py`, `contents.py`, `reading.py`, `highlights.py`, `finder.py`, `labels.py`) and its
screenshots in `docs/screenshots/`, read-only.

- **Window** (`lib/features/desktop/`, used on Linux/Windows/macOS; phones keep the touch layout): sidebar with Home,
  Prayers (count), Writings (“18 books”), Saved (count); a book replaces them with Back + title + “author · parts ·
  words”; “Search this section…”, passage count and the contents tree (Hidden Words by Arabic/Persian, books by part,
  prayers by category with word counts), opened at and scrolled to the passage on show. Header bar: sidebar toggle,
  centred title/subtitle, Search, Aa (appearance + text size), Copy, Save star, ⋮ (search, settings & GTK import,
  shortcuts, About). Narrow windows (<700 px) take turns between sidebar and content, as the GTK window does.
- **Home**: Continue reading (last three books, % of the book) and the library as cards with the gold spine, grouped by
  author in the GTK order. Writings shows the library alone. Today/obligatory-prayer cards are not built (out of scope).
- **Reading pane**: eyebrow (“From the Arabic · Bahá’u’lláh”), accent heading (“Arabic no. 12”), “Passage 12 of 153 ·
  about 1 minute”, the text with GTK margins, italic citation; footer with ← Previous, “book · n of m” + “% of the book”
  + bar, the Next pill, and “English · Available offline · Texts: …”.
- **Highlights**: selecting words shows a small bar (four colour swatches · Note… · Copy) after the selection settles;
  clicking a highlight opens colour, note (with “n / 5,000”), Remove highlight and Done; Saved → “Highlights & notes · n”
  page with cards that open the passage at the highlight.
- **Search dialog** (Ctrl+K): This book · n / Everything · n, “Ignores accents and apostrophes · offline”, results
  grouped by book or prayer category, Enter opens the first; the opened passage marks the match and **scrolls to it**.
- **Look**: the GTK palettes (Dark `#161b19/#e6e1d3/#c9ab70`, Light, Sepia) and derived sidebar/card/popover colours,
  Adwaita Sans for the interface, Noto Serif for the text, default text size 22 as in GTK. The default appearance
  follows the live Omarchy theme (`~/.local/state/omarchy/current/theme/colors.toml`, re-read every 2 s, local file only),
  labelled “Omarchy” in Aa; elsewhere it follows the system. On Omarchy the window has no GTK title bar
  (`linux/runner/my_application.cc`), like the GTK app.
- **Keys**: Ctrl+K, Ctrl+D, Ctrl+Shift+C, Ctrl+H, Alt+←/→, Ctrl+PgUp/PgDn, Ctrl+F, F11 focus mode, Esc, F1, Ctrl+?.
- New settings key `recent` (Continue reading order). Existing settings files load unchanged.

Verified: `flutter analyze` clean; `flutter test` **36 passed** (the 32 below plus `test/desktop_test.dart` (4): home
and library by author, open a book, Ctrl+D, Next, Continue reading; selection bar → green highlight → click → recolour
+ note → Saved → Highlights & notes → open; Ctrl+K This book/Everything, Enter opens; narrow window turn-taking).
Linux release build launched with a scratch `XDG_CONFIG_HOME` and checked by screenshot against the GTK screenshots:
Home, Hidden Words reader with a highlight (dark and light), Prayers in the Omarchy palette, Ctrl+K dialog typed via
`wtype`, Enter jumping to and marking “Kitáb-i-Íqán” in Epistle to the Son of the Wolf, Ctrl+D toggling the star.
Not checked by hand: the selection bar and highlight popover with a real mouse (widget tests only), Windows/macOS builds.

Known differences from the GTK app: no Today, obligatory prayers section, counter, collections, side-by-side compare,
reading font/line spacing/margin settings, or random passage; a highlight’s background shows faint notches between
words (Flutter paints it per glyph run); the selection bar appears where the pointer was released rather than pointing
exactly at the selected words.

## Summary

| Goal | State |
|---|---|
| Linux build on TUF | ✅ `flutter build linux --release` succeeds; the built binary starts and opens a work (checked by screenshot) |
| Android | ✅ `flutter build apk --release` succeeds (56.2 MB). **Not run on a device or emulator.** |
| Windows / macOS / iOS | Scaffolding only. **Not built** (can't be built on Linux). |
| Browse library | ✅ Writings by book, prayers by category |
| Read a work | ✅ Passage by passage, contents list, Aqdas cross-references, prev/next, remembers position per work |
| Switch languages | ✅ English + Amharic (the only pack already downloaded on TUF) |
| Search | ✅ Full current-language library, accent/apostrophe/hyphen-insensitive |
| Highlights, notes, bookmarks | ✅ GTK record format and anchoring rules; cross-language follow by `match` |
| Light/dark | ✅ GTK palettes (Light/Dark/Sepia); follows the Omarchy theme, else the system |
| Offline | ✅ No network code in `lib/`; release APK has no INTERNET permission |
| Tests | ✅ 36 tests, all passing (32 in v0 + 4 desktop) |

## How to run

```sh
cd ~/Projects/bahai-reader-flutter
flutter pub get
flutter test                                  # 32 tests
flutter build linux --release
./build/linux/x64/release/bundle/bahai_reader                     # library
./build/linux/x64/release/bundle/bahai_reader --open aqdas:Paragraphs:6   # open a passage directly
flutter run -d linux                          # debug run
flutter build apk --release                   # → build/app/outputs/flutter-apk/app-release.apk
```

Settings, highlights and saved passages are stored in `~/.config/bahai-reader-flutter/settings.json` (Linux; honours
`$XDG_CONFIG_HOME`). Other platforms use Flutter’s application support directory.

## What I actually verified

- `flutter analyze`: no issues.
- `flutter test`: **32 passed, 0 failed** (`00:04 +32: All tests passed!`):
  - `test/marks_test.dart` (13): highlight creation (trim spaces, colours, 5,000-char notes), `anchor()` (stored
    offsets, moved text, nearest occurrence, missing words → null, out-of-range offsets), overlap replacement
    (one colour per word, other passages untouched), GTK record cleaning, `languageOf`, cross-language `follow`
    in both directions, unmatched ids staying in their language.
  - `test/library_conversion_test.dart` (7): known ids survive (`hidden:1`, `hidden:2`, `prayers:15692`,
    `aqdas:Paragraphs:6`, `aqdas:Notes:1`, `gleanings:1`, `iqan:1`, `saq:1`); 3,526 unique English ids with no
    prefix; bahai.org text under the same id with the copyright notice; no `match` on prayers/days/Riḍván/UHJ;
    every language has `{id}:`-prefixed unique ids, BMP-only text and in-range spans; Amharic `90:hidden:7400` ↔
    English `hidden:2` by `match`; works/contents grouping; copied text carries the citation.
  - `test/search_test.dart` (3): fold parity (`Bahá’u’lláh`→`bahaullah`, `‘Abdu’l‑Bahá`, `Riḍván`,
    `Kitáb-i-Íqán`), match mapped back to original text, full-library search for “Bahaullah”.
  - `test/settings_test.dart` (4): round-trip in GTK record shape; a corrupt settings file is set aside as
    `.bad`/`.bad.1` and never overwritten; GTK import copies highlights + saved ids, is idempotent, and leaves the
    source file byte-identical with the same mtime; the store path is never the GTK one.
  - `test/app_test.dart` (5, widget + state): English highlight + bookmark follow to Amharic as a passage-level
    marker (no guessed word range, stored ids unchanged); app starts, lists the library, opens a work, saves,
    goes to next; narrow window uses a contents drawer and a selection highlights in green; search screen finds
    results and opens one; tapping a highlight opens it, recolours and removes it.
- **Linux, by hand on TUF** (release binary, scratch `XDG_CONFIG_HOME`, screenshots via `grim`):
  - Started, opened Kitáb-i-Aqdas ¶6 with its Q&A/Notes links, contents panel and citation (dark, following system).
  - With a scratch settings file set to Amharic + Light + an English `hidden:2` highlight/note/bookmark, `--open hidden:2`
    opened Amharic Hidden Words no. 2 with the bookmark filled and a “Highlighted in English” card showing the note.
  - Library screen lists all 18 English books; Gleanings opens within ~2 s on a warm start (not formally measured).
  - I could not click/type in the real window from here, so **selecting text, the highlight bar, notes, copy and the
    search screen were verified only by widget tests, not by hand on Linux.**
- **Android**: release APK built; `aapt2 dump badging` shows no INTERNET permission and label “Bahá’í Reader
  (experiment)”. The APK is signed with the default debug key (Flutter template); it is not committed. Not installed
  or run anywhere. Local path: `build/app/outputs/flutter-apk/app-release.apk`.
  - Note: the first Gradle build auto-installed **Android SDK Platform 35** and **CMake 3.22.1** into the user-local SDK
    at `~/.local/share/mise/installs/android-sdk/23.0/` (the path the environment points at). No sudo involved.
- `~/.config/bahai-reader/settings.json` was not modified (mtime still 11:53, before this work). Tim’s current GTK
  settings contain 0 highlights and 0 saved passages, so the import button currently has nothing to copy.

## Content conversion

- `scripts/convert_library.py` imports the GTK app’s own `load_library()` from `../bahai-reader` **read-only**
  (bytecode writing disabled, its feed cache and pack paths redirected), so ids, `match`, bahai.org replacements,
  citations and spans are exactly what the GTK app computes. Output in `assets/library/`:
  - `1.json` English: 3,526 passages, 3,509 of them bahai.org text (replacements under BahaiPrayers.net ids plus
    the UHJ and Shoghi Effendi works) (12.8 MB, decoded in a background isolate).
  - `90.json` Amharic: 191 passages (153 Hidden Words paired by `match`, 38 prayers), from
    `~/.local/share/bahai-reader/libraries/90.json`. Nothing was downloaded.
  - `manifest.json` (languages), `fold.json` (search folding table, below).
- Offsets: the converter refuses texts with characters outside the BMP, so Python code-point offsets equal Dart
  UTF-16 offsets and GTK highlight records can be used unchanged.
- Search folding: Dart has no Unicode normalisation in core, so the converter writes, for every character in the
  texts (plus accented Latin letters a query might use), what the GTK `fold()` produces. Dart applies it per
  character, matching GTK `fold_map()`. Characters outside that table fall back to `toLowerCase()`.
- `--without-bahai-org` rebuilds English from BahaiPrayers.net only, should bahai.org permission be withdrawn.
- Not imported: `cities.json`, `badi-dates.json` (out of scope).

## Highlights, notes, bookmarks

Ported from `marks.py`: records `{"id","start","end","words","color","created","note"}`; anchoring by offsets, then
the nearest occurrence of `words`, else kept and listed (“The text changed; kept but not drawn”) but not drawn;
colours yellow/green/blue/magenta; notes trimmed to 5,000 chars; a new highlight replaces overlapping ones in the
same passage. Saved passages are a list of ids. Stored ids are never rewritten; in another language they follow by
`match`, and highlights from another language show as a card with the note above the passage, not a word range.
Settings → “Import from GTK app” copies (never moves) `highlights` and `saved` from the GTK settings file.

## Attribution

`DATA-NOTICE.md` is copied from the GTK app with paths adapted; the BahaiPrayers.net and bahai.org sections are kept in
full (diffed against the original: only path notes were added). The About screen shows both notices and the full
DATA-NOTICE + LICENSE; bahai.org citations end with “Copyright © Bahá’í International Community, bahai.org”, and
copy-with-citation follows GTK `clipping()`. Code is MIT; texts are not relicensed. The app is free and not sold. No
permission beyond the published terms has been sought or obtained; nobody was contacted.

## Known gaps / not done

- Touch layout only: search marks the match in the opened passage but does not scroll to it (the desktop layout does).
- bahai.org styling: italics, bold, underline and headings are rendered; indented quotations are shown in a muted
  colour rather than indented; paragraph numbers are shown small, not as margin numbers.
- Very long passages (up to ~257k characters, e.g. some Shoghi Effendi chapters) render as one selectable text; not
  profiled.
- Touch layout only: the contents list does not auto-scroll to the current passage (the desktop sidebar does).
- A highlight cannot span two passages (same as GTK).
- No “Continue reading”, collections, compare, Today/calendar, reminders, counter, Omarchy theme follow, packaging,
  CI (all out of scope for v0).
- Windows/macOS/iOS untested; Android built but untested on a device.

## Notes on the GTK checkout

Nothing in `~/Projects/bahai-reader`, its worktrees, PR #51 or Speakeasy task df5647 was changed. I read files and
ran `git status`, `git worktree list` (read-only) in that checkout; `git status` may refresh `.git/index` stat
data, which does not change content. `CHECKLIST-features.md` is still untracked and untouched.

## Sensible next steps

1. Hand-test on Linux: select → highlight → note → copy, and the search screen (only widget-tested so far).
2. Install the APK on a phone and check reading and selection handles on touch.
3. Scroll to the search hit; indent quotations; auto-scroll the contents list.
4. Profile startup and the longest passages; consider SQLite (with FTS) if JSON startup or search gets slow with
   more languages.
5. Build on macOS/Windows machines to check the scaffolding.
6. If the experiment continues: decide whether to share `scripts/convert_library.py` output format with the GTK app.
