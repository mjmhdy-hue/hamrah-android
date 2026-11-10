# Limitations

Deliberate scope decisions and things that were **not** verified in this build environment.

## Delivered subset and scope

- **No recurring reminders.** One occurrence per reminder; rollover creates the next day's
  occurrence only for unfinished work.
- **No app lock (PIN/biometric)** — this was the lowest-priority cut item of the allowed list. The
  database and SMS/alarm background work are still protected by encryption and remain independent of
  the UI.
- **No backup / export / import.** `allowBackup=false`; Keystore keys cannot move between devices.
- **No cloud, login, multi-user, budgets, loans, cheques, OCR, widgets, overlays or full-screen
  intents.** No background microphone.
- **Templates cover only the verified Appendix A message types.** Anything else from a whitelisted
  sender goes to the Unrecognized inbox; other banks are marked unsupported.

## Platform / distribution

- The app is **sideloaded**. On Android 15+ a sideloaded app must enable *Allow restricted settings*
  before the SMS permission can be granted; Onboarding and Diagnostics show the exact path and open
  the app-details screen.
- Play Store distribution is out of scope (`RECEIVE_SMS` would require a declared exception).
- Exact alarms: when `SCHEDULE_EXACT_ALARM` is denied the app falls back to inexact alarms and shows
  a warning; reminders may be late.
- OEM battery managers and auto-start behavior are **untested and not claimed**. The reliability
  screen only offers self-reported checkboxes.
- Day/time and Jalali conversion use `Asia/Tehran` (Iran no longer observes DST). A bank clock that
  disagrees with the phone clock can still shift a transaction by minutes.

## Voice

- Recognition is done by the device's speech service, which may be online depending on the phone;
  only spoken words leave the device, never SMS content or amounts. Voice is foreground-only and
  fills text fields only; the reminder date/time always comes from the Jalali picker.
- If the service is missing/denied the mic is disabled and the reason is shown in Diagnostics.

## Data

- Balance discrepancies are detected and displayed, never corrected. The fixtures contain a known
  gap (M5→M6 = −82,000 Rial) and, because they are a partial capture, another one between the older
  Blu messages and B1.
- Duplicate detection is exact-hash only (`SHA-256(canonicalSender + "\n" + normalizedBody)`). Two
  genuinely identical texts with no balance/time difference (not present in the samples) would be
  treated as one message, which is the specified behaviour.
- The bank message body is unauthenticated and can be spoofed; every transaction is editable and
  deletable, and the only side effect of a spoofed message is a local notification.

## Verification limits of this delivery

- **No APK is included** and `flutter analyze` / `flutter test` / Gradle builds were not executed:
  this machine is aarch64 Linux (no Flutter SDK for that host), has no JDK/Android SDK pre-installed
  and no emulator. The Kotlin core was compiled and its fixture suite executed with an arm64 JDK;
  the Android layer was type-checked against `android.jar` 36; the Dart data layer was generated
  with drift and analyzed/tested with a standalone Dart SDK (see `docs/TEST_REPORT.md`).
- UI rendering, RTL/Jalali widget tests and instrumented tests must be run by the user with
  `flutter analyze`, `flutter test`, and `gradlew connectedDebugAndroidTest`.
