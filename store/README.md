# Store listing drafts

Drafts for Tim to review and paste into Google Play Console and Microsoft Partner Center. Nothing here is uploaded
automatically, and nothing here is final. There are no images in this folder on purpose: screenshots and feature
graphics will be made separately.

- [google-play.md](google-play.md) — Play listing text (short and full description), with character counts.
- [google-play-data-safety.md](google-play-data-safety.md) — likely Data safety answers, app access, target audience,
  permission notes.
- [microsoft-store.md](microsoft-store.md) — Microsoft Store listing text, and the Partner Center steps that fill the
  TODO identity values in `pubspec.yaml`.
- [content-rating.md](content-rating.md) — likely IARC questionnaire answers (both stores use IARC).

Privacy policy URL for both stores: https://bahaireader.org/privacy (from `docs/privacy.html`, live once this is merged
and GitHub Pages has published it).

Everything here was checked against the code on `main` as of 17 November 2026, and again after merging `main`
(1.1.2: Study, notes export/import, folder sync, the Android backup switch) on 24 November 2026. If the app changes what it does
(for example, Android gains language downloads and the INTERNET permission), the privacy page and these answers must
change with it, before the store build that ships the change.

Things the stores want that are not in this folder:

- Screenshots (Play: at least 2 phone screenshots; Microsoft: at least 1 desktop screenshot), a Play feature graphic
  (1024 × 500) and a 512 × 512 Play icon. The app icon exists at `packaging/icons/hicolor/512x512/apps/`.
- A support contact. Both stores ask for an email address; Play shows it publicly. Use whatever address Tim wants public.
  The website and the issue tracker can be given as well.
