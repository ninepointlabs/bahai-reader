# Bahá’í Reader — Flutter experiment

> **This is an experiment, not a replacement.** It is a trial Flutter port of Bahá’í Reader, made to see how a
> cross-platform version turns out. The real app is the native GTK Bahá’í Reader:
>
> - Source: https://github.com/ninepointlabs/bahai-reader
> - Site: https://bahaireader.org

Offline-first: the library is bundled, and the app makes **no network calls**, has no analytics and no telemetry.

## What it does (v0)

- **Library**: writings grouped by book, prayers grouped by category.
- **Reading**: passage by passage, with a contents list (beside the text on wide windows, in a drawer on narrow ones),
  Kitáb-i-Aqdas cross-references, and copy-with-citation.
- **Languages**: switch among the libraries bundled offline (English, plus Amharic in this build).
- **Search**: the whole current-language library, ignoring case, accents, apostrophes and hyphens
  (“Bahaullah” finds “Bahá’u’lláh”).
- **Highlights, notes and saved passages**, stored the same way as the GTK app (passage id + character offsets + the
  quoted words), and following passages across languages by their `match`.
- **Light, Dark and Sepia** palettes from the GTK app; by default it follows the live Omarchy theme where there is one,
  else the system's light or dark.
- **Desktop layout like the GTK app** (Linux, Windows, macOS): a sidebar with Home, Prayers, Writings and Saved and the
  open section's contents; a header bar with Search, Aa, Copy, Save and ⋮; the reading pane with the book and part, the
  heading, Previous / progress / Next; a Ctrl+K search dialog with This book / Everything; Highlights & notes under Saved;
  the GTK app's keyboard shortcuts. Phones and tablets keep the touch layout.
- **Today and the obligatory prayers** (desktop layout): the Badí‘ date (changing at sunset), sun times for a saved
  city, the chosen obligatory prayer's times with a private "Said today", the next Feast and Holy Day, the Fast, the
  passage of the day and the Today calendar; an Obligatory prayers section under Prayers with the Kitáb-i-Aqdas guidance;
  the Alláh-u-Abhá counter; Location & reminders (city search, clock times, Long prayer period). Ported from the
  GTK app's `badi.py` and `today.py` and checked against them.
- **On phones** (Android): the app opens on a Today tab with the same cards; Prayers starts with Obligatory prayers (the
  counter, the three prayers, their guidance); ⋮ → Location & reminders; "Said today" in the prayer. Reminders are set as
  alarms a week ahead and arrive with the app closed (and after a restart of the phone); "Said today" on the notification
  marks it without opening the app.
- **Reminders** (Linux): desktop notifications when the obligatory prayer's time opens and before it closes (with
  "Said today" and "Open" on the notification), a nudge before the Long prayer's period resets, Feasts, Holy Days, the
  Fast's approach and each fasting day's sunrise and sunset. All off until turned on in Location & reminders. Optionally
  they keep running with the window closed: closing hides the window and a login entry starts the app hidden
  (`--background`). Worked out on this computer and sent to the desktop's own notification service; nothing leaves it.

See [STATUS.md](STATUS.md) for what works, what doesn’t, and how it was tested.

## Run

Requires Flutter 3.47 (Dart 3.13).

```sh
flutter pub get
flutter run -d linux                    # or: flutter build linux --release
./build/linux/x64/release/bundle/bahai_reader [--open hidden:2]
flutter build apk --release             # Android
flutter test
```

Windows, macOS and iOS project scaffolding is included; those targets must be built on their own platforms.

On Linux only one copy runs at a time (a second launch brings the window forward), so reminders are never sent twice.
`BAHAI_READER_SEPARATE=1` runs a separate copy, e.g. with its own `XDG_CONFIG_HOME` for testing.

## Layout

The app is split so pieces can be changed or added independently. `lib/core/` has no UI code except `app/`;
each feature under `lib/features/` is a self-contained screen that talks to `AppState`.

```
lib/
  main.dart                    entry point (--open <passage id>)
  core/
    app/        app_state.dart  shared state + AppScope; theme.dart (GTK palettes, Omarchy theme follow)
    library/    passage.dart, library.dart (works, grouping), library_repository.dart (assets), citations.dart,
                labels.dart (headings, subtitles, progress: port of GTK labels.py)
    calendar/   badi.dart (Badí‘ calendar, sun, prayer windows: port of GTK badi.py), today.dart (Today's cards as data),
                reminders.dart (which reminders are due: port of GTK badi.py's reminders),
                cities.dart (city search), zones.dart (bundled time-zone database)
    platform/   notifier.dart (Linux: notifications over the session bus; Android: alarms set a week ahead, see
                android/.../Reminders.kt), window_control.dart (hide/present the Linux window, the login entry)
    marks/      highlight.dart  anchoring, overlap, notes, cross-language follow (port of GTK marks.py)
    search/     fold.dart, search_index.dart (port of GTK search.py)
    settings/   settings_store.dart (own file; read-only GTK import)
  features/
    desktop/    the GTK-style desktop window: shell, sidebar, home/library, reading view, search dialog,
                Highlights & notes (shell_model.dart holds where the window is)
    today/      shared by both layouts: Today's cards, the counter, Location & reminders, the Said button;
                phone_today.dart opens them as pages on phones
    library/  reader/  search/  marks/    the touch layout (phones, tablets)
    settings/  about/                     shared by both
scripts/convert_library.py     rebuilds assets/library/ and assets/calendar/ from the GTK app's data/
scripts/calendar_fixtures.py   expected answers from the GTK app's badi.py, for test/calendar_test.dart
scripts/reminder_fixtures.py   expected reminders from the GTK app's badi.py, for test/reminders_test.dart
assets/library/                converted library (checked in), manifest, search fold table
test/                          marks, conversion, search, settings, app/widget tests
```

To add a feature: put its logic in `lib/core/<area>/` (pure Dart, unit-tested), its screen in
`lib/features/<feature>/`, and any shared state or persisted setting in `AppState` / `Settings`.

## Content

`assets/library/` is generated by `scripts/convert_library.py`, which runs the GTK app’s own loader
(`load_library()` in `bahai_reader/library.py`) read-only, so passage ids, `match` keys, bahai.org replacements and
citations are identical. `--without-bahai-org` rebuilds English from BahaiPrayers.net text only.

## Licence and attribution

The code is under the MIT License ([LICENSE](LICENSE)). **The texts and translations are not**: see
[DATA-NOTICE.md](DATA-NOTICE.md). Texts come from BahaiPrayers.net (https://bahaiprayers.net/Developer) and, in English,
from the Bahá’í Reference Library: Copyright © Bahá’í International Community, bahai.org, used under
https://www.bahai.org/legal. No ownership of the writings is claimed. This app is free and is not sold.
