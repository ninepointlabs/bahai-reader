Bug-fix release of Bahá’í Reader, from the first days of Study on a real phone and desktop.

- Fixed: **typing an answer no longer loses your place.** Space turned the page, and keys such as j, k, b and 1–5 scrolled, bookmarked or highlighted instead of being typed; while you type an answer, a note or a search they now go to the text.
- New: **a table of contents for PDFs that don't have one.** Study now makes it from the book's headings, as Dogear does (a printed Contents page, headings set larger than the text, and lines like “Section 2”). It is made once, the first time the book opens, and kept on your device.
- Changed: **imported PDFs now travel through your sync folder** (in `bahai-reader-books/`), so a book imported on one device opens on the others; the switch in Settings → Sync through a folder turns it off. A new import goes out within seconds, and a book that arrives shows in the library at once.
- Fixed: the question about **bringing in your Dogear marks** after importing a book can no longer be lost when the book opens. If you skipped it, the book's time-through menu (the clock button) has *Bring in Dogear marks…*.

1.1 added Study (your own PDFs, such as your copies of Ruhi Institute books, with highlights, notes, bookmarks and answers on the blank lines; the app includes no Ruhi Institute material and is not affiliated with or endorsed by the Ruhi Institute), five highlight colours, a notes backup, and syncing through a folder that Syncthing, Dropbox or the like keeps in step.

Downloads: `bahai-reader-1.1.1.apk` (Android), `bahai-reader-1.1.1-windows-x64-setup.exe` or `-windows-x64.zip` (Windows; not code-signed yet, so SmartScreen may warn: **More info → Run anyway**), and the Linux packages below.

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli). `add` only starts tracking the repository; `install` installs the package and asks for your password:

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
autonomix-cli install bahai-reader
```

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, `.AppImage` for a portable download, or `.flatpak` for any distribution with Flatpak. Linux downloads are x86_64.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md and are not covered by the MIT license. This is an independent community app, not an official publication of a Bahá’í institution.
