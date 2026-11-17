# Google Play: Data safety and App content (draft answers)

Checked against `main` on 17 November 2026. The release manifest of the AAB built from this branch declares exactly:
`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `ACCESS_COARSE_LOCATION` (and the
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` that AndroidX adds for itself). **No `INTERNET`.** Play's Data safety form
is about data that leaves the device ("collected" = sent off the device; "shared" = sent to a third party). Nothing
leaves the device in the Android app, because it cannot reach the network.

## Data safety

| Question | Likely answer | Why |
|---|---|---|
| Does your app collect or share any of the required user data types? | **No** | No network access on Android. Location, notes, highlights and settings are processed and stored only on the device. Google's guidance: data processed only on the device is not "collected". |
| Is all of the user data collected by your app encrypted in transit? | Not asked once the answer above is No | — |
| Do you provide a way for users to request that their data is deleted? | Not asked once the answer above is No | There is no account and no server-side data. |

With "No", the listing shows "No data collected" and "No data shared with third parties".

Re-check this form if the Android app ever gains the INTERNET permission (for language downloads): requests to
bahaiprayers.net would then send the device's IP address to a third party when the person asks for a download, and
the form and the privacy page would both need updating.

Per data type, for Tim's reference (all "not collected, not shared"):

- **Location — approximate**: only when "Use my location" is tapped; Android's own location service, coarse
  permission only; one reading, saved on the device; not sent anywhere. (`android/app/src/main/kotlin/.../Locate.kt`,
  `lib/core/platform/locator.dart`.)
- **Personal info / Messages / Photos / Contacts / Financial / Health**: none touched.
- **App activity — other user-generated content** (notes, highlights, saved passages, "Said today" / "Fasted today"):
  stored in the app's settings file on the device only (`lib/core/settings/settings_store.dart`).
- **App info and performance — crash logs, diagnostics**: none; there is no crash reporting or analytics SDK
  (`pubspec.lock`: no Firebase, Sentry, analytics or ads packages).
- **Device or other IDs**: none read.

## App content declarations

- **Privacy policy**: https://bahaireader.org/privacy
- **Ads**: No ads.
- **App access**: All functionality is available without special access (no login).
- **Content rating**: see [content-rating.md](content-rating.md).
- **Target audience and content**: Recommendation: choose the age groups **13–15, 16–17 and 18+** and do not tick any
  under-13 group. The app is not designed for children, has no characters or child-directed design, and choosing an
  under-13 group would bring it under the Families policy. Answer **No** to "Could your store listing unintentionally
  appeal to children?" — it is a scripture reader. (Tim's decision: if he wants the app listed for families, that
  is possible, because the app collects nothing, but it brings extra review.)
- **News app**: No.
- **COVID-19 contact tracing / status**: No.
- **Data safety**: as above.
- **Government app**: No.
- **Financial features**: None.
- **Health**: No health features.

## Permissions that may draw questions

- **`SCHEDULE_EXACT_ALARM`**: used so reminders come at the minute (e.g. the obligatory prayer time). The app asks the
  person to allow "Alarms & reminders" on Android 12+, and works without it. This is the user-granted permission, not
  `USE_EXACT_ALARM` (which Play restricts to alarm and calendar apps). As of writing, Play's exact-alarm declaration
  is required for `USE_EXACT_ALARM`; if Play Console asks about `SCHEDULE_EXACT_ALARM`, the honest answer is
  "reminders the user sets for prayer times, Feasts, Holy Days and the Fast". Check in Play Console.
- **`ACCESS_COARSE_LOCATION`**: foreground only, approximate only, on tap. No background location, so no
  background-location declaration.
- **`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`**: reminders, and setting them again after a restart. No
  declaration needed.
- No foreground services, no `QUERY_ALL_PACKAGES`, no SMS/call log, no accessibility service.
