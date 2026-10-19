Patch release of Bahá’í Reader.

v0.1.4 makes it easier to read on any Linux distribution.

- New: a Flatpak bundle, `bahai-reader-0.1.4-x86_64.flatpak`. It brings its own Python and GTK through the GNOME runtime, so it runs on any distribution with Flatpak, even where the system GTK is too old. It is a download here, not a Flathub listing. Install it with `flatpak install --user ./bahai-reader-0.1.4-x86_64.flatpak`.
- New: the AppImage can add itself to your application menu with `--install-desktop-entry` (and remove itself with `--remove-desktop-entry`), and it now has proper icons and app info for Gear Lever and AppImageLauncher.
- Changed: if your system’s Python or GTK is missing or too old, the AppImage now says so kindly and points you to the Flatpak instead.

- Ten English collections included for offline reading.
- Downloadable language libraries with 112 prayer languages in the catalog.
- Collapsible contents, saved passages, prayer word counts, and offline search.
- Adjustable sidebar, reading typography, palettes, and smooth wheel scrolling.
- Live Omarchy theme integration with standalone GTK support on other Linux desktops.

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli):

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
```

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, `.AppImage` for a portable launcher, or `.flatpak` for any distribution with Flatpak. The packages are architecture-independent; the AppImage launcher is x86_64. All but the Flatpak require a host Python 3.11+ with PyGObject, GTK 4.8+, and its introspection data. Package managers install dependencies for the native packages; install them separately before using the AppImage.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md. This is an independent community app. The online AI search is not integrated.
