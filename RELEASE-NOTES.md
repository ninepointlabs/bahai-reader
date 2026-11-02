## Unreleased

- New: **Narrow windows**: below 700 px the contents list and the right pane take turns, and the window can shrink to 320 px.
- New: **Passage headings and position**: “Arabic no. 1”, “Paragraph 4”, and “1 of 71” between Previous and Next.
- Fixed: neither pane can be dragged below its minimum width, so neither can disappear.

Patch release of Bahá’í Reader.

v0.1.8 adds a new **Today** view that brings the day together, and reorganizes the header around it.

- New: **Today**, the first sidebar entry: the Badí‘ date, sunrise, noon and sunset, your obligatory prayer’s time, the next Feast and Holy Day, the Fast and the passage of the day. In the sidebar it lists the next 12 months and this year’s months. New installs open here; existing installs keep their place.
- Changed: **Ctrl+T and the Today button now open the Today view** instead of the passage of the day, which is a card there.
- Changed: **Languages & offline libraries and About moved from Aa to a new ⋮ menu**, with Location & reminders and Keyboard shortcuts. Aa keeps the reading settings. F1 still opens About.
- New: **Location**: type a city, found offline in a bundled GeoNames list, or enter coordinates. It is never detected and never sent anywhere.
- New: **Obligatory prayer times and Said today**, taken from the bundled texts. For the Long prayer you choose which twenty-four hours count, because no text says and no ruling has been made; sunset to sunset is the default, and its one reminder is opt-in.
- New: **Clock times**, for regions where days and nights vary greatly: enter the hours your National Spiritual Assembly uses, and they replace the sun. The app has none of its own.
- New: **Alláh-u-Abhá counter** (Ctrl+Shift+A), with Kitáb-i-Aqdas ¶18.
- New: **Reminders**, all off by default, for the prayer, Feasts, Holy Days and the Fast, with an opt-in to keep them running when the window is closed.
- New: **The Fast**: the day, the fasting hours and an optional private Fasted today check.
- Badí‘ dates come from the Universal House of Justice’s table for 172 to 221 B.E.; after that the app says they have not been published yet.

v0.1.7 added every Kitáb-i-Aqdas paragraph on obligatory prayer to the Obligatory prayers section. v0.1.6 showed the directions in the obligatory prayers in italics. v0.1.5 added Copy with citation (Ctrl+Shift+C), the Obligatory prayers section, collections for saved passages, Today and Random passages (Ctrl+T, Ctrl+R), and two languages side by side.

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
