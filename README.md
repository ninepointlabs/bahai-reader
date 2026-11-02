# Bahá’í Reader

A standalone GTK 4 Linux app for quiet reading. Follows Omarchy colors live, including custom themes. No shell plugin or Omarchy dependency.

## Install packages

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli). It takes two steps: `add` only starts tracking the repository, and `install` then installs the package for your distribution. The install step asks for your password.

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
autonomix-cli install bahai-reader
```

Later, `autonomix-cli update` installs new releases, again with a password prompt.

Or download from [GitHub Releases](https://github.com/ninepointlabs/bahai-reader/releases). From your download folder (`sudo` asks for your password):

```sh
# Debian 12+ / Ubuntu 24.04+
sudo apt install ./bahai-reader_0.1.8-1_all.deb
# Fedora 43+ / compatible modern RPM systems
sudo dnf install ./bahai-reader-0.1.8-1.noarch.rpm
# Arch / Omarchy
sudo pacman -U ./bahai-reader-0.1.8-1-any.pkg.tar.zst
```

### Other Linux distributions

Two portable x86_64 downloads are attached to each release as well.

**AppImage.** A small launcher that runs on your system’s Python 3.11+, PyGObject and GTK 4.8+ (Debian 12+, Ubuntu 24.04+, Fedora 43+, Arch). If they are missing or too old, it says so and points to the Flatpak instead.

```sh
chmod +x bahai-reader-0.1.8-x86_64.AppImage
./bahai-reader-0.1.8-x86_64.AppImage
```

To add it to your application menu and dock, use [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) or [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher). Both can also update it in place. Or let the AppImage add its own menu entry and icons under `~/.local/share`, and remove them again later:

```sh
./bahai-reader-0.1.8-x86_64.AppImage --install-desktop-entry
./bahai-reader-0.1.8-x86_64.AppImage --remove-desktop-entry
```

`--check-host` prints the Python and GTK versions it found. If the AppImage does not start because FUSE is unavailable, run it with `--appimage-extract-and-run`, or install FUSE (`fuse3` on most distributions, `fuse` on older ones).

**Flatpak bundle.** Brings its own Python and GTK through the GNOME runtime, so it works on any distribution with Flatpak, including ones whose GTK is too old for the AppImage. It is a self-hosted download, not a Flathub listing. Install the file for your user:

```sh
flatpak install --user ./bahai-reader-0.1.8-x86_64.flatpak
flatpak run org.bahai.Reader
```

The first install also downloads the GNOME 51 runtime (`org.gnome.Platform//51`, a few hundred MB, shared with other GNOME apps) from Flathub. If Flatpak cannot find it, add the Flathub remote and try again:

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

To update, install the newer `.flatpak` file the same way. The Flatpak keeps its settings and downloaded languages under `~/.var/app/org.bahai.Reader`. It follows the Omarchy theme palette, but on Omarchy the Arch package integrates more closely.

Open **Bahá’í Reader** in the application menu or run `bahai-reader`. Packages are architecture-independent, requiring Python 3.11+ and GTK 4.8+. Package managers resolve dependencies. These are downloadable packages, not an APT/DNF repository or AUR submission. Install newer packages to update; user libraries and settings remain in place.

[Website](https://bahaireader.org/) · [Issues](https://github.com/ninepointlabs/bahai-reader/issues)

## Run

```sh
/usr/bin/python3 reader.py
```

`bahai-reader --help` and `--version` print and exit; `--background` runs reminders with no window (see Features). If the settings file is damaged, the app starts with defaults, keeps the damaged file as `settings.json.bad` (or `settings.json.bad.1` and so on, never replacing an earlier one), and says so. Damaged collection entries are dropped, but every passage filed in one stays saved.

Requires Python 3.11+, GTK 4, and PyGObject. Arch/Omarchy packages: `python-gobject gtk4`. Debian 12+/Ubuntu 24.04+: `python3-gi gir1.2-gtk-4.0`. Fedora: `python3-gobject gtk4`.

## Features

- Separate Prayers, Hidden Words (Arabic/Persian divisions), and Writings sections.
- **Obligatory prayers** section: the short, medium and long obligatory prayers in one place, with their directions (when to say them, the actions, and the notes after them) in italics so the words of the prayer stand out, followed by the Kitáb-i-Aqdas paragraphs on obligatory prayer (¶6, ¶8, ¶10, ¶12, ¶13 and ¶14) and the notes and Questions and Answers that the bundled Aqdas links to them. All from the bundled texts; prayers are found by their BahaiPrayers.net category, which other languages may not use.
- All ten English collections bundled for offline reading, sourced directly from the API.
- Topic filtering, full-text section search, saved passages, last passage restoration.
- **Copy** (Ctrl+Shift+C) puts the passage on the clipboard with its citation: author, book and paragraph or Hidden Word number, or the prayer’s author and category. With words selected in the passage, only the selection is copied, still with the citation.
- Search ignores case, accents, apostrophes and hyphens: `Bahaullah`, `Baha'u'llah` and `abdul-baha` find Bahá’u’lláh and ‘Abdu’l‑Bahá. Searching narrows the contents list without changing the passage you are reading.
- **Collections** for saved passages, like a personal prayerbook. Saved passages start under *Unsorted*; the **Collection** list under a saved passage moves it, and **Manage collections…** (shown in Saved passages) creates, renames and deletes them. Deleting a collection keeps its passages saved, under Unsorted. Saved passages are listed by collection.
- **Today** (the first entry in the sidebar, the header’s Today button, or Ctrl+T; new installs open here, and an existing reading position is kept) gathers the day in one quiet column: the Badí‘ date with the Gregorian date and the month’s name and meaning, the sun’s times for your location, the next Feast and Holy Day with whether work is suspended and links to their readings in Days of Remembrance and to the prayers for Naw-Rúz, Ayyám-i-Há and the Fast, and the passage of the day. With a location set the date changes at local sunset; without one it follows the calendar day. In the sidebar, Today lists the next 12 months of Holy Days and Feasts and this year’s months with their Gregorian dates, and search narrows them.
- **Obligatory prayer times**: choose Short, Medium, Long or Don’t track in ⋮ → Location & reminders. Today then shows whether the prayer’s time is open and when it opens or closes, with links to the prayer and its guidance. The times come from the bundled texts: the short prayer from noon till sunset; the medium prayer from sunrise till noon, noon till sunset, and sunset till two hours after (Question and Answer 83), the morning prayer also as early as dawn (Note 5); the long prayer once in twenty-four hours, at any time (Question and Answer 82). Which twenty-four hours is your choice, because the texts do not say and the Universal House of Justice has made no ruling (letter of 17 December 1990): sunset to sunset by default, noon to noon, midnight to midnight, or 24 hours since last said. Without a location, 6:00, 12:00 and 18:00 stand in for the sun, and the card says so. Where the sun does not rise or set that day, no times are shown and the card points to ¶10 and to your National Spiritual Assembly, unless you have set clock times.
- **Clock times** (⋮ → Location & reminders): enter the sunrise, noon and sunset hours your National Spiritual Assembly uses. They then replace the sun for prayer times, the Fast, reminders and when the Badí‘ date changes, and also apply where there is a real sunrise and sunset. The app has no hours of its own.
- **Said today**: a toggle on the Today card and beside the prayer while you read it, one state in both places. The medium prayer has one for each of its three times. The long prayer’s resets when its chosen period does. The record stays on this computer, can be turned off, and **Clear my records** removes it. There are no streaks, scores or “you missed” messages.
- **Reminders** (⋮ → Location & reminders; all off until you turn them on): when the chosen prayer’s time opens, and about 30 minutes before it closes if not yet said. The long prayer has one separate, opt-in nudge instead, sent only if it isn’t marked, 2 hours before its period resets unless you change that. Notifications have **Said today**, which marks it without opening the window, and **Open**. They check the wall clock every 30 seconds rather than waiting on a timer, so restarts, suspend and changes of the clock or time zone don’t lose them; after a long sleep, stale reminders are skipped and at most one per prayer is sent. Feast, Holy Day and Fast reminders each have their own switch: a Feast on the afternoon of the day it begins at sunset; a Holy Day the day before and on the day; the Fast 5, 3 and 1 days before, and if you like before sunrise and at sunset each day of the Fast. Without a location they use clock times. While the app is open no further setup is needed.
- **Keep reminders running when the window is closed** (opt-in): adds `~/.config/autostart/org.bahai.Reader-reminders.desktop`, which runs `bahai-reader --background` at login. **A quiet background process then runs with no window and no tray icon**, and closing the window keeps it alive; launching the app opens the window in that process. To stop it, turn the option off in the same window and close the app. The entry is removed. In the Flatpak the app asks the XDG Background portal instead; where the desktop doesn’t offer that portal (Hyprland’s may not), the window says so and reminders run only while the app is open.
- **The Fast**: during the month of ‘Alá’, Today shows “Day 7 of 19”, the day’s sunrise and sunset, prayers for the Fast and an optional private **Fasted today** check, kept and cleared like Said today. Outside it the card appears only within 30 days: “The Fast begins at sunrise on 2 March”.
- **Alláh-u-Abhá counter** (from Today, the top of the Obligatory prayers section, or Ctrl+Shift+A): a large count, a target of 95, 19, 9 or a number you choose, and Kitáb-i-Aqdas ¶18 beneath it. Space, Enter or a click counts one; Backspace undoes one; Ctrl+0 or Reset starts over; Esc goes back to where you were. Reaching the target shows “95 of 95”, with no sound or animation. The count is not saved. Screen readers hear it at every nineteenth and at the target.
- **Badí‘ dates** come from the Universal House of Justice: the table of dates for 172 to 221 B.E. and the message of 10 July 2014. After 221 B.E. (March 2065), and before 172 B.E., the app does not guess: it says “Dates for this year have not been published yet”.
- **The passage of the day** is the same passage all day, a different one each day, until every passage has had its day. **Random** (Ctrl+R) opens a random passage. Both pick from the prayers, the Hidden Words, Gleanings and Prayers and Meditations, up to 500 words, in the current language, and work offline.
- Installed font selection, text size, line spacing, page margins.
- Omarchy theme tracking every second; light, dark, and sepia overrides.
- Manual background library refresh, with offline fallback on failure.
- **Location & reminders** (⋮ menu): type a city (found offline, in a bundled GeoNames list, without regard to accents) or enter latitude, longitude and time zone. The window shows the place, its time zone and today’s sunrise, solar noon and sunset, worked out on this computer with the public-domain NOAA calculation; where the sun does not set or rise that day it says so. The location is never detected and never sent anywhere; only the place’s name, its coordinates rounded to 2 decimals and its time zone are saved, and **Clear location** forgets them.
- The header’s **Aa** holds how the text reads (appearance, font, size, spacing, margins, Side by side). The **⋮** menu holds the rest: Location & reminders, Languages & offline libraries, Keyboard shortcuts and About.
- **Side by side**: Aa → Side by side shows the passage beside the same passage in English or any downloaded language. Passages are paired by their numbering (Hidden Word, Gleanings and Prayers and Meditations number, Tablet and paragraph, Íqán part and paragraph, Aqdas paragraph, note or question, SAQ chapter), as BahaiPrayers.net's Matrix comparison feeds pair them, so it works offline and makes no network request. Prayers, Days of Remembrance and Riḍván messages have no shared numbering across languages and are not paired. A translation that numbers its paragraphs differently is paired the same way the provider pairs it.

Current Omarchy theme location: `$XDG_STATE_HOME/omarchy/current/theme/colors.toml` (defaults to `~/.local/state`). Legacy `~/.config/omarchy/current/theme/colors.toml` is also supported. App settings live in `$XDG_CONFIG_HOME/bahai-reader`; downloaded language libraries in `$XDG_DATA_HOME/bahai-reader/libraries` (default `~/.local/share/bahai-reader/libraries`). No desktop configuration is modified.

## Desktop launcher

Run `./install.sh` to register the app in the current user's application menu. It points to this checkout; keep the repository in place. Remove `~/.local/share/applications/org.bahai.Reader.desktop` to uninstall the launcher.

## Content and scope

Texts are provided by [BahaiPrayers.net](https://bahaiprayers.net/), whose [developer documentation](https://bahaiprayers.net/Developer) explicitly permits use of its feeds in apps. Texts retain their source attribution; no ownership of the writings is claimed. Bundled snapshots downloaded September 13, 2026. HTML is converted to plain paragraphs for the native reader; text is not rewritten.

English ships with Gleanings, Prayers and Meditations, Tablets of Bahá’u’lláh, the Kitáb-i-Íqán, and the Epistle to the Son of the Wolf in Writings. BahaiPrayers.net files the Epistle with the prayers; the reader lists it under Writings. Other content languages can be downloaded where the API offers them; the interface remains English. Native Debian, RPM, and Arch packages are provided. The RPM uses Fedora dependency names; compatibility with every RPM-based distribution is not claimed.

## Omarchy integration

Square, undecorated window lets Hyprland supply themed borders. Interface uses the fontconfig monospace family (Omarchy's configured font); the reading font is independent. When available, `omarchy theme color --all` resolves semantic and legacy palette keys. Active theme changes are detected without installing a hook or editing packaged Omarchy files. See [Keyboard shortcuts](#keyboard-shortcuts).

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Ctrl+F | Show the contents panel and search this section |
| Alt+Right or Ctrl+Page Down | Next passage |
| Alt+Left or Ctrl+Page Up | Previous passage |
| Ctrl+D | Save or unsave the current passage |
| Ctrl+Shift+C | Copy the passage (or the selected words) with its citation |
| F1 | About Bahá’í Reader |
| Ctrl+Q | Quit (also from the small windows). While reminders keep running, it closes the window instead |
| Ctrl+T | Today (previously the passage of the day, which is now a card on Today) |
| Ctrl+R | Random passage |
| Ctrl+Shift+A | Alláh-u-Abhá counter |
| Space or Enter | In the counter: count one |
| Backspace | In the counter: undo one |
| Ctrl+0 | In the counter: start over |
| Escape | Show the contents panel again if it is hidden; closes the small windows; leaves the counter |
| Tab / Shift+Tab | Move between search, the contents list and the reading pane or Today’s cards, top to bottom. The contents list is a single stop; use the arrow keys and Enter inside it |
| Page Up / Page Down | Scroll the passage |

The collapsible table of contents follows API prayer categories, Arabic/Persian Hidden Words divisions, and book → tablet/part → passage nesting for writings. Expansion choices persist; search temporarily expands matching branches. Previous/Next stays within the selected category or book division.

## About

Open **⋮ → About Bahá’í Reader** or press F1. It shows the version, Nine Point Labs, the creation date, the MIT license (readable in full, with the text attribution from DATA-NOTICE.md), the support address [help@ninepointlabs.com](mailto:help@ninepointlabs.com) with Email and Copy buttons (Email prefills the app, GTK, PyGObject and Python versions), the privacy statement, and the toolkit versions.

## Offline languages

Open **⋮ → Languages & offline libraries…**. English is the first-run default and includes all ten supported collections locally. No network request is made at startup or when switching to an already downloaded language.

The bundled API catalog lists 112 prayer languages. Select a language to see its available collections, then choose **Download & use**. The app downloads all supported collections offered in that language and remembers your selection. Unavailable translations are not replaced with English. Use **Check available languages** to update the catalog or **Update downloaded content** to refresh a language explicitly.

Downloads are stored as permanent user data, not disposable cache. A complete language pack is validated and published atomically; a failed download leaves existing content untouched. Older English cache files remain readable for compatibility. Downloading requires a connection; reading, search, categories, saved passages, and fonts work offline. Right-to-left content uses the API’s direction metadata. Font coverage depends on installed system fonts; the interface and book labels remain English. Word counts are token estimates for languages without space-delimited words.

Run offline storage tests with `/usr/bin/python3 -m unittest discover -s tests`.

## Complete structured collection support

All ten collections documented by BahaiPrayers.net are supported. English now bundles 2,616 readable records, including 190 Aqdas paragraphs, 107 Questions and Answers, 194 notes, 84 Some Answered Questions chapters, 45 Days of Remembrance selections, and 73 Riḍván messages. Aqdas references open offline through **Related passages**. Other new contents are grouped by part, holy day, and decade/year respectively.

Existing English packs automatically gain newly bundled books. For previously downloaded non-English libraries, open **Languages & offline libraries → Update downloaded content** to add newly supported translations. The dialog identifies collections still needing an update. The language catalog is merged with bundled additions when upgrading.

The provider also has a separate online AI-branded document search. It returns ranked documents and highlighted snippets, with language and optional author filters; its UI documents phrase, Boolean, and proximity search. This online search is not integrated. The app’s existing search remains local and works offline.

## Build and release

```sh
scripts/get-nfpm.sh /tmp/bahai-nfpm
NFPM=/tmp/bahai-nfpm/nfpm scripts/build-packages.sh
xvfb-run -a /usr/bin/python3 tests/smoke_ui.py
```

The pinned nFPM builder creates all three packages and SHA256SUMS in `dist/`. GitHub Actions tests the source and package installation/GTK startup in Debian 12, Fedora 43, and Arch containers. Tagged releases publish only after checks pass. Update VERSION, RELEASE-NOTES.md, and the website's versioned download links before tagging `vX.Y.Z`.

The static website is in `docs/` and deploys through GitHub Pages. Application code and original artwork are MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md.
