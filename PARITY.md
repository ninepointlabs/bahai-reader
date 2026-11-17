# Feature parity: GTK Bahá’í Reader (v0.2.3) → Flutter port

Audit of every user-facing feature of the GTK app on `main` at **v0.2.3** (`1cb4bd0`, merge of PR #55), read from
`/home/tim/Projects/bahai-reader` (code, README, DATA-NOTICE.md, `docs/`, `packaging/`, `scripts/`, tests) and the
merged PRs #1–#55, against this repo's branch `parity/phase-1`. The GTK tree was only read.

**Status:** **match** means the same capability and behaviour; **partial** means the capability is there but something
differs (said in Notes); **missing** means it is not there. **New** in Notes means this branch added or completed it.
Where the GTK feature belongs to its classic GTK window, Flatpak or packaging and cannot reasonably be ported one for
one, Notes says so. Pointers are to the GTK code (`bahai_reader/…`, `badi.py`) unless they say otherwise.

Summary: 97 rows. **match 85 · partial 9 · missing 3** (after the 1.0 release work; at the end of Phase 1 it was
match 80 · partial 9 · missing 8). The 3 missing rows are the Flatpak Background portal, restart after update and the
classic window (which does not apply). Every partial row says what differs.

## 1. Library and texts

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Bundled English library | 3,526 passages in all ten BahaiPrayers.net collections, offline (`library.load_library`, `data/*.json`) | match | `assets/library/1.json` is made by `scripts/convert_library.py`, which calls the GTK `load_library()` itself: same ids, titles, groups, citations, spans and references. |
| Official bahai.org text under stable ids | Where bahai.org has the passage (3,509 of 3,526), its text replaces BahaiPrayers.net's under the same id (`use_official`, `data/bahai-org-books.json`) | match | Same converter, so the same replacements and ids. Checked in `test/library_conversion_test.dart`. |
| UHJ messages (515) and Riḍván messages | Under Writings, grouped by decade; the 73 Riḍván messages replace BahaiPrayers.net's under the same ids (`official_items`) | match | |
| Shoghi Effendi's works (7) | Under Writings, by part (`official_items`) | match | |
| Prayers by category | BahaiPrayers.net categories; a prayer listed under each of its categories | match | `Library` in `lib/core/library/library.dart`. |
| Obligatory prayers section | The three prayers, their directions in italics, then Aqdas ¶6, 8, 10, 12, 13, 14 with linked notes and Q&A (`obligatory`, `directions`) | match | The groups and the italic directions are computed by the GTK functions in the converter (and by their Dart port for packs). |
| Grouping by book / by author | Library cards grouped by author in the order Báb, Bahá’u’lláh, ‘Abdu’l‑Bahá, Shoghi Effendi, UHJ; classic window also offers Group by book / Group by author (`writings_by`) | partial | Grouped by author everywhere, with “Compilations” for multi-author books. Desktop and phone show an index of authors that fold open to their books instead of cards (Tim asked for this on 16 Nov). The classic window's Group by book choice is not offered (the libadwaita window does not offer it either). |
| Book contents | Parts, chapters and passages in the sidebar; Back to the library | match | |
| Epistle to the Son of the Wolf under Writings | Comes from the prayer feed but is listed as a book (`PRAYER_FEED_BOOKS`) | match | |
| Aqdas cross-references | “Related passages” menu opens the linked note, Q&A or paragraph | match | Shown as buttons under the passage rather than a menu; same links. |
| Styled spans (bahai.org) | Italics, bold, underlined transliteration, quotations set in from the margin, paragraph numbers small, headings (`rendering.SPAN_STYLES`) | partial | All drawn except quotations, which are shown in a muted colour instead of indented. |
| Headings and place line | Heading says what the passage is (“Arabic no. 1”, the prayer's category, “Obligatory prayers”); eyebrow line with book/part/author; “Passage n of m · about n minutes” (`labels.py`, `shell_progress`) | match | |
| Progress footer | Previous, “book · n of m”, “n% of the book” with a bar, Next pill; the text fades above it | match | |
| Language pack texts | Downloaded languages read from `~/.local/share/bahai-reader/libraries/<id>.json` (`load_bahaiprayers`) | match | **New.** `lib/core/library/packs.dart` is a line-by-line Dart port. Checked against the GTK code: the Amharic pack and all 2,616 English feed passages give identical libraries, including the passage of the day order (Python's Mersenne Twister ported) and the Obligatory prayers groups (`test/packs_test.dart`; the English check runs with `GTK_ENGLISH_PACK`, see `scripts/pack_fixtures.py`). Texts with characters outside the BMP would have highlight offsets that differ from GTK's (none in the bundled data). |
| Amharic bundled | GTK bundles English only; other languages are downloaded | partial | Amharic (`90.json`) is bundled here because it was the one pack on this machine when the experiment started. Harmless, but the Phase 2 build can drop it now that packs are read and downloaded. |

## 2. Reading

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Passage by passage, Previous/Next within the group | Previous/Next stays within the category or book division | match | |
| Copy with citation | Ctrl+Shift+C or the header button: the passage or the selected words, then “— citation”; prayers add “Prayers, category”; toast “Copied with its citation” (`citations.clipping`) | match | Port of `clipping()`. |
| Side by side | Aa → Side by side: Off, English or a downloaded language; paired by numbering (`match`); messages for unpaired prayers, missing language or passage; second pane follows the scroll proportionally; stacks in a narrow window (`reading.show_second`) | match | **New.** Same messages and pairing; `test/parity_test.dart`. |
| Random passage | ⋮ → Random passage, Ctrl+R: prayers, Hidden Words, Gleanings, Prayers and Meditations ≤ 500 words, not the current one; subtitle “Random passage · …” | match | **New.** |
| Passage of the day | Same passage all day, fixed shuffle (seed 1844), on Home and Today | match | Same order as GTK, for bundled and downloaded languages. |
| Reading font | Aa → Reading font: any installed font family (Pango list); default Noto Serif, else DejaVu Serif | match | **New.** Families from `fc-list` on Linux; used for the text, Today, the counter and Side by side. |
| Interface font | Aa → Interface font: System or Monospace (`chrome_font`) | match | **New.** |
| Text size | 15–36, default 22 | match | |
| Line spacing | 0–20 px between wrapped lines, default 8 | match | **New.** Approximated as extra line height (spacing / size); paragraph gap unchanged. |
| Page margins | 24–160, default 80, giving way below a 360 px text column | match | **New.** Same rule. |
| Smooth wheel scrolling | Wheel steps animate (`queue_scroll`), touchpads native | partial | Flutter's own scrolling; no eased wheel animation. |
| Focus mode | F11: only the text; F11 or Esc brings back the sidebar and header | match | |
| Narrow windows | Below 700 px sidebar and content take turns; Copy moves into ⋮; arrows shorten; Side by side stacks | match | |
| Directions in italics | Obligatory prayers' directions in italics | match | |
| Said toggle beside an obligatory prayer | “Said today / this morning / at noon / this evening”, same mark as Today | match | |
| Collection under a saved passage | “Collection [Unsorted ▾] Manage…” under a saved passage (`show_filing`) | match | **New.** |

## 3. Search

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Folding | Case, accents (NFKD), apostrophes, hyphens ignored (`search.fold`, `fold_map`) | match | **New:** the folding table now covers every BMP character (GTK `fold()` per character), so downloaded languages fold exactly as in GTK, not just the bundled ones. |
| Ctrl+K search | This book · n / Everything · n, grouped by book or prayer category, bold matches, Enter opens the first, the match is selected and scrolled into view (`finder.py`) | match | |
| Contents search (Ctrl+F) | Shows the sidebar and puts the cursor in “Search this section…”; narrows the list without moving the reading position; “No passages match …” | match | **New:** Ctrl+F now focuses the field. |
| Today calendar search | Narrows the Upcoming / This year dates | match | |
| Offline city search | Accent-insensitive search of the bundled GeoNames list, “City, region” narrowing, ranked (`search_cities`) | match | |

## 4. Highlights, notes, bookmarks, collections

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Highlights | Select words → bar with four colours, Note…, Copy; Ctrl+H; one colour per word; click to recolour, note or remove (`highlights.py`, `marks.py`) | match | Same record shape `{id,start,end,words,color,created,note}`. |
| Notes | Up to 5,000 characters with a counter; words with a note underlined | match | |
| Anchoring | Offsets, else nearest occurrence of the words, else kept and listed but not drawn | match | |
| Highlights & notes list | Saved → Highlights & notes · n, newest first, each opens its passage at the highlight | match | |
| Saved passages (bookmarks) | Ctrl+D / star; ids in `saved` | match | |
| Named collections | Saved grouped by collection then Unsorted; Collection chooser under a saved passage; Manage collections (create, rename, delete with the same checks and messages); deleting keeps passages saved; unsaving removes from the collection (`saved.py`, `clean_collections`) | match | **New.** Same `collections` shape and cleaning. Phone: the Saved tab is grouped too, with a per-passage Collection menu and Manage collections. |
| Marks across languages | Saved passages and highlights follow by `match` into another language; a highlight from another language shows as a card with its note; stored ids never rewritten | match | |

## 5. Reading positions

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Per-book position | `positions[book] = id`; a book opens where it was left | match | |
| Continue reading | Last three books on Home with % through the book (`recent`, 6 kept) | match | |
| Restore on launch | Opens the last section, book and passage (`section`, `book`, `last`) | match | **New.** `ShellModel.restore()`; a new install opens on Home. |
| Contents groups remembered | Opened/closed groups kept in `expanded`; the group holding the passage opens without being remembered | match | **New.** Kept in settings under the GTK paths (GTK `hidden/…` is `writings/The Hidden Words/…` here). |

## 6. Today, calendar, obligatory prayer, the Fast, reminders

Ported earlier in this experiment line by line from `badi.py`, `today.py`, `reminders.py`, `location.py`, and checked
against answers generated by the GTK code (`test/calendar_test.dart`, `test/reminders_test.dart`: 11,420 reminders
equal).

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Badí‘ date | From the UHJ table 172–221 B.E.; changes at local sunset; “not published yet” outside | match | |
| Sun times | NOAA calculation for a typed-in place; polar day/night messages | match | |
| Clock times | Sunrise/noon/sunset hours from the NSA replace the sun | match | |
| Obligatory prayer times | Short/Medium/Long windows, Long prayer's period choice (sunset/noon/midnight/rolling), guidance links | match | |
| Said today / Fasted today | Private records, Keep a record switch, Clear my records | match | |
| Next Feast and Holy Day | With work suspended, readings and prayers links | match | |
| The Fast card | Day n of 19, fasting hours, Fasted today, ¶16 | match | |
| Today calendar in the sidebar | Upcoming 12 months, This year's months, searchable | match | |
| Home strip | Today's date, the prayer's state, the passage of the day | match | |
| Reminders | Prayer opens and 30 min before close; Long prayer nudge 1–12 h; Feasts, Holy Days, the Fast notices and daily; 30 s wall-clock tick; stale skipped; one per group; Said today and Open actions | match | Linux via the freedesktop notification service; Android via alarms (beyond GTK). |
| Keep reminders running | Opt-in XDG autostart entry running `--background`; closing hides the window; a launch opens it | partial | Same behaviour and the same app id now, but the entry is still named `com.ninepointlabs.bahai_reader-reminders.desktop`, and `keep_running` is not imported, so people who had it on turn it on again (said in the release notes). |
| Flatpak Background portal | Inside Flatpak, asks the XDG Background portal instead of writing an entry | missing | The Flatpak build exists now, but the app writes an autostart file there, which the sandbox keeps inside itself; reminders run only while the app is open (said in the README). |
| Location never sent | Typed in, rounded to 0.01°, stays local; Clear location | match | Phones may also ask the device once (“Use my location”), still rounded and local. |

## 7. Alláh-u-Abhá counter

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Counter | From Today, Obligatory prayers or Ctrl+Shift+A; target 95/19/9/custom (remembered); Space/Enter/click counts; Backspace undoes; Ctrl+0 resets; Esc back; “95 of 95”; ¶18 beneath | match | |
| Screen reader announcements | Announced at every nineteenth and at the target | match | **New** (`SemanticsService.sendAnnouncement`). |

## 8. Languages and offline behaviour

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Languages & offline libraries window | 112-language catalog, searchable, offline ones first with “· Offline”; what each offers; “update to add: …”; Use this language / Download & use; Update downloaded content; Check available languages; progress; can't close while downloading (`languages.py`) | match | **New** (`lib/features/settings/languages_dialog.dart`). English is always the bundled library here (GTK can also re-download English feeds; not offered, since the bundled English carries the bahai.org texts). |
| Downloads | Only when asked; all collections offered; validated; written atomically; a failure keeps what was there; GTK's sentences for errors (`download_language`, `download_problem`) | match | **New** (`lib/core/library/downloads.dart`). Saved in `~/.local/share/bahai-reader-flutter/libraries`, never in the GTK folder. Tested with a fake network; **not tried against bahaiprayers.net** from here. Phones: hidden (the Android build has no INTERNET permission). |
| Packs already downloaded by the GTK app | — | match | **New.** Read from `~/.local/share/bahai-reader/libraries` read-only (never written; tested bytes and mtime). This app's own download of a language comes first. |
| Unreadable or missing language | Falls back to English with a notice | match | **New.** Same two sentences. |
| No network otherwise | Starting, reading, searching, switching to a downloaded language use no network | match | The only network code is `downloads.dart`, called from the dialog's buttons. |

## 9. Settings, appearance, window

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Appearance | Omarchy (follows the live theme every second), Light, Dark, Sepia | match | Re-reads the Omarchy colors every 2 s. |
| Damaged settings | Defaults, file kept as `.bad`/`.bad.n` (never replacing one), a notice; damaged collection entries dropped but passages stay saved | match | |
| Save failure | “Settings and saved passages cannot be stored (…)” once | match | **New.** |
| Notices | Dismissable messages at the bottom of the window | match | **New** on desktop: start notices (import, language) are shown once, dismissable. |
| libadwaita window | Sidebar Home/Prayers/Writings/Saved with counts, book mode with Back, header with Search, Aa, Copy, Save, ⋮ | match | Prayers and Writings show a welcome page until a topic or book is chosen (Tim asked for this; GTK shows the first passage). |
| Classic GTK window | Older libadwaita (Debian 12) gets the classic window; `BAHAI_READER_SHELL` | missing | Not applicable: the Flutter app has one window layout on every system. The classic window existed only for old libadwaita. |
| Undecorated on Omarchy | No title bar; Hyprland draws the border | match | |
| Single instance | A second launch shows the open window | match | |
| Restart after update | A running copy restarts as the newly installed version on the next launch (PR #50, `updated_on_disk`) | missing | Not done. A copy kept running for reminders keeps running the old version until it is quit. |
| Sidebar width | Classic window remembers a dragged width (`sidebar_width`) | partial | The sidebar is 26% of the width (240–340 px), as in the libadwaita window; not draggable. |

## 10. Keyboard

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Ctrl+F, Ctrl+K, Alt+←/→, Ctrl+PgUp/PgDn, Ctrl+D, Ctrl+H, Ctrl+Shift+C, Ctrl+T, Ctrl+Shift+A, F1, F11, Esc, Ctrl+? | As in the README table | match | |
| Ctrl+R | Random passage | match | **New.** |
| Ctrl+Q | Quit; while reminders keep running, closes the window instead | match | **New** (the runner's `close`, which hides when keep-running is on). Also ⋮ → Quit. |
| Counter keys | Space/Enter, Backspace, Ctrl+0, Esc | match | |
| Page Up / Page Down | Scroll the passage | partial | Flutter's default scrolling keys; not tested. |
| Tab order | Search → contents list (one stop, arrows inside) → reading pane or Today's cards | partial | Flutter's focus order; the contents list is not one Tab stop and has no arrow-key movement. Not audited. |
| Keyboard shortcuts dialog | Grouped list (Reading, Finding, Counter, The app) | match | **New:** now the same rows as GTK's `SHORTCUT_GROUPS`, plus Quit. |

## 11. Accessibility

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| Names for screen readers | Every control named (`name_widget`), checked by an AT-SPI audit and a headless Orca run (`scripts/accessibility/`) | partial | Flutter builds a semantics tree from labels and tooltips, and the Linux embedder exposes it through ATK. Not audited with AT-SPI or Orca; that audit cannot be run one for one (the GTK script inspects GTK widgets). Needs its own pass in Phase 2. |
| Reduced motion | No view transitions | match | No transitions between views. |

## 12. About, attribution and notices

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| About | F1 / ⋮: version, tagline, made by Nine Point Labs, created, MIT license (Read it, with DATA-NOTICE), texts, bahai.org, places, calendar, support email with Email and Copy, privacy, built with, Copy version details (`about.py`) | match | **New:** same rows. Email opens the mail app with `xdg-open` (the version details in the body). States that the GTK app is still the released one. |
| “Copyright © Bahá’í International Community, bahai.org” | On every bahai.org citation and copied text | match | From the converter. |
| DATA-NOTICE.md | BahaiPrayers.net, bahai.org, Badí‘ dates and GeoNames notices; texts not MIT | match | Copied with paths adapted; shown in About. |
| Footer “English · Available offline · Texts: BahaiPrayers.net, bahai.org” | Language name; bahai.org only for English | match | |

## 13. Command line, packaging and distribution

| Feature | GTK behaviour | Flutter | Notes |
|---|---|---|---|
| `--help`, `--version`, unknown options | Print and exit (2 for an unknown option) | match | **New.** Answered by the new process even when a copy is running. `--open PASSAGE` is extra. |
| `--background` | Reminders with no window; a later launch opens it | match | |
| AppImage | `bahai-reader-<v>-x86_64.AppImage` with `--install-desktop-entry`, `--remove-desktop-entry`, `--check-host` | match | `bahai-reader-<v>-x86_64.AppImage` (same name and zsync update info), with `--install-desktop-entry` and `--remove-desktop-entry`; runs on the host GTK 3. `--check-host` is dropped: there is no Python/GTK 4 to check. Release 1.0 work. |
| Flatpak bundle | `bahai-reader-<v>-x86_64.flatpak`, `org.bahai.Reader` | match | `bahai-reader-<v>-x86_64.flatpak`, `org.bahai.Reader`, GNOME 51 runtime. Release 1.0 work. |
| .deb / .rpm / pacman packages | nFPM-built, `/usr/share/bahai-reader` | match | nFPM-built, bundle in `/usr/lib/bahai-reader`, launcher `/usr/bin/bahai-reader`. Names now carry x86_64 (`_amd64.deb`, `.x86_64.rpm`, `-x86_64.pkg.tar.zst`) because the app is compiled. Installed and started in CI on Debian 12, Ubuntu 24.04, Fedora 43 and Arch. |
| autonomix-cli tracking | `autonomix-cli add https://github.com/ninepointlabs/bahai-reader` | match | Same repository and package name; autonomix-cli picks assets by extension. In the README and release notes. |
| Desktop entry and icon | `org.bahai.Reader.desktop`, metainfo, icons; `install.sh` for a checkout | match | `org.bahai.Reader` app id, desktop file, metainfo and icons, as GTK; the Bahá’í Reader icon on Android and Windows too. No `install.sh` (a checkout needs a Flutter build first). |

## 14. Data migration from the GTK app

First-run import: `lib/core/settings/gtk_import.dart` (rule in its header), tests in `test/gtk_import_test.dart`.

| GTK key | Imported | Rule / reason |
|---|---|---|
| `highlights` (with notes), `highlight_color` | yes | Merged; a GTK highlight overlapping one here is skipped (this app's wins). Colour on first run only. |
| `saved`, `collections` | yes | Merged; collections matched by name ignoring case; a passage is filed only if in no collection here. |
| `records` (`said`, `fasted`), `reminders_sent` | yes | Merged (valid marks only). |
| `positions`, `expanded` | yes | Added for books / groups with none here. |
| `recent` | first run | Continue reading order. |
| `theme`, `size`, `language`, `keep_records` | first run | Always have a value here, so only into a new settings file. `Omarchy` → follow Omarchy. |
| `location`, `clock_hours`, `prayer`, `long_period`, `long_lead_hours`, `counter_target`, `font`, `chrome_font`, `spacing`, `margin`, `compare`, `last`, `section`, `book`, `reminders` (switches) | yes, when unset here | Never replaces a value set here. |
| `keep_running` | no | Turning it on writes a login entry; doing that unasked would start a second background reminder process beside the GTK app's. In Phase 2 the GTK entry runs the new app. |
| `sidebar_width` | no | The sidebar is sized as a share of the window, as in the libadwaita window. |
| `writings_by` | no | The classic window's grouping; Writings are always by author here. |
| Language packs | read in place | Read from `~/.local/share/bahai-reader/libraries` without copying; never written. |
