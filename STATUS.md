# STATUS — Bahá’í Reader Flutter port

Date: 2026-11-16 · Machine: TUF (Linux, Omarchy/Hyprland) · Flutter 3.47.9 stable, Dart 3.13.7 (the existing
user-local install; nothing was reinstalled and no sudo was used).

The released app is still the GTK Bahá’í Reader: https://github.com/ninepointlabs/bahai-reader · https://bahaireader.org

## Promotion, Phase 1: feature parity (2026-11-16)

Brief: `designer-briefs/bahai-reader-flutter-promotion.md`. Branch **`parity/phase-1`**, PR: PR_URL (not merged).
Phase 2 was not started.

**What was done**

1. **Audit:** [`PARITY.md`](PARITY.md) lists 97 user-facing features of the GTK app at v0.2.3 (`1cb4bd0`): 80 match,
   9 partial, 8 missing. The 8 missing are packaging and distribution (AppImage, Flatpak, .deb/.rpm/pacman, autonomix,
   the `org.bahai.Reader` desktop id), restart-after-update, the Flatpak Background portal and the classic GTK window;
   all Phase 2 or not applicable. Every partial row says what differs.
2. **Missing and partial items implemented** (commits on the branch):
   - **First-run GTK import** (`lib/core/settings/gtk_import.dart`): on the first start, and from Settings → Import
     again, it reads `$XDG_CONFIG_HOME/bahai-reader/settings.json` and copies highlights with their notes, saved
     passages, collections, Said/Fasted records, positions, opened groups, and settings (theme, text size, fonts,
     spacing, margins, Side by side, language, location, clock hours, prayer, Long prayer period and nudge, counter
     target, reminder switches, last passage/section/book). The rule: marks are merged, never replaced; settings fill
     only what has no value here, and the ones that always have a value (theme, size, language, keep records, highlight
     colour, Continue reading) only on the first run. **Not imported:** `keep_running` (it would add a second login entry
     beside the GTK app's), `sidebar_width`, `writings_by` (reasons in PARITY.md §14). The GTK file, its `.bad*`
     backups and both GTK folders are only read. A damaged GTK file imports nothing, is left as it is, and is tried
     again at the next start; a missing one counts as done.
   - **Language packs**: a line-by-line Dart port of the GTK pack loader (`lib/core/library/packs.dart`) reads packs
     in the GTK format from this app's folder and, **read only**, from `~/.local/share/bahai-reader/libraries`.
     **Languages & offline libraries** (Download & use, Update downloaded content, Check available languages; the
     network only on those buttons; saved atomically in `~/.local/share/bahai-reader-flutter/libraries`). Search
     folding now covers the whole BMP.
   - **Side by side**, **collections** (Saved grouped, Collection under a saved passage, Manage collections; phone
     Saved tab too), **reading font / interface font / line spacing / page margins** (Aa), **Random passage** (Ctrl+R),
     **Quit** (Ctrl+Q; hides while reminders keep running), **Ctrl+F** into the section search, **restore the
     section, book and passage at start**, **remembered contents groups**, **About** with GTK's rows, the counter's
     **screen-reader announcements**, a notice when settings **cannot be saved**, start **notices shown** on desktop,
     **`--help` / `--version`**, the full **shortcuts** list.
3. **Data migration tests** (`test/gtk_import_test.dart`, 7): first run imports every field above with the GTK record
   shapes; GTK folder unchanged (every file's bytes and mtime, no file added or removed, incl. an existing
   `settings.json.bad`); importing again adds nothing and keeps changes made here (note, colour, theme, size, prayer,
   collection filing); an existing settings file keeps its settings and only empty ones are filled; damaged and
   non-object GTK files; a missing file; the desktop shows what was imported.

**Tests (real results)**

- `flutter analyze`: **No issues found!**
- `flutter test`: **`00:16 +81 ~1: All tests passed!`** — 81 passed, 1 skipped, 16 test files. The skipped test is
  the whole-English-library check, which needs a 10 MB fixture outside the repo:
  `python3 scripts/pack_fixtures.py /tmp/en.json && GTK_ENGLISH_PACK=/tmp/en.json flutter test test/packs_test.dart`
  → **`+5: All tests passed!`** (2,616 English feed passages identical to the GTK app's output).
- New test files: `test/gtk_import_test.dart` (7), `test/packs_test.dart` (5), `test/parity_test.dart` (11).

**Linux build**

- `flutter build linux --release` → `✓ Built build/linux/x64/release/bundle/bahai_reader`.
- `bahai_reader --version` → `Bahá’í Reader 0.0.1` (exit 0); `--help` prints the usage (exit 0); `--bogus` → exit 2.
  These were run with the earlier build already running in the background, and answered without reaching it.
- Started hidden (`--background`, `BAHAI_READER_SEPARATE=1`, scratch `XDG_CONFIG_HOME`/`XDG_DATA_HOME` holding a
  **copy** of the real GTK settings and Amharic pack): first run imported the real shapes (theme, size 21, section,
  last passage, prayer, five reminder switches, location, 2 positions, Continue reading, 37 groups;
  `keep_running` left off) and exited as `--background` does with keep-running off. Second run with keep-running on
  stayed up hidden for 8 s with no window mapped, then was stopped. The copy's SHA-256 was unchanged, and the real
  `~/.config/bahai-reader/settings.json` and `~/.local/share/bahai-reader/libraries/90.json` kept their size and mtime.
- **Not looked at on screen**: you were on workspace 12, so no window was opened. The new dialogs (Languages,
  Collections, Aa) and Side by side are covered by widget tests only.

**Not done / left (also in PARITY.md)**

- **Downloads were not tried against bahaiprayers.net** (tested with a fake network). Worth one real “Download & use”
  before Phase 2.
- Accessibility: no AT-SPI/Orca audit of the Flutter window; Tab order differs (the contents list is not one Tab
  stop with arrow keys). Quotations in bahai.org texts are muted, not indented. Wheel scrolling is not eased.
- Packaging, `org.bahai.Reader` app id/desktop entry/icon, window title (still “… (Flutter experiment)”),
  restart-after-update, Flatpak portal: Phase 2.
- Amharic is still bundled (GTK bundles only English); can be dropped in Phase 2.
- **On this machine:** your running Flutter copy (pid 1716546) is the earlier build and was not restarted. When
  the new build first starts with your real settings, it will import from your GTK settings once: it already has its own
  settings file, so only marks and empty settings are filled. Your GTK settings have all five reminder switches on;
  any switch not set in the Flutter settings will be turned on, so with both apps running, reminders may come twice.

**Nothing else was touched:** the GTK checkout (`git status`: only its own untracked `CHECKLIST-features.md`), its
worktrees, its `main`, tags and releases, bahaireader.org, `~/.config/bahai-reader/` and `~/.local/share/bahai-reader/`
(read only). No merge, tag, release, rename, archive or visibility change. Nobody was contacted.

**Phase 2 (outline only; not started; needs Tim's OK):** tag the GTK app `gtk-final` and keep it on `gtk-legacy`;
replace `main` of `ninepointlabs/bahai-reader` with this app in one PR; switch the app id to `org.bahai.Reader` (so
existing autostart entries and desktop files keep working) and drop “(Flutter experiment)”; build the AppImage,
Flatpak bundle and .deb/.rpm/pacman packages under the **same asset file names**; release 1.0; update bahaireader.org,
the README (with the autonomix-cli install line), a blog post and social posts (#bahai #linux), adding Android once
ready; archive `bahai-reader-flutter` with a pointer to the main repo.

---

# Earlier: the Flutter experiment (v0)

## Update 5: reminders on time, and "Use my location" on phones (2026-11-16)

Tried on a real phone (Pixel 11 Pro XL, Android, release build over USB). The first reminder ("Short Obligatory
Prayer · Its time is open, until 5:20 PM") showed as soon as notifications were allowed, and a week of alarms was set.
But Android had not allowed exact alarms, so every alarm had a one-hour window: the "closes at" nudge could come too
late and then be dropped as stale.

- **Reminders on time:** the app now declares `SCHEDULE_EXACT_ALARM`. Turning a reminder on, and once at start if
  reminders are already on (`asked_exact_times` in settings), offers "Reminders on time" → Android's "Alarms &
  reminders" page for the app. Location & reminders shows a notice and an "Allow reminders on time" button while it
  is not allowed. When it is allowed, `BootReceiver` (now also on `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`) sets
  the alarms again as exact ones, as does the app when it comes back to the front.
- **Use my location:** a button at the top of Location (phones only) asks the phone once for an approximate fix
  (`ACCESS_COARSE_LOCATION` only, requested when tapped; `Locate.kt`, `lib/core/platform/locator.dart`). The point is
  rounded to 0.01° as before, named "Near <city>" after the largest bundled city within 5 km or else the nearest within
  25 km (`nearestCity`), and given the phone's time zone. Still no `INTERNET` permission.
- Tests: `test/location_test.dart` (3). 58 tests pass; `flutter analyze` clean.
- **Verified on the phone:** the build installs, the two permissions are declared, the app starts and sets its alarms.
  **Not yet seen on the phone:** the dialog, the settings page, and a GPS fix (the phone was locked).

## Update 4: Today and reminders on phones (2026-11-15, late)

Asked for: “add Today and reminders to the phone layout too”.

- **Phone layout** (`lib/features/library/library_screen.dart`, `lib/features/today/phone_today.dart`): tabs Today ·
  Writings · Prayers, opening on Today (the same `TodayView` cards as the desktop, buttons opening pages); Prayers
  starts with an “Obligatory prayers” card (counter, Location & reminders, the three prayers and the guidance, read
  with Next/Previous among them); ⋮ → Location & reminders (the same settings as a full page); the reader shows the
  “Said today / this morning …” button under an obligatory prayer. Today, the counter, Location & reminders and the
  Said button moved to `lib/features/today/`, shared by both layouts.
- **Reminders on Android**: the same rules (`upcomingReminders()` in `reminders.dart`, built on `candidateReminders()`)
  produce the next 7 days, handed to `android/app/src/main/kotlin/.../Reminders.kt`, which sets an alarm per reminder
  (exact where Android allows it, otherwise as near as it allows), shows it when due (replacing its group, timing out
  when stale), and sets the alarms again after a restart (`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`). Handed over again
  at start, when the app comes back to the front, hourly while open, and when a setting or Said mark changes.
  “Said today” on a notification is kept for the app and cancels that prayer’s later reminders at once; “Open” opens the
  app on the prayer or Today. The device’s time zone now comes from Android (Dart cannot read it there). Notification
  permission is asked when a reminder is first turned on. New permissions: `POST_NOTIFICATIONS`,
  `RECEIVE_BOOT_COMPLETED`; still no `INTERNET`.

Verified: `flutter analyze` clean; `flutter test` **54 passed** (new `test/phone_today_test.dart` (3): phone opens on
Today, prayer chosen on the Location page, Said from Today shows in the prayer, Obligatory prayers → counter, and the
scheduling/pending-tap flow; `reminders_test.dart` gains a check that the week handed over contains every reminder the
desktop would send at its time over six days). On the Android emulator (API 36, headless, debug build with seeded clock
hours): the due reminder showed at once with Said today and Open; 15 alarms were set; with the app process killed, the
“closes at 10:16 PM” alarm fired on time and replaced the first; tapping Said today in the shade withdrew it and, on
opening the app, the mark was recorded (Today showed ✓ Said today); tapping Open on a Medium reminder opened the
Medium prayer among the three. The release APK permissions were checked with aapt.

Not verified / differs: reboot re-arming was not tested (no reboot of the emulator); behaviour under Doze and battery
savers on real phones untested (alarms may come a few minutes late without the exact-alarm permission, which is not
requested); reminders stop if the app is not opened for a week. iOS has no reminders.

Follow-up fix: the phone reader headed many passages (655 in English, among them the Medium prayer) with their
title cut off mid-word (“TO BE RECITED DAILY… le”): titles are the opening words worked out without margin numbers and
the text’s own heading line, but the check compared them with the raw text. `phoneHeading()` (labels.dart) now
compares with the unnumbered text, so those show no heading (or just their number); real titles (Some Answered
Questions chapters, Epistle to the Son of the Wolf) stay; a long title found further in counts as the opening too
(Hidden Words no. 1, after its preface). Checked in both bundled languages: English keeps 78 title headings, all names
(the 9 long ones are Some Answered Questions chapters); Amharic (191 passages) has none and was not affected before
either. Tested in `test/labels_test.dart` (no English prayer headed by an 80+ character title; in English and
Amharic no long heading is words from the text) and seen on the emulator.

## Update 3: reminders (2026-11-15, night)

Asked for: “add the reminders too”. Ported from the GTK app’s `badi.py` (reminders), `reminders.py` and `location.py`,
read-only.

- **What is sent** (`lib/core/calendar/reminders.dart`, a line-by-line port): the obligatory prayer when its time opens
  and 30 minutes before it closes unless said; the Long prayer, once 1–12 hours (default 2) before its period resets if
  not marked (with “24 hours since last said”, before those 24 hours end); Feasts on the afternoon (15:00, or an hour
  before an earlier sunset) of the day they begin; Holy Days the afternoon before and at 9:00 on the day; the Fast 5, 3
  and 1 days before; each fasting day 30 minutes before sunrise and at sunset. Clock times without a location. Each is
  sent once, only while still current (stale ones after a sleep are skipped), the latest per group; sent ids are kept 3
  days (`reminders_sent`). Checked every 30 s, like GTK’s tick. Everything is off until turned on.
- **Notifications** (`lib/core/platform/notifier.dart`): the freedesktop `org.freedesktop.Notifications` service over
  the local session bus (pure-Dart `dbus` package, already in the dependency tree via `path_provider_linux`). Buttons:
  “Said today” (marks it without opening the window and withdraws the notification) and “Open” (brings the window
  forward on Today or the prayer). A later reminder of the same group replaces the shown one. Windows/macOS/phones:
  not sent (`NoNotifier`); the dialog says so.
- **Location & reminders** (renamed from Location & obligatory prayer): “Remind me when its time opens and before it
  closes”, the Long prayer’s nudge and hours, “Feasts, Holy Days and the Fast” (four switches), “Keep reminders running
  when the window is closed” with its note and status. “Reminders…” buttons are back on Today’s prayer, events and
  Fast cards.
- **Keep running** (Linux runner, `linux/runner/my_application.cc`): the app is now single-instance (a second launch
  presents the window; `BAHAI_READER_SEPARATE=1` opts out for tests); with the setting on, closing the window hides it
  and the process keeps sending reminders; a login entry `~/.config/autostart/com.ninepointlabs.bahai_reader-reminders.desktop`
  starts it with `--background` (window hidden). Turning it off removes the entry; then closing quits. A
  `--background` start with the setting off exits at once. No Flatpak/Background portal path (there is no Flatpak).
- Settings use the GTK keys: `reminders`, `long_lead_hours`, `reminders_sent`, `keep_running`.
- Fixed on the way: two settings saves close together could collide on `settings.json.tmp` (“Cannot rename file”);
  saves now run one after another. Home’s narrow cards clipped long buttons (“Open the Short Obligatory Pra…”); their
  buttons now stack and wrap.

Verified: `flutter analyze` clean; `flutter test` **50 passed**. New: `test/reminders_test.dart` compares every
candidate reminder (id, group, title, body, times to the second, Said mark, target) and the due/marked lists with the GTK
code for 1,152 cases (Haifa, Chicago, clock hours, no location × 8 prayer/switch settings × 9 dates around the Fast,
Twin Holy Days and Feasts × 4 hours): 11,420 reminders, all equal (`scripts/reminder_fixtures.py`).
`test/reminders_app_test.dart` (4): sent once, “Said today” marks and stops the closing nudge, a bad mark is ignored,
“Open” routes to the prayer in the window, settings cleaning, the login entry’s text/quoting and removal, the dialog’s
switches. On this machine (Linux release build, quickshell as notification server, scratch config): the prayer
reminder arrived with the right text and buttons (seen on the bus); its “Said today” action recorded the mark and
closed the notification; with keep-running on, closing the window via Hyprland hid it while the process kept running,
and a second launch exited and brought the same window back, redrawn.

Not verified / differs: “Open” from a notification bringing a hidden window forward was only covered by the widget
test (the live try failed because the app forgot a notification once its popup expired; fixed, not re-run live — test
windows were opening over a game on the active workspace, so live window tests stopped). Login autostart was not
tested by logging in. If the GTK app’s reminders are also on, both apps notify. (Phones: see Update 4.)

## Update 2: Today and the obligatory prayers (2026-11-15, evening)

Asked for: “add the Today page and obligatory prayers too”. Ported from the GTK app’s `badi.py`, `today.py`,
`counter.py`, `location.py`, the Today calendar in `contents.py` and `obligatory()`/`directions()`/`passage_of_the_day()`
in `library.py`, all read-only. Desktop layout only; the phone layout does not have them yet.

- **Today** (Ctrl+T, Home → Open Today, ⋮ → Today): the Badí‘ date (it changes at local sunset), Gregorian date and
  month; sunrise/solar noon/sunset for the saved place (or the clock hours entered); the chosen obligatory prayer with
  “Open now, until …” / “Opens at …” / “Its time has ended …”, a “Said …” toggle, guidance links (Q&A 82/83, ¶10) and
  the Long prayer’s period line and the 1990 letter; the counter card; the next Feast and Holy Day with their prayers or
  Days of Remembrance readings, and Ayyám-i-Há when near; the Fast (day n of 19, fasting hours, “Fasted today”, prayers,
  ¶16) during or near ‘Alá’; the passage of the day. Redrawn every 30 s. The sidebar shows the Today calendar (Upcoming,
  This year) with a search; dates with readings or prayers open them.
- **Home** gains the GTK app’s three cards: Today’s date, the obligatory prayer (Said / Open), the passage of the day.
- **Obligatory prayers**: the first row of Prayers opens its own section (Back → Prayers): “Alláh-u-Abhá counter”, “The
  three prayers” and the Kitáb-i-Aqdas guidance (¶6, 8, 10, 12, 13, 14 and the notes and Q&A they link), groups open
  as in GTK. Reading an obligatory prayer shows its “Said today / this morning / at noon / this evening” toggle in the
  footer (the same mark as on Today); its directions are in italics.
- **Alláh-u-Abhá counter** (Ctrl+Shift+A): count, Complete at the target, target 95/19/9/custom (remembered), Undo,
  Reset, Back, ¶18 with its citation; Space/Enter count (a held key counts once), Backspace, Ctrl+0, Esc.
- **Location & obligatory prayer** (⋮, and the cards’ buttons): city search over the bundled GeoNames list, or
  latitude/longitude/time zone; clock hours in place of the sun; Short/Medium/Long/Don’t track; the Long prayer’s
  24 hours (sunset/noon/midnight/rolling); keep or clear the private Said/Fasted record.
- Settings use the GTK app’s keys and meanings (`location`, `clock_hours`, `prayer`, `long_period`, `keep_records`,
  `records`, `counter_target`). The GTK import still copies only highlights and saved passages.
- Data: `assets/calendar/badi-dates.json` and `cities.json` (copied from the GTK app; notices added to DATA-NOTICE.md);
  each library now carries the passage-of-the-day order and the Obligatory prayers groups, precomputed by
  `scripts/convert_library.py` with the GTK functions; passages are otherwise unchanged (checked). New dependency:
  `timezone` (bundled IANA data; it pulls in `http`, which nothing in `lib/` uses).

Verified: `flutter analyze` clean; `flutter test` **44 passed**. New: `test/calendar_test.dart` (5) compares the Dart
port with answers generated by the GTK code (`scripts/calendar_fixtures.py`): Badí‘ dates, upcoming events, the Fast,
Ayyám-i-Há and months for 12 dates (2014–2066); sun times to the second for Haifa, Chicago, Tromsø (polar day/night),
Kiritimati and clock hours; the observed day, 450 Short/Medium windows and 135 Long periods; the passage of the day for 9
dates. `test/today_test.dart` (3): Home and Today cards, Said from Today and from the prayer, the Obligatory prayers
section and Back, the counter (keys, target), city search → Haifa, prayer choice → Medium on Today. Linux release
build checked by screenshot (Home cards, Today with Chicago, the Today calendar, the counter counting three Space
presses, the Medium prayer with italic directions and “Said this morning”). APK rebuilt: still no INTERNET permission.

Not done / differs: no reminders or background notifications (GTK’s Reminders… buttons are left out); daylight-saving
changes after 2037 are not in the Dart time-zone data, so clock times for 2038–2065 can be an hour off in DST zones
(Python’s are not); `--open` of an obligatory prayer opens it in its prayer category, as GTK’s search does; not checked
by hand with a mouse (clicking the cards’ buttons) beyond the widget tests.

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
| Tests | ✅ 44 tests, all passing (32 in v0 + 4 desktop + 8 Today/calendar) |

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
- No collections, compare, packaging or CI. (Continue reading, Today/calendar, the counter, reminders and the Omarchy
  theme follow were added later; see the updates above.)
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
