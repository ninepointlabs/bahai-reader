Patch release of Bahá’í Reader.

v0.1.3 adds an About screen.

- New: an About screen, opened from **Aa → About Bahá’í Reader** or with F1. It shows the version, Nine Point Labs, the creation date, the full MIT license with the text attribution, the support address help@ninepointlabs.com with Email and Copy buttons, the privacy statement, and the toolkit versions.
- Changed: the LICENSE copyright holder is now Nine Point Labs.
- Changed: the AppImage now ships VERSION, LICENSE and DATA-NOTICE.md.

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
