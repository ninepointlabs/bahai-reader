# Bahá’í Reader UX redesign: status

Brief: UX Phases 1 and 2, Python + GTK 4 + libadwaita (approved by Tim 2026-11-11, 8:42 AM CT).
Source review: “Bahá’í Reader UX and Stack Review” (read 2026-11-11).
Nothing here is merged, tagged or released. Nothing was pushed to `main`.

**Mockups approved 2026-11-11** (“Go with those and continue”, relayed by Hermes). Phase 2 shell work is under way in stacked PRs; nothing is merged.

Decisions taken with that approval (the defaults I recommended; say if any is wrong):
- The mockups are built as drawn (all eleven decisions in `design/mockups/phase2/README.md`).
- **Debian 12: option A, graceful fallback.** libadwaita 1.4+ gets the new window; older libadwaita (Debian 12 has 1.2.2) gets the classic (Phase 1) window. No package target dropped.
- **No Blueprint:** widgets are built in code, as the rest of the app is, with no new build tool. (The brief allowed “Blueprint or `.ui` templates”; neither is used. Easy to revisit.)
- **Hidden Words prologue:** left as it is, inside Arabic no. 1.

## Done

| Step | Branch | PR | State |
| --- | --- | --- | --- |
| Phase 1: quick wins on the current GTK 4 code | `feat/ux-phase1-quick-wins` (base `main`) | https://github.com/ninepointlabs/bahai-reader/pull/42 | open, not merged |
| Phase 2, step 1: split `reader.py` into modules, no visible change | `refactor/split-reader-modules` (base: the Phase 1 branch, **stacked on #42**) | https://github.com/ninepointlabs/bahai-reader/pull/43 | open, not merged |
| Phase 2, step 2: mockups for approval (docs only) | `design/phase2-mockups` (base: the split branch, **stacked on #43**) | https://github.com/ninepointlabs/bahai-reader/pull/44 | open, approved, not merged |
| Phase 2, step 3 (+ parts of 4–6): libadwaita window with fallback, Home and library, book contents, Continue reading, toasts, theme mapping, F11 focus mode | `feat/adw-shell` (base: the mockups branch, **stacked on #44**) | see below once opened | open, not merged |
| Phase 2, step 4–5 (part): Ctrl+K search (This book / Everything), the reader's place line and book progress footer | `feat/search-progress` (base: `feat/adw-shell`, **stacked on #45**) | see below once opened | open, not merged |
| Phase 2, rest: highlights and notes, preferences and shortcuts dialogs, Orca pass | — | — | to do, in that order |

Merge order: #42, then #43, then #44. Each one's base is the previous branch; GitHub retargets it when the one below merges.

### Phase 1 (one PR)

1. **Interface font.** `window { font-family: monospace; }` is gone. The interface uses the desktop’s own interface font (proportional; Adwaita Sans on TUF). **Aa → Interface font → Monospace** brings the old look back for anyone who wants it. The reading font (`Gtk.TextView`, DejaVu Serif 22 px by default, or the user’s choice) is unchanged and still set separately.
2. **Compact section switcher.** The six bordered full-width buttons are now one `Gtk.ListBox` of icon-and-label rows with the current section selected. The header’s Today button is gone (Today is the first row; Ctrl+T still works). Random moved into ⋮ as “Random passage” (Ctrl+R still works). The ☰ and ⋮ glyphs are now the standard `sidebar-show-symbolic` and `view-more-symbolic` icons, all present in Debian 12’s Adwaita icon theme.
3. **Labels.** The obligatory prayers are listed as Short, Medium and Long Obligatory Prayer. A prayer’s heading is its category (“Healing”), using the category it was opened in when it has several. Obligatory prayers are headed “Obligatory prayers” because bahai.org’s text already prints the prayer’s name as its first line; the name, author and length are in the line beneath. The subtitle never repeats the heading (fixes “Epistle to the Son of the Wolf” twice) and adds the author where the book’s name does not already include it. Branch names in the contents list now use the full width, with a tooltip holding the whole name; passage rows keep their tooltips.
4. **Reading footer.** Previous/Next and the status line sit under a 1 px divider, and the text fades out over its last 28 px above it, so no line is hidden under the bar. The text’s bottom margin (50 px) lets the last line scroll clear of the fade. The citation now follows the text after one line break with a 10 px gap, not an empty paragraph.
5. **Softer controls.** 6 px radii, no hard borders, a light fill for ordinary buttons, flat buttons in the header, menu and contents list, and one primary style (accent fill, text colour chosen for 4.5:1 contrast) used for Next and the counter’s Count. The pane separator is a 1 px hairline instead of a 5 px selection-coloured bar. Today cards have 12 px radii.
6. **Hidden Words preamble.** See the finding below. No text was changed.

Also: the said-today toggle under an obligatory prayer has a tooltip explaining what it does. README features, the Aa/⋮ description and the interface-font note are updated; the keyboard shortcuts are unchanged.

### Phase 2, step 1: the split (no visible change)

`reader.py` (2,377 lines after Phase 1) is now a 73-line launcher; the app is the `bahai_reader` package, 21 modules:

- Below the views, no GTK: `config` (paths, app facts), `settings` (settings.json cleaning), `library` (feeds, packs, bahai.org texts, grouping), `search` (folding, cities), `citations`, `labels` (headings, list names), `theme` (contrast, stylesheet, Omarchy palette follow), `ui` (layout constants, shortcut list). `rendering` (styled spans, Pango), `desktop` (autostart, Flatpak, clocks, GLib) and `widgets` (`Choice`) are small shared helpers.
- The window: `app` (the `Reader` application: header, panes, keys, navigation) plus one mixin per view or window: `contents`, `reading`, `saved`, `today`, `counter`, `reminders`, `about`, `location`, `languages`, and `theme`’s `ThemeMixin`.

How it was done: an AST script moved every top-level statement and every `Reader` method verbatim into its module; imports were then filled in from pyflakes’ undefined-name reports. Only two things are not verbatim: `roman()` moved next to `citation()` (to avoid an import cycle), and code that reads a path the tests change (`STATE`, `CACHE`, `LIBRARY`, `ROOT`, `AUTOSTART`, `in_flatpak`) now reads it from its module at call time (`config.STATE`). `reader.py` re-exports every name, and setting a name on `reader` (as the tests and `scripts/import-bahai-library.py` do) sets it wherever the package holds that object, so **no existing test changed**.

Packaging: `.deb`/`.rpm`/Arch (nfpm), the AppImage and the Flatpak now also install `bahai_reader/*.py` beside `reader.py`. Launchers are unchanged.

### Phase 2, step 3: the libadwaita window (`feat/adw-shell`)

- `bahai_reader/shell.py`: `AdwApplicationWindow` → `AdwToastOverlay` → `AdwNavigationSplitView`, each page an `AdwToolbarView` with an `AdwHeaderBar`; one `AdwBreakpoint` (below 700 px) collapses the split view. It builds the same widgets as the classic window (contents list, reading view, Today, counter), so every view works unchanged in both.
- Chosen at start: libadwaita ≥ 1.4 → the new window; otherwise the classic one. `BAHAI_READER_SHELL=classic|adwaita` overrides (documented in the README).
- Sidebar: Home, Prayers (with count), Writings (“18 books”), Saved (count). Today, Obligatory prayers and the Hidden Words keep their own pages and belong to Home, Prayers and Writings respectively.
- Home: date, obligatory prayer and passage-of-the-day cards; Continue reading (last three books, at the passage left, % of the book by words); the library, by author. Writings shows the library; a book card opens the book with its contents in the sidebar and Back to the library; the branch holding the current passage opens.
- Settings: `positions` (last passage per book), `recent` (books, most recent first), `book` (the open book), all validated in `clean_settings`.
- Theme: the palette goes to libadwaita’s named colours (`@define-color`, and the CSS variables libadwaita 1.6+ reads when GTK ≥ 4.16); the sidebar takes Omarchy’s `dark_background` when it keeps 7:1 contrast with the text; accent text and text on the accent are contrast-checked; `AdwStyleManager` is forced light or dark to match. No per-widget button/entry CSS in the new window.
- Notices are `AdwToast`s (they stay until dismissed). F11 is focus mode (Esc leaves it). Header actions are icons (save, copy), with Aa and ⋮ as before.
- Packaging: `.deb` depends on `gir1.2-adw-1` (1.2 on Debian 12, which then gets the classic window), `.rpm` and Arch on `libadwaita`; the Flatpak runtime has it; the AppImage uses the host’s if present.
- Tests: `tests/shell_ui.py` (new, drives the whole new window), `tests/test_shell.py` (13: library, Continue reading settings, theme mapping, choosing the window). `layout_ui`, `chrome_ui` and `smoke_ui` test the classic window and now say so (they pin it). `robustness_ui` reads notices through `notice_texts()` (bar or toasts) and `today_ui` expects Home or Today as the first page, depending on the window. CI runs `shell_ui`, then navigation/today/robustness/dropdown/background in the classic window too, and `shell_ui installed` in the Debian, Fedora and Arch install jobs and the Flatpak.

### Phase 2: Ctrl+K search and book progress (`feat/search-progress`)

- `bahai_reader/finder.py`: Ctrl+K (or the search buttons, or ⋮ → Search the texts…) opens a search over every passage, or only the open book (“This book”; for a prayer, all the prayers). Results are grouped by book or prayer category with the matching words in bold; ↓ moves into them, Enter or a click opens the passage in its place with the match selected and scrolled into view. It is an `AdwDialog` on libadwaita ≥ 1.5 and a small modal window otherwise, so the classic window has it too.
- `search.py`: `fold_map` maps folded text back to the original characters (checked against `fold()` on every passage), so a match found while ignoring accents and apostrophes is shown exactly where it is. Matching uses each passage's cached folded text: 4 ms per query after the first (0.7 s once).
- The libadwaita reader: the book and part as a small line above the heading; “Passage 3 of 27 · about 33 minutes” below it; the footer shows “God Passes By · 3 of 27”, a progress bar through the whole book by words, and “5% of the book” (a prayer shows its place in its category instead). Next is the one suggested (primary) button.
- Tests: `tests/test_finder.py` (8), `tests/finder_ui.py` (in either window; CI runs it in both). README: features and Ctrl+K in the shortcuts table.

## Tests actually run

All on 2026-11-11.

Ctrl+K search and book progress (`feat/search-progress`):

| Where | What | Result |
| --- | --- | --- |
| TUF | unit tests | 247 OK (1 skipped) |
| Arch container, libadwaita window | `shell_ui`, `finder_ui` + the 8 existing UI tests | all passed |
| Arch container, classic window | `finder_ui`, `navigation_ui`, `robustness_ui`, `today_ui`, `dropdown_ui`, `background_ui` | all passed |
| `debian:12` (classic window) | unit tests, `finder_ui`, `smoke_ui`, `shell_ui` (skips) | all passed |

Phase 2 libadwaita window (`feat/adw-shell`):

| Where | What | Result |
| --- | --- | --- |
| TUF | unit tests | 239 OK (1 skipped) |
| Arch container + Xvfb, libadwaita 1.10 (new window) | `shell_ui` + all 8 existing UI tests | all passed |
| Same, `BAHAI_READER_SHELL=classic` | all 8 existing UI tests | all passed |
| Classic window unchanged | Phase 1 screenshots re-rendered in the classic window | 8 of 9 byte-identical; the 9th differs only in the search field’s blinking caret (as before) |
| `debian:12` container, libadwaita 1.2.2 | unit tests, `shell_ui` (skips: classic window chosen), `smoke_ui`, `navigation_ui`, `today_ui`, `chrome_ui` | all passed; the classic window opens |
| Packages built and installed in `debian:12`, `fedora:43`, `archlinux:base` | `smoke_ui installed`, `shell_ui installed` | all passed; Fedora and Arch open the new window, Debian 12 the classic one |

Phase 2 split branch:

| Where | What | Result |
| --- | --- | --- |
| TUF | unit tests | 226 OK (1 skipped): Phase 1’s 214 plus 12 in `tests/test_modules.py` (every pre-split name and method still there, no method hidden inside a function, data modules free of GTK, path and function patches on `reader` reach the package, packaging lists the package) |
| Arch container + Xvfb | all 8 UI tests | all passed |
| Packages built with the pinned nFPM 2.47.0, installed in `debian:12`, `fedora:43`, `archlinux:base` (the CI’s install jobs) | `smoke_ui installed` and `chrome_ui installed` (plus `navigation_ui` on Debian 12) | all passed; `bahai-reader --version` works on Debian 12 |
| No visible change | the 9 Phase 1 screenshots in Light and in Dark, rendered again from the split | 17 of 18 byte-identical; the 18th differs only in the search field’s blinking caret, and two renders of the same split code differ in the same place |
| pyflakes | `bahai_reader/` | clean |

Not run locally: the AppImage and Flatpak builds (no appimagetool / GNOME 51 SDK on TUF). The PR’s CI builds both and starts the Flatpak.

Phase 1 branch:

| Where | What | Result |
| --- | --- | --- |
| TUF (Arch, Python 3.14, GTK 4.24) | `/usr/bin/python3 -m unittest discover -s tests` | 214 tests OK (1 skipped, as on `main`); 200 before, 14 new in `tests/test_chrome.py` |
| Arch container + Xvfb (the CI’s UI tests, as uid 1000) | `chrome_ui` (new), `navigation_ui`, `layout_ui`, `smoke_ui`, `robustness_ui`, `today_ui`, `dropdown_ui`, `background_ui` | all 8 passed |
| Debian 12 container + Xvfb (Python 3.11, GTK 4.8.3, PyGObject 3.42) | unit tests, `chrome_ui`, `smoke_ui`, `layout_ui`, `navigation_ui`, `today_ui` | all passed |

Baseline before any change (`main` at 52a84ad): 200 unit tests OK, and all 7 UI tests passed on GTK Broadway.

Notes on the test setup: TUF has no Xvfb. GTK Broadway crashed (`broadway-server.c:1797: decode_nodes: assertion failed`) when screenshots were rendered offscreen, so the UI tests and screenshots run in throwaway Docker containers with Xvfb instead. `robustness_ui` must not run as root, because root can write to its read-only folder. Two existing UI tests were updated for intended changes: `layout_ui` (only Copy moves into ⋮ in a narrow window now) and `smoke_ui` (the obligatory prayer heading and the ⋮ menu entries).

## Debian 12 and libadwaita

Checked in `debian:12` containers on 2026-11-11:

- Debian 12 (bookworm): **libadwaita 1.2.2**, GTK 4.8.3, PyGObject 3.42.2. bookworm-backports has no newer libadwaita. The review was right.
- Debian 13 (trixie, stable since August 2025): libadwaita 1.7.6, GTK 4.18.6, PyGObject 3.50.0.
- Fedora 43: libadwaita 1.8.8. TUF (Arch): libadwaita 1.10.0. Flatpak (GNOME 51 runtime): current libadwaita.
- Ubuntu 24.04: **not verified**; the container could not reach Ubuntu’s mirrors (DNS failure). Not assumed.

What libadwaita 1.2 lacks for the Phase 2 shell: `AdwNavigationSplitView`, `AdwToolbarView`, `AdwBreakpoint`, `AdwNavigationView` (all 1.4), `AdwPreferencesDialog` and `AdwDialog` (1.5). It has `AdwApplicationWindow`, `AdwHeaderBar`, `AdwToastOverlay`, `AdwLeaflet` (deprecated in 1.4), `AdwPreferencesWindow`, `AdwStatusPage` and the style manager.

Phase 1 does not use libadwaita at all, so it runs on Debian 12 as before.

### Phase 2 shell on Debian 12: options (Tim to choose; nothing dropped)

The approved shell needs libadwaita 1.4 (split view, breakpoints, toolbar view) and 1.5 (preferences dialog). Debian 12 has 1.2.2 and no backport.

- **A. Graceful fallback (recommended).** One app, two windows: on libadwaita ≥ 1.4 (Debian 13, Fedora 43, Arch, the Flatpak and, if confirmed, Ubuntu 24.04) the new shell; on Debian 12 the Phase 1 window, which the split keeps as its own module. The data and reading code are shared, so the text, search, citations, saved passages and theme work the same on both; features that need the new shell (library home, focus mode, the highlights UI) are new-shell only, and Debian 12 keeps what it has today. The `.deb` keeps `Debian 12+` and adds a dependency on `gir1.2-adw-1` (available as 1.2 on Debian 12). Cost: two window modules to keep starting in CI; the Debian 12 install test stays as the guard. A plain libadwaita 1.2 version of the new shell (with `AdwLeaflet`) is possible, but `AdwLeaflet` is deprecated, so it would be throwaway work.
- **B. Raise the `.deb` baseline** to Debian 13 / Ubuntu 24.04 for 0.2.0, and point Debian 12 users to the Flatpak (it already ships, with its own GTK and libadwaita) or to staying on 0.1.x. Simplest code; it is a change to a supported target, so it needs Tim’s explicit yes.
- **C. Flatpak only for Debian 12**, but keep publishing a 0.1.x `.deb` for it with security and text fixes only. Middle ground; two release lines.

Until Tim chooses, nothing about packaging changes: Phase 1 and the split run on Debian 12 (tested in a `debian:12` container) and the shell is not started.

## Hidden Words preamble (finding)

On Hidden Words Arabic no. 1, the official 0.1.9 text opens with “HE IS THE GLORY OF GLORIES” and the prologue (“THIS is that which hath descended from the realm of glory…”), then “* * *”, then “1 O SON OF SPIRIT!”. Persian no. 1 likewise opens with “In the Name of the Lord of Utterance, the Mighty.”

- This is **intended by the importer**, not a stray paste. `scripts/import-bahai-library.py` places short official lines that match no passage (a part’s invocation or prologue) at the start of the passage that follows. Commit 22f5d0e (“Official text, book 1: The Hidden Words”) says so explicitly. The text is bahai.org’s own, word for word; nothing is lost or reworded.
- The app’s older BahaiPrayers.net copy of Arabic no. 1 has no prologue, so the 0.1.9 change is that the prologue now appears at all, attached to no. 1.
- **Not changed.** Whether the prologue should stay inside no. 1, or become its own “Prologue” entry before no. 1 in the contents (a change to how the text is divided, not to the text), is Tim’s call. See “Open questions”.

## Mockups

**Made and approved.** In the repo at [`design/mockups/phase2/`](design/mockups/phase2/README.md) on the `design/phase2-mockups` branch, PR https://github.com/ninepointlabs/bahai-reader/pull/44. Ten stills: Home/library, Reader (with a highlight and a note), Reader for a long work with contents, Today, Saved (collections, highlights and notes), Ctrl+K search, Focus mode, Narrow Home, Narrow Reader, and the Reader in Dark. The README lists the eleven design decisions to confirm (for example: Today folds into Home, Obligatory prayers move under Prayers, the Hidden Words becomes a library book, F11 for focus mode).

They are HTML drawn in libadwaita’s layout and rendered in headless Chrome, not running code. All quoted text, titles and counts come from the bundled library through `extract.py` (quotations were checked against the texts: for example “Free thyself from the fetters of this world” is Persian no. 40). Day-to-day content (passage of the day, reading positions, highlights, notes) is example data.

Approved by Tim: **yes**, 2026-11-11 (“Go with those and continue”, relayed by Hermes), as drawn.

## CI

GitHub Actions on #42, #43 and #44, 2026-11-11 (UTC):

- **Flatpak job: passed on all three** (it builds the bundle and starts the app in the GNOME 51 sandbox; on #43 and #44 that includes the new `bahai_reader` package).
- **`build` job: never got past its first step**, `sudo apt-get update && sudo apt-get install …`, so no test ran there. First runs started 15:10–15:28 and were still on that step at 15:30, past the workflow's own 20-minute timeout. I cancelled them and re-ran them at 15:30; at 15:40 they were stuck on the same step again. The same day a local `ubuntu:24.04` container could not resolve `security.ubuntu.com`, so this looks like an Ubuntu mirror problem, not the code. The package install jobs (Debian 12, Fedora 43, Arch) depend on `build`, so they have not run on GitHub either.
- **So CI is not green yet.** What has been verified is the local results above, which cover the same tests (the unit tests, all UI tests, and package installs in `debian:12`, `fedora:43` and `archlinux:base` containers). To do: re-run the `build` job once Ubuntu's mirrors answer (`gh run rerun <id>` on each PR's latest run).

## Accessibility / Orca

Not started (Phase 2, step 6). Orca is not installed on TUF.

## Open questions and blocked gates

Answered 2026-11-11 by “Go with those and continue” (as I read it; correct me if not): mockups approved; Debian 12 option A; no Blueprint; the Hidden Words prologue stays inside Arabic no. 1.

Still open:
1. **CI** cannot run its `build` job while Ubuntu's mirrors are failing (see “CI”); re-run when they answer.
2. **Ubuntu 24.04's libadwaita version** is still unconfirmed here (believed 1.5, which would get the new window; otherwise it falls back to classic, which is safe either way).
3. **Release 0.2.0** is the intended end; no version bump, tag or release without Tim's OK.
