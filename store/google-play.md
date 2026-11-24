# Google Play listing (draft)

Package: `com.ninepointlabs.bahai_reader` (fixed forever once the first build is uploaded).
Upload: `bahai-reader-<version>.aab` from the GitHub release (signed with the existing release key, which becomes the
upload key; let Play App Signing hold the app signing key).

## App name (max 30)

Bahá’í Reader

## Short description (max 80)

<!-- short:start -->
Bahá’í prayers and writings to read offline. No account, no ads, no tracking.
<!-- short:end -->

## Full description (max 4000)

Written for what the Android app does today: English only (other languages cannot be downloaded on Android yet), no
network access, reminders available, Study (imported PDFs), notes export/import and folder sync through the system
pickers, and the *Include notes in Android backup* switch. Do not mention the 112 prayer languages or downloads here
until Android has them. Do not mention Dogear import (Linux only). The Study wording and the Ruhi Institute notice
follow the website and the Study plan (§10); keep the notice whenever Ruhi is named.

<!-- full:start -->
Bahá’í Reader is a quiet place to read the Bahá’í prayers and writings on your phone, with everything ready offline.

THE LIBRARY
• A prayer book of 472 English prayers, organized by topic.
• The Hidden Words, Arabic and Persian, each in its own place.
• Seventeen more books by Bahá’u’lláh, ‘Abdu’l‑Bahá, Shoghi Effendi and the Universal House of Justice, including Gleanings, the Kitáb-i-Íqán, the Kitáb-i-Aqdas with its notes, Some Answered Questions, God Passes By, and the Riḍván messages.

English texts are the official ones from the Bahá’í Reference Library (bahai.org) and come with the app. There is nothing to download before you start.

READ YOUR WAY
• Search every prayer and writing at once, or just one book. Accents, case and apostrophes do not get in the way.
• Highlight a line in one of five colours and add a note.
• Save passages to return to, and pick up where you left off.
• Choose light, dark or sepia, and a comfortable text size.

STUDY
• Import a PDF of your own, such as your copy of a Ruhi Institute book, and study it the way you would on paper.
• Type your answers right on the blank lines, highlight in five colours, write notes and bookmark pages.
• Each time through a book is kept, so you can see every answer you have given to a question.
• File books in categories, search every highlight, note and answer, and export a book to Markdown.
• A new edition of a book? Your marks move to it.
The app includes no Ruhi Institute material and is not affiliated with or endorsed by the Ruhi Institute. A PDF you import is copied into the app on your device. The app never uploads it; it leaves your device only if you sync through a folder.

TODAY
• The Badí‘ date, the next Feast and Holy Day, and their readings.
• Sunrise, noon and sunset for your place, and the time for your obligatory prayer.
• An Alláh-u-Abhá counter.
• Optional reminders for your obligatory prayer, Feasts, Holy Days and the Fast.

YOUR NOTES, ON EACH DEVICE
• Export everything you have marked to one file and merge it on another device.
• Or choose a folder that Syncthing, Dropbox or the like keeps in step, and your devices share your highlights, notes and answers.
• Export highlights and notes to Markdown.
• Choose whether Android’s own backup includes your notes.

YOURS, ON YOUR PHONE
• No account, no ads, no analytics, no tracking.
• The app does not use the internet at all.
• Your highlights, notes, answers, books and settings stay on your phone, unless you export or sync them, or let Android back up your notes.
• Location is optional and approximate, used only on your phone to work out the sun’s times. You can type a city instead.

Bahá’í Reader is free, and its code is open. It is an independent community project and not an official publication of a Bahá’í institution.

Privacy: https://bahaireader.org/privacy
<!-- full:end -->

Character counts on 24 November 2026: short 77, full 2839. Keep the short
description at 80 or fewer and the full one at 4000 or fewer if you edit.

## Other listing fields

- Category: Books & Reference.
- Tags: prayer, religion, books (choose from Play's list).
- Contains ads: No.
- In-app purchases: None. Price: Free.
- Website: https://bahaireader.org/
- Privacy policy: https://bahaireader.org/privacy
- Email: Tim to choose (shown publicly).

## Before the first upload (things to check in Play Console, not done here)

- Personal developer accounts: Play has required new personal accounts to run a closed test (at least 12 testers who
  stay opted in for 14 days) before production access is granted. Check the current rule in Play Console when the
  account is made.
- Release notes per release can come from `RELEASE-NOTES.md` (500 characters per language in Play).
- `versionCode` comes from the build number after `+` in `pubspec.yaml` (`+112` for 1.1.2). Every upload needs a higher one.
