# Microsoft Store listing (draft)

Package: MSIX built by CI from `msix_config` in `pubspec.yaml` (job `windows`, artifact `windows-msix-store-draft`).
It is unsigned on purpose; the Store signs packages it publishes.

## Filling in the identity (one time, after reserving the name)

1. In Partner Center, reserve the app name "Bahá’í Reader" (Apps and games → New product → MSIX or PWA app).
2. Open the product → Product management → **Product identity**. Copy three values into `pubspec.yaml`
   (`msix_config`), replacing the TODO placeholders:
   - `Package/Identity/Name` → `identity_name`
   - `Package/Identity/Publisher` (starts with `CN=`) → `publisher`
   - `Package/Properties/PublisherDisplayName` → `publisher_display_name`
3. Keep `msix_version` as the app version with a `.0` revision (`1.1.2.0` for 1.1.2). CI fails if it does not match
   `version` in `pubspec.yaml`. The Store requires the revision (fourth number) to be 0.
4. The next CI run's `windows-msix-store-draft` artifact is then the package to upload in a submission.

The placeholder package that CI builds before step 2 cannot be submitted: its identity does not match the reserved
name.

## Submission notes

- **Restricted capability `runFullTrust`**: added by the `msix` package for every desktop (Win32) app. Partner Center
  asks why. Suggested answer: "Bahá’í Reader is a Flutter desktop app packaged as MSIX. It runs as a normal desktop
  app (Win32) and needs runFullTrust for that. It does not use any other restricted capability."
- **`internetClient`**: declared because the Windows app downloads a language from bahaiprayers.net when the person
  asks. The Store lists this as "Access your Internet connection".
- **Privacy policy URL** (required because of `internetClient`): https://bahaireader.org/privacy
- **Category**: Books + reference. Subcategory: none needed.
- **Pricing**: Free. No in-app offers.
- **Age rating**: IARC questionnaire, see [content-rating.md](content-rating.md).
- **Markets**: all (Tim's choice).
- **Notes for certification**: "No sign-in. English is bundled; other languages download from bahaiprayers.net only
  when the user picks one in Settings → Languages & offline libraries. The Study section opens PDF files the user
  imports from their own computer through the file dialog; the app includes no third-party books and uploads
  nothing."
- **Intellectual property (Store policy 10.1/11)**: the app is a reader for user-supplied PDFs and bundles no
  third-party books; it is not affiliated with or endorsed by the Ruhi Institute (said in the description and in the
  app). No `broadFileSystemAccess` capability: files come only through the file and folder pickers.

## Product name

Bahá’í Reader

## Short description (optional field, shown in some places; keep it short)

<!-- short:start -->
Bahá’í prayers and writings to read offline. No account, no ads, no tracking.
<!-- short:end -->

## Description (max 10,000)

Written for what the Windows app does today: languages can be downloaded; reminders are not available on Windows yet;
location is typed (city or coordinates), not detected; Study (imported PDFs, file dialog or Ctrl+O), notes
export/import and folder sync are available. Do not mention Dogear import (Linux only) or Android backup. The Study
wording and the Ruhi Institute notice follow the website and the Study plan (§10); keep the notice whenever Ruhi is
named.

<!-- full:start -->
Bahá’í Reader is a quiet place to read the Bahá’í prayers and writings on your computer, with everything ready offline.

THE LIBRARY
• A prayer book of 472 English prayers, organized by topic.
• The Hidden Words, Arabic and Persian, each in its own place.
• Seventeen more books by Bahá’u’lláh, ‘Abdu’l‑Bahá, Shoghi Effendi and the Universal House of Justice, including Gleanings, the Kitáb-i-Íqán, the Kitáb-i-Aqdas with its notes, Some Answered Questions, God Passes By, and the Riḍván messages.

English texts are the official ones from the Bahá’í Reference Library (bahai.org) and come with the app. Prayers in many other languages can be downloaded from BahaiPrayers.net when you choose them, and then read offline. Translation availability varies by book. The interface is in English.

A WINDOW MADE FOR READING
• Home, Prayers, Writings, Study and Saved in the sidebar, the text beside them.
• Open a book and the sidebar becomes its contents, with your place in the book under the text.
• Search every prayer and writing at once (Ctrl+K), or only this book. Accents, case and apostrophes do not get in the way.
• Highlight a line in one of five colours and add a note. Save passages to return to.
• Focus mode (F11) hides everything but the words.
• Light, dark or sepia, your choice of font, text size, spacing and margins.
• Put a passage beside the same passage in another language.

STUDY
• Import a PDF of your own, such as your copy of a Ruhi Institute book, and study it the way you would on paper.
• Type your answers right on the blank lines, highlight in five colours, write notes and bookmark pages.
• Each time through a book is kept. Show the last time beside this one, or see every answer you have given to a question.
• File books in categories, search every highlight, note and answer, and export a book to Markdown.
• A new edition of a book? Your marks move to it.
The app includes no Ruhi Institute material and is not affiliated with or endorsed by the Ruhi Institute. A PDF you import is copied into the app on your device. The app never uploads it; it leaves your device only if you sync through a folder.

TODAY (Ctrl+T)
• The Badí‘ date, the next Feast and Holy Day, and their readings.
• Sunrise, noon and sunset for a place you type in, worked out on your computer, and the time for your obligatory prayer.
• An Alláh-u-Abhá counter.

YOUR NOTES, ON EACH DEVICE
• Export everything you have marked to one file and merge it on another device.
• Or choose a folder that Syncthing, Dropbox, OneDrive or the like keeps in step, and your devices share your highlights, notes and answers. The app itself never goes online for this.
• Saved → Highlights & notes lists them all, with a search and a Markdown export.

YOURS, ON YOUR COMPUTER
• No account, no ads, no analytics, no tracking.
• The app goes online only when you ask it to download a language or check the list of languages.
• Your highlights, notes, answers, books and settings stay on your computer, unless you export them or choose a folder to sync through.

Bahá’í Reader is free, and its code is open. It is an independent community project and not an official publication of a Bahá’í institution.

Privacy: https://bahaireader.org/privacy
<!-- full:end -->

## Product features (up to 20, 200 characters each)

- 472 English prayers and 18 books of the Bahá’í writings, offline
- Search everything at once, or only one book
- Highlights in five colours, with notes
- Study: import your own PDF workbooks and type answers on the blank lines
- Every time through a workbook kept, side by side or question by question
- Export your notes, merge them on another device, or sync them through a folder you choose
- Saved passages and your place in every book
- Today: Badí‘ date, Feasts, Holy Days, sun times and the obligatory prayer
- Download prayers in other languages when you want them
- Focus mode, light, dark and sepia themes
- No account, no ads, no tracking

## Search terms (up to 7)

Bahá’í, Baha'i, prayers, Hidden Words, Aqdas, Ruhi, writings

7 terms, 8 words, none over 30 characters (Partner Center: up to 7 terms, 30 characters each, 21 words in all).
"Ruhi" added by Tim's decision (2026-11-24), in place of "prayer book", which "prayers" already covers.
