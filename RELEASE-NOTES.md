Patch release of Bahá’í Reader.

v0.1.1 fixes startup on minimal Linux installations whose font catalog does not include the preferred reading font. The app now selects the first installed font safely.

- Ten English collections included for offline reading.
- Downloadable language libraries with 112 prayer languages in the catalog.
- Collapsible contents, saved passages, prayer word counts, and offline search.
- Adjustable sidebar, reading typography, palettes, and smooth wheel scrolling.
- Live Omarchy theme integration with standalone GTK support on other Linux desktops.

Choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, or `.AppImage` for a portable launcher. The packages are architecture-independent; the AppImage launcher is x86_64. All require a host Python 3.11+ with PyGObject, GTK 4.8+, and its introspection data. Package managers install dependencies for the native packages; install them separately before using the AppImage.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md. This is an independent community app. The online AI search is not integrated.
