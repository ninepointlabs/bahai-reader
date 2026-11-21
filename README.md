# Bahá’í Reader

Offline Bahá’í prayers and writings for **Linux, Android and Windows**. English is bundled; other languages download
only when you ask, and nothing else ever uses the network. No accounts, no analytics, no telemetry.

[Website](https://bahaireader.org/) · [Releases](https://github.com/ninepointlabs/bahai-reader/releases) ·
[Issues](https://github.com/ninepointlabs/bahai-reader/issues)

Version 1.0 is a Flutter rebuild of the GTK app (0.2.3 and earlier, kept on the `gtk-legacy` branch and tagged
`gtk-final`). On Linux, the first start brings over highlights, notes, saved passages, collections, reading places
and settings from the GTK app, and reads the languages it downloaded; the GTK app's files are only read, never changed.

## Install

### Linux

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli). `add` only starts tracking the
repository; `install` installs the package for your distribution and asks for your password:

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
autonomix-cli install bahai-reader
```

Later, `autonomix-cli update` installs new releases.

Or download from [GitHub Releases](https://github.com/ninepointlabs/bahai-reader/releases) and install from your
download folder:

```sh
# Debian 12+ / Ubuntu 24.04+
sudo apt install ./bahai-reader_1.0.1-1_amd64.deb
# Fedora 43+ / compatible modern RPM systems
sudo dnf install ./bahai-reader-1.0.1-1.x86_64.rpm
# Arch / Omarchy
sudo pacman -U ./bahai-reader-1.0.1-1-x86_64.pkg.tar.zst
```

**AppImage** (x86_64, uses the system's GTK 3):

```sh
chmod +x bahai-reader-1.0.1-x86_64.AppImage
./bahai-reader-1.0.1-x86_64.AppImage
./bahai-reader-1.0.1-x86_64.AppImage --install-desktop-entry   # add it to the application menu
```

[Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) or
[AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher) can also add it and update it in place.

**Flatpak bundle** (any distribution with Flatpak; a direct download, not a Flathub listing):

```sh
flatpak install --user ./bahai-reader-1.0.1-x86_64.flatpak
flatpak run org.bahai.Reader
```

The first install also downloads the GNOME 51 runtime from Flathub. Inside the Flatpak, reminders run only while the
app is open.

### Android

Download `bahai-reader-1.0.1.apk` from the release on your phone and open it. Android asks you to allow installs from
your browser or file manager the first time. Later versions install over it and keep your data.

### Windows

Run `bahai-reader-1.0.1-windows-x64-setup.exe` (installs for your user, no administrator rights), or unzip
`bahai-reader-1.0.1-windows-x64.zip` and run `bahai-reader.exe`. They are not code-signed yet, so SmartScreen may
warn the first time: choose **More info → Run anyway**. Reminders are not sent on Windows yet.

Checksums for every download are in `SHA256SUMS`.

## What it does

- **Library**: writings grouped by book, prayers grouped by category.
- **Reading**: passage by passage, with a contents list (beside the text on wide windows, in a drawer on narrow ones),
  Kitáb-i-Aqdas cross-references, and copy-with-citation.
- **Languages**: English bundled; other languages downloaded from BahaiPrayers.net when you ask, in Languages & offline
  libraries, and read offline after that.
- **Search**: the whole current-language library, ignoring case, accents, apostrophes and hyphens
  (“Bahaullah” finds “Bahá’u’lláh”).
- **Highlights, notes and saved passages**, anchored the same way as the GTK app (passage id + character offsets + the
  quoted words), and following passages across languages by their `match`. They are kept, with collections, reading
  places and Said/Fasted records, in `userdata.sqlite` beside `settings.json`: one record per mark with a permanent id,
  change times and deletion markers, so they can be synced between devices. Settings → *Back up or move your notes*
  exports them all to one file and imports-and-merges such a file from another device (the version changed last wins,
  record by record; nothing goes over the network). The first start
  of a version with this store moves them out of `settings.json` and keeps a copy of the old file as
  `settings.json.pre-userdata-<date>`; `settings.json` keeps its copies as they were at the move, so an older version
  still finds them.
- **Study**: import PDFs of your own (such as your copies of Ruhi Institute books; the app includes none) and study them:
  highlights in five colours with notes, bookmarks, your answers typed on the workbook's blank lines (found in the page
  image, as in Dogear) or in a box anywhere on the page, notes about the book, search in the book, and the place you
  stopped. Each time through a book is a *run* ("1st time, Nov 2026") that owns its marks. Export a run to Markdown for
  Obsidian. Imported files are copied into the app on this device and never uploaded. Not affiliated with or endorsed
  by the Ruhi Institute.
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

See [PARITY.md](PARITY.md) for how each GTK feature maps to this app, and [STATUS.md](STATUS.md) for how it was tested.

## Build

Requires Flutter 3.47 (Dart 3.13).

```sh
flutter pub get
flutter run -d linux                    # or: flutter build linux --release
./build/linux/x64/release/bundle/bahai-reader [--open hidden:2]
flutter build apk --release             # Android
flutter test
```

`flutter build windows --release` must run on Windows; macOS and iOS scaffolding is included but not built or tested.

**Packages and releases.** `.github/workflows/release.yml` tests the code, builds the Linux bundle on Ubuntu 22.04
(so it runs on Debian 12), the .deb/.rpm/pacman packages (`scripts/build-packages.sh`, nFPM), the AppImage
(`scripts/build-appimage.sh`), the Flatpak bundle (`scripts/build-flatpak.sh`), the signed APK and the Windows zip and
installer (`packaging/windows/bahai-reader.iss`), and starts each one to check it runs; the packages are installed and
started on Debian 12, Ubuntu 24.04, Fedora 43 and Arch. A `vX.Y.Z` tag publishes a release once every check passes.
Before tagging, update `version:` in `pubspec.yaml` and `appVersion` in `lib/core/app/about.dart`, add a `<release>`
to `packaging/org.bahai.Reader.metainfo.xml`, and update `RELEASE-NOTES.md` and the website's download links.

The APK is signed with the release key from the `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD` secrets
(locally, `android/key.properties`, never committed). Keep a backup of the key: an APK signed with another key cannot
update an installed copy.

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
    userdata/   userdata_store.dart (marks and personal choices in SQLite, sync-ready records, the move from
                settings.json; schema 2 adds Study's tables), ids.dart (UUIDv7, UUIDv5, hybrid logical clock)
    study/      study_store.dart (books, runs and their marks), study_controller.dart (the open book), rules.dart
                (answer lines found in a page image: Dogear's rules.py), page_data.dart (a PDF page's text and lines),
                importer.dart, export.dart (Markdown)
  features/
    desktop/    the GTK-style desktop window: shell, sidebar, home/library, reading view, search dialog,
                Highlights & notes (shell_model.dart holds where the window is)
    today/      shared by both layouts: Today's cards, the counter, Location & reminders, the Said button;
                phone_today.dart opens them as pages on phones
    library/  reader/  search/  marks/    the touch layout (phones, tablets)
    settings/  about/                     shared by both
    study/      Study's library, PDF reader (pdfrx), panels, import/export; used by both layouts
packaging/                     desktop file, icons, AppStream metainfo, nFPM, AppRun, Flatpak manifest, Windows installer
scripts/build-*.sh             Linux packages, AppImage and Flatpak from the release bundle
scripts/screenshots/           the website's desktop screenshots, rendered off screen (see the file's header)
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
citations are identical. The GTK source is on the `gtk-legacy` branch: check it out into a separate folder
(`git worktree add ../bahai-reader-gtk gtk-legacy`) and pass it with `--gtk ../bahai-reader-gtk`.
`--without-bahai-org` rebuilds English from BahaiPrayers.net text only.

## Licence and attribution

The code is under the MIT License ([LICENSE](LICENSE)). **The texts and translations are not**: see
[DATA-NOTICE.md](DATA-NOTICE.md). Texts come from BahaiPrayers.net (https://bahaiprayers.net/Developer) and, in English,
from the Bahá’í Reference Library: Copyright © Bahá’í International Community, bahai.org, used under
https://www.bahai.org/legal. No ownership of the writings is claimed. This app is free and is not sold.
