Patch release of Bahá’í Reader.

v0.1.2 fixes the Fedora package and adds passage citations.

- Fixed: on an up-to-date Fedora 43, the v0.1.1 RPM failed to start with `Typelib file for namespace 'cairo' not found`. The RPM now depends on `gobject-introspection`.
- New: each passage ends with a citation, the author for prayers and the author, book and section for the Writings.

- Ten English collections included for offline reading.
- Downloadable language libraries with 112 prayer languages in the catalog.
- Collapsible contents, saved passages, prayer word counts, and offline search.
- Adjustable sidebar, reading typography, palettes, and smooth wheel scrolling.
- Live Omarchy theme integration with standalone GTK support on other Linux desktops.

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli):

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
```

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, or `.AppImage` for a portable launcher. The packages are architecture-independent; the AppImage launcher is x86_64. All require a host Python 3.11+ with PyGObject, GTK 4.8+, and its introspection data. Package managers install dependencies for the native packages; install them separately before using the AppImage.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md. This is an independent community app. The online AI search is not integrated.
