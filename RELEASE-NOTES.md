Bahá’í Reader 1.1 adds **Study**: a place to study PDFs of your own, such as your copies of Ruhi Institute books.

The app includes no Ruhi Institute material and is not affiliated with or endorsed by the Ruhi Institute. A PDF you import is copied into the app on your device; it is never uploaded or shared, and the app still uses the network only to download a language when you ask.

- New: **Study** (a sidebar section on the desktop, a tab on phones). Import a PDF (Ctrl+O, or on Android “Open with” / Share), then:
  - highlight in **five colours** and write notes on highlights;
  - **type your answers on the workbook’s blank lines** (the app finds the lines on the page; Tab moves to the next blank), or in a box anywhere on the page;
  - bookmark pages, write notes about the book, search in it, and come back to where you stopped;
  - keep each **time through** a book separately (“1st time, Nov 2026”, “2nd time…”): a new one starts empty, earlier ones are kept read-only, and you can see your earlier answer beside each question or compare two times side by side;
  - file books in **categories**, and search every highlight, note and answer you have written;
  - **export** a time through (or all of them) to Markdown for Obsidian.
- New: **another edition** of a book you have marked is recognized when you import it, and your marks can be moved to it; anything that cannot be found is listed for you to place.
- New on Linux: **bring in your Dogear marks** for a book you import.
- New: **Saved → Highlights & notes** covers the writings, the prayers and Study, with a search and a Markdown export.
- New: **Settings → Back up or move your notes** exports everything you made to one file and merges such a file from another device; **Sync through a folder** keeps your notes in step between devices through a folder that Syncthing, Dropbox or the like shares (the app never goes online; your sync program carries the files).
- Changed: highlights come in **five colours** (yellow, green, blue, pink, purple); earlier magenta highlights are now pink and look the same.
- Changed on phones: Today, Writings, Prayers and Study are in a **bottom bar**.
- Changed: your highlights, notes and saved passages are now kept in a small database beside the settings file (`userdata.sqlite`). The first start of 1.1 moves them there and keeps a copy of the old settings file (`settings.json.pre-userdata-<date>`); going back to 1.0.1 shows your notes as they were at the move.
- Android: imported books are never included in Android’s backup; Settings has a switch for whether your notes are.

Downloads: `bahai-reader-1.1.0.apk` (Android), `bahai-reader-1.1.0-windows-x64-setup.exe` or `-windows-x64.zip` (Windows; not code-signed yet, so SmartScreen may warn: **More info → Run anyway**), and the Linux packages below.

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli). `add` only starts tracking the repository; `install` installs the package and asks for your password:

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
autonomix-cli install bahai-reader
```

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, `.AppImage` for a portable download, or `.flatpak` for any distribution with Flatpak. Linux downloads are x86_64.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md and are not covered by the MIT license. This is an independent community app, not an official publication of a Bahá’í institution.
