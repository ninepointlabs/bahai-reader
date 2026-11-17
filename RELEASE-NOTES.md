Bahá’í Reader 1.0: the app is rebuilt with Flutter, so the same reader now runs on **Linux, Android and Windows**.

The texts, how they are cited and the offline promise are unchanged: English is bundled, other languages download only when you ask, and nothing else ever uses the network.

- New: **Android.** Install `bahai-reader-1.0.0.apk` (Android may ask you to allow installs from your browser or file manager). The phone has Today, the prayers and writings, search, highlights, notes and saved passages, the Alláh-u-Abhá counter and reminders that arrive with the app closed.
- New: **Windows** (64-bit). Run `bahai-reader-1.0.0-windows-x64-setup.exe` to install for your user, or unzip `bahai-reader-1.0.0-windows-x64.zip` and run `bahai-reader.exe`. They are not code-signed yet, so Windows SmartScreen may warn the first time: choose **More info → Run anyway**. Reminders are not sent on Windows yet.
- **Upgrading on Linux:** the first time 1.0 starts it brings over your highlights, notes, saved passages, collections, reading places and settings from earlier versions, and reads the languages you already downloaded. The earlier version’s files are only read, never changed or removed, so going back to 0.2.3 keeps everything it had. 1.0 keeps its own settings in `~/.config/bahai-reader-flutter/`.
- **If you used “Keep reminders running when the window is closed”:** turn it on again in ⋮ → Location & reminders after updating. Your reminder choices are kept; only the login entry needs to be made again.
- Changed: the Linux packages are now built for x86_64 (`_amd64.deb`, `.x86_64.rpm`, `-x86_64.pkg.tar.zst`) instead of architecture-independent; they need GTK 3, which every desktop has, and no longer need Python. The AppImage and Flatpak keep their names, so AppImage updaters (Gear Lever, AppImageLauncher, `zsync`) find 1.0.
- Removed: the classic GTK window and the `BAHAI_READER_SHELL` switch. The 0.2.3 release stays available for systems that need it.

Install with [autonomix-cli](https://github.com/ninepointlabs/autonomix-cli). `add` only starts tracking the repository; `install` installs the package and asks for your password:

```sh
autonomix-cli add https://github.com/ninepointlabs/bahai-reader
autonomix-cli install bahai-reader
```

Or choose `.deb` for Debian 12+/Ubuntu 24.04+, `.rpm` for Fedora 43+ and compatible modern RPM systems, `.pkg.tar.zst` for Arch/Omarchy, `.AppImage` for a portable download, or `.flatpak` for any distribution with Flatpak. Linux downloads are x86_64.

Checksums are in SHA256SUMS. Code is MIT licensed; bundled texts have separate attribution in DATA-NOTICE.md and are not covered by the MIT license. This is an independent community app, not an official publication of a Bahá’í institution.
