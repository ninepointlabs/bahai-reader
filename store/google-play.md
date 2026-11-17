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
network access, reminders available. Do not mention the 112 prayer languages or downloads here until Android has them.

<!-- full:start -->
Bahá’í Reader is a quiet place to read the Bahá’í prayers and writings on your phone, with everything ready offline.

THE LIBRARY
• A prayer book of 472 English prayers, organized by topic.
• The Hidden Words, Arabic and Persian, each in its own place.
• Seventeen more books by Bahá’u’lláh, ‘Abdu’l‑Bahá, Shoghi Effendi and the Universal House of Justice, including Gleanings, the Kitáb-i-Íqán, the Kitáb-i-Aqdas with its notes, Some Answered Questions, God Passes By, and the Riḍván messages.

English texts are the official ones from the Bahá’í Reference Library (bahai.org) and come with the app. There is nothing to download before you start.

READ YOUR WAY
• Search every prayer and writing at once, or just one book. Accents, case and apostrophes do not get in the way.
• Highlight a line in one of four colours and add a note.
• Save passages to return to, and pick up where you left off.
• Choose light, dark or sepia, and a comfortable text size.

TODAY
• The Badí‘ date, the next Feast and Holy Day, and their readings.
• Sunrise, noon and sunset for your place, and the time for your obligatory prayer.
• An Alláh-u-Abhá counter.
• Optional reminders for your obligatory prayer, Feasts, Holy Days and the Fast.

YOURS, ON YOUR PHONE
• No account, no ads, no analytics, no tracking.
• The app does not use the internet at all.
• Your highlights, notes, saved passages and settings stay on your phone.
• Location is optional and approximate, used only on your phone to work out the sun’s times. You can type a city instead.

Bahá’í Reader is free, and its code is open. It is an independent community project and not an official publication of a Bahá’í institution.

Privacy: https://bahaireader.org/privacy
<!-- full:end -->

Character counts on 17 November 2026: short 77, full 1717. Keep the short
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
- `versionCode` comes from the `+101` in `pubspec.yaml`. Every upload needs a higher one.
