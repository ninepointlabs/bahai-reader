Bug-fix release of Bahá’í Reader.

- Fixed: **Dogear answers drawn over the question.** When a blank starts at the end of a question's own line, Dogear's answer begins after the question; the import dropped that, so the first line was drawn over the printed words. New imports keep it, and answers already brought in are put right the first time the book is opened on the computer that has Dogear (their words are not changed); the correction reaches your other devices through sync.
- A long answer on ruled lines now starts after the question and wraps onto the full-width lines below, as in Dogear, and a click anywhere in it opens it.
- The Study library's note on privacy now says that imported books go into your own sync folder when you sync through one (they are never uploaded anywhere else).

1.1.1 fixed typing answers (Space no longer turns the page), made a table of contents for PDFs without one, and shared imported PDFs through the sync folder. 1.1 added Study (your own PDFs, such as your copies of Ruhi Institute books, with highlights, notes, bookmarks and answers on the blank lines; the app includes no Ruhi Institute material and is not affiliated with or endorsed by the Ruhi Institute).

Downloads: `bahai-reader-1.1.2.apk` (Android), `bahai-reader-1.1.2-windows-x64-setup.exe` or `-windows-x64.zip` (Windows; not code-signed yet, so SmartScreen may warn: **More info → Run anyway**), and the Linux packages below.

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli). `add` only starts tracking the repository; `install` installs the package and asks for your password:

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
autonomix-cli install bahai-reader
```

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, `.AppImage` for a portable download, or `.flatpak` for any distribution with Flatpak. Linux downloads are x86_64.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md and are not covered by the MIT license. This is an independent community app, not an official publication of a Bahá’í institution.
