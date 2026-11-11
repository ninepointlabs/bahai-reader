# Bahá’í Reader UX redesign: status

Brief: UX Phases 1 and 2, Python + GTK 4 + libadwaita (approved by Tim 2026-11-11, 8:42 AM CT).
Source review: “Bahá’í Reader UX and Stack Review” (read 2026-11-11).
Nothing here is merged, tagged or released. Nothing was pushed to `main`.

**Current gate: waiting for Tim to approve the Phase 2 mockups before the new libadwaita shell is built.**

## Done

| Step | Branch | PR | State |
| --- | --- | --- | --- |
| Phase 1: quick wins on the current GTK 4 code | `feat/ux-phase1-quick-wins` (base `main`) | see PR list below | open, not merged |

PR links are filled in below as each PR is opened.

### Phase 1 (one PR)

1. **Interface font.** `window { font-family: monospace; }` is gone. The interface uses the desktop’s own interface font (proportional; Adwaita Sans on TUF). **Aa → Interface font → Monospace** brings the old look back for anyone who wants it. The reading font (`Gtk.TextView`, DejaVu Serif 22 px by default, or the user’s choice) is unchanged and still set separately.
2. **Compact section switcher.** The six bordered full-width buttons are now one `Gtk.ListBox` of icon-and-label rows with the current section selected. The header’s Today button is gone (Today is the first row; Ctrl+T still works). Random moved into ⋮ as “Random passage” (Ctrl+R still works). The ☰ and ⋮ glyphs are now the standard `sidebar-show-symbolic` and `view-more-symbolic` icons, all present in Debian 12’s Adwaita icon theme.
3. **Labels.** The obligatory prayers are listed as Short, Medium and Long Obligatory Prayer. A prayer’s heading is its category (“Healing”), using the category it was opened in when it has several. Obligatory prayers are headed “Obligatory prayers” because bahai.org’s text already prints the prayer’s name as its first line; the name, author and length are in the line beneath. The subtitle never repeats the heading (fixes “Epistle to the Son of the Wolf” twice) and adds the author where the book’s name does not already include it. Branch names in the contents list now use the full width, with a tooltip holding the whole name; passage rows keep their tooltips.
4. **Reading footer.** Previous/Next and the status line sit under a 1 px divider, and the text fades out over its last 28 px above it, so no line is hidden under the bar. The text’s bottom margin (50 px) lets the last line scroll clear of the fade. The citation now follows the text after one line break with a 10 px gap, not an empty paragraph.
5. **Softer controls.** 6 px radii, no hard borders, a light fill for ordinary buttons, flat buttons in the header, menu and contents list, and one primary style (accent fill, text colour chosen for 4.5:1 contrast) used for Next and the counter’s Count. The pane separator is a 1 px hairline instead of a 5 px selection-coloured bar. Today cards have 12 px radii.
6. **Hidden Words preamble.** See the finding below. No text was changed.

Also: the said-today toggle under an obligatory prayer has a tooltip explaining what it does. README features, the Aa/⋮ description and the interface-font note are updated; the keyboard shortcuts are unchanged.

## Tests actually run

All on 2026-11-11, on the Phase 1 branch.

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

Phase 1 does not use libadwaita at all, so it runs on Debian 12 as before. The Phase 2 options are in “Open questions”.

## Hidden Words preamble (finding)

On Hidden Words Arabic no. 1, the official 0.1.9 text opens with “HE IS THE GLORY OF GLORIES” and the prologue (“THIS is that which hath descended from the realm of glory…”), then “* * *”, then “1 O SON OF SPIRIT!”. Persian no. 1 likewise opens with “In the Name of the Lord of Utterance, the Mighty.”

- This is **intended by the importer**, not a stray paste. `scripts/import-bahai-library.py` places short official lines that match no passage (a part’s invocation or prologue) at the start of the passage that follows. Commit 22f5d0e (“Official text, book 1: The Hidden Words”) says so explicitly. The text is bahai.org’s own, word for word; nothing is lost or reworded.
- The app’s older BahaiPrayers.net copy of Arabic no. 1 has no prologue, so the 0.1.9 change is that the prologue now appears at all, attached to no. 1.
- **Not changed.** Whether the prologue should stay inside no. 1, or become its own “Prologue” entry before no. 1 in the contents (a change to how the text is divided, not to the text), is Tim’s call. See “Open questions”.

## Mockups

Not made yet. They come after the `reader.py` split and before the new shell.

## Accessibility / Orca

Not started (Phase 2, step 6). Orca is not installed on TUF.

## Open questions and blocked gates

1. **Hidden Words prologue:** keep it inside Arabic no. 1 (as now), or show it as its own “Prologue” entry before no. 1? Either way the words stay bahai.org’s.
2. **Phase 2 shell on Debian 12** (libadwaita 1.2): see the options in the Phase 2 section once written.
3. **Gate:** the new shell waits for Tim’s approval of the mockups.
