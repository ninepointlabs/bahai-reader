# Bahá’í Reader

A standalone GTK 4 Linux app for quiet reading. Follows Omarchy colors live, including custom themes. No shell plugin or Omarchy dependency.

## Install packages

Download from [GitHub Releases](https://github.com/ninepointlabs/bahai-reader/releases). From your download folder:

```sh
# Debian 12+ / Ubuntu 24.04+
sudo apt install ./bahai-reader_0.1.0-1_all.deb
# Fedora 43+ / compatible modern RPM systems
sudo dnf install ./bahai-reader-0.1.0-1.noarch.rpm
# Arch / Omarchy
sudo pacman -U ./bahai-reader-0.1.0-1-any.pkg.tar.zst
```

Open **Bahá’í Reader** in the application menu or run `bahai-reader`. Packages are architecture-independent, requiring Python 3.11+ and GTK 4.8+. Package managers resolve dependencies. These are downloadable packages, not an APT/DNF repository or AUR submission. Install newer packages to update; user libraries and settings remain in place.

[Website](https://ninepointlabs.github.io/bahai-reader/) · [Issues](https://github.com/ninepointlabs/bahai-reader/issues)

## Run

```sh
/usr/bin/python3 reader.py
```

Requires Python 3.11+, GTK 4, and PyGObject. Arch/Omarchy packages: `python-gobject gtk4`. Debian 12+/Ubuntu 24.04+: `python3-gi gir1.2-gtk-4.0`. Fedora: `python3-gobject gtk4`.

## Features

- Separate Prayers, Hidden Words (Arabic/Persian divisions), and Writings sections.
- All ten English collections bundled for offline reading, sourced directly from the API.
- Topic filtering, full-text section search, saved passages, last passage restoration.
- Installed font selection, text size, line spacing, page margins.
- Omarchy theme tracking every second; light, dark, and sepia overrides.
- Manual background library refresh, with offline fallback on failure.

Current Omarchy theme location: `$XDG_STATE_HOME/omarchy/current/theme/colors.toml` (defaults to `~/.local/state`). Legacy `~/.config/omarchy/current/theme/colors.toml` is also supported. App settings live in `$XDG_CONFIG_HOME/bahai-reader`; downloaded language libraries in `$XDG_DATA_HOME/bahai-reader/libraries` (default `~/.local/share/bahai-reader/libraries`). No desktop configuration is modified.

## Desktop launcher

Run `./install.sh` to register the app in the current user's application menu. It points to this checkout; keep the repository in place. Remove `~/.local/share/applications/org.bahai.Reader.desktop` to uninstall the launcher.

## Content and scope

Texts are provided by [BahaiPrayers.net](https://bahaiprayers.net/), whose [developer documentation](https://bahaiprayers.net/Developer) explicitly permits use of its feeds in apps. Texts retain their source attribution; no ownership of the writings is claimed. Bundled snapshots downloaded September 13, 2026. HTML is converted to plain paragraphs for the native reader; text is not rewritten.

English ships with Gleanings, Prayers and Meditations, Tablets of Bahá’u’lláh, and the Kitáb-i-Íqán in Writings. Other content languages can be downloaded where the API offers them; the interface remains English. Native Debian, RPM, and Arch packages are provided. The RPM uses Fedora dependency names; compatibility with every RPM-based distribution is not claimed.

## Omarchy integration

Square, undecorated window lets Hyprland supply themed borders. Interface uses the fontconfig monospace family (Omarchy's configured font); the reading font is independent. When available, `omarchy theme color --all` resolves semantic and legacy palette keys. Active theme changes are detected without installing a hook or editing packaged Omarchy files. Ctrl+F searches, Ctrl+D saves, Ctrl+Q quits, and Escape restores navigation.

The collapsible table of contents follows API prayer categories, Arabic/Persian Hidden Words divisions, and book → tablet/part → passage nesting for writings. Expansion choices persist; search temporarily expands matching branches. Previous/Next stays within the selected category or book division.

## Offline languages

Open **Aa → Languages & offline libraries…**. English is the first-run default and includes all ten supported collections locally. No network request is made at startup or when switching to an already downloaded language.

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
