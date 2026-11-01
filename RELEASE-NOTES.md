## Unreleased

A new **Today** view brings the day together, and the header is reorganized around it.

- New: **Today**, the first sidebar entry: the Badí‘ date, sunrise, noon and sunset, your obligatory prayer’s time, the next Feast and Holy Day, the Fast and the passage of the day. In the sidebar it lists the next 12 months and this year’s months. New installs open here; existing installs keep their place.
- Changed: **Ctrl+T and the Today button now open the Today view** instead of the passage of the day, which is a card there.
- Changed: **Languages & offline libraries and About moved from Aa to a new ⋮ menu**, with Location & reminders and Keyboard shortcuts. Aa keeps the reading settings. F1 still opens About.
- New: **Location**: type a city, found offline in a bundled GeoNames list, or enter coordinates. It is never detected and never sent anywhere.
- New: **Obligatory prayer times and Said today**, taken from the bundled texts. The Long prayer has no Said today or reminders yet.
- New: **Alláh-u-Abhá counter** (Ctrl+Shift+A), with Kitáb-i-Aqdas ¶18.
- New: **Reminders**, all off by default, for the prayer, Feasts, Holy Days and the Fast, with an opt-in to keep them running when the window is closed.
- New: **The Fast**: the day, the fasting hours and an optional private Fasted today check.
- Badí‘ dates come from the Universal House of Justice’s table for 172 to 221 B.E.; after that the app says they have not been published yet.

Patch release of Bahá’í Reader.

v0.1.7 completes the Kitáb-i-Aqdas guidance in the Obligatory prayers section.

- Changed: the **Obligatory prayers** section now has every Kitáb-i-Aqdas paragraph on obligatory prayer: ¶6, ¶8, ¶10, ¶12, ¶13 and ¶14. Each comes with the notes and Questions and Answers linked to it, so the section has 44 Aqdas passages instead of 16.

v0.1.6 showed the directions in the obligatory prayers in italics. v0.1.5 added Copy with citation (Ctrl+Shift+C), the Obligatory prayers section, collections for saved passages, Today and Random passages (Ctrl+T, Ctrl+R), and two languages side by side.

- Ten English collections included for offline reading.
- Downloadable language libraries with 112 prayer languages in the catalog.
- Collapsible contents, saved passages, prayer word counts, and offline search.
- Adjustable sidebar, reading typography, palettes, and smooth wheel scrolling.
- Live Omarchy theme integration with standalone GTK support on other Linux desktops.

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli). `add` only starts tracking the repository; `install` installs the package and asks for your password:

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
autonomix-cli install bahai-reader
```

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, `.AppImage` for a portable launcher, or `.flatpak` for any distribution with Flatpak. The packages are architecture-independent; the AppImage launcher is x86_64. All but the Flatpak require a host Python 3.11+ with PyGObject, GTK 4.8+, and its introspection data. Package managers install dependencies for the native packages; install them separately before using the AppImage.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md. This is an independent community app. The online AI search is not integrated.
