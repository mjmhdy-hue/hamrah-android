# Test report

Environment used for this session: Linux **aarch64** container, no Flutter SDK, no Android SDK, no
emulator (`/dev/kvm` absent), no root. The following toolchains were installed into `/tmp` to run
everything that can run without a device: Temurin **JDK 17.0.21** (arm64), Kotlin **2.1.0** compiler,
Dart **3.13.7** SDK, `android.jar` from **platform 36** plus androidx/sqlcipher jars for type-checking.

The APK could not be produced here (see UNVERIFIED). Every command below is reproducible; evidence
files are in `docs/evidence/`.

## TESTED (executed, with result)

| # | Check | Command (in this environment) | Result |
| --- | --- | --- | --- |
| 1 | Appendix A fixtures through the **shipped Kotlin parser** — 16 messages, all expected fields, Jalali vectors, sender canonicalization, balance chains, M5→M6 = −82,000, B9/B10 distinct hashes, OTP masking, year inference, unknown label, unsupported sender, amount bounds, normalization | `kotlinc core/*.kt FixtureChecks.kt && java … FixtureChecks test/fixtures/sms` | **ALL FIXTURE CHECKS PASSED (16 fixtures)** — `evidence/fixture-checks.txt` |
| 2 | Android/Kotlin layer type-checks against real `android.jar` (API 36) + androidx-core + sqlite + **sqlcipher-android 4.6.1** (all files except the two Flutter-embedding files) | `kotlinc -classpath android.jar:… -d out $(find … ! -path '*bridge*' ! -name MainActivity.kt)` | **exit 0, no errors** — `evidence/kotlin-android-compile.txt` |
| 3 | Money formatting (Toman/Rial, decimal only when needed, Persian digits, `٬`), Jalali vectors, Tehran clock/date | `dart test` (pure Dart copy of `lib/core/formatting.dart`) | **12/12 passed** — `evidence/dart-tests.txt` |
| 4 | Import pipeline against a real Drift **in-memory** database: 15 transactions imported once, batch replay is idempotent, listed balance pairs = 0, M5→M6 = −82,000, B9/B10 two rows, account last balance by newest `occurred_at` | `dart test test/import_service_test.dart` | **5/5 passed** — `evidence/import-tests.txt` |
| 5 | Drift code generation | `dart run build_runner build` (drift 2.35.4 / drift_dev 2.35.3) | **success**, `lib/data/db/app_db.g.dart` (8,094 lines) |
| 6 | Analyzer on data layer + repositories + services + native bridge (Flutter SDK replaced by a stub for `package:flutter/services.dart`) | `dart analyze` | **No issues found** — `evidence/dart-analyze.txt` |
| 7 | Static project checks (65): manifest permission set, INTERNET/BLUETOOTH removed, no READ_SMS/SYSTEM_ALERT_WINDOW, allowBackup=false, dataExtractionRules, cleartext=false, API 26/36 (no 37), sqlite3mc hook, 9 main tables, 9 native tables, Dart↔Kotlin method parity, batch keys, 16 fixtures, verified labels only, no sample first name in sources | `python3 tools/verify_static.py` | **ALL 65 STATIC CHECKS PASSED** — `evidence/static-checks.txt` |
| 8 | Dart syntax parse of all 27 app/test files | `dart format --output=none lib test pigeons` | **no syntax errors** (only formatting differences) |

## PARTIALLY TESTED

| Area | What was covered | What was not |
| --- | --- | --- |
| Android runtime | Kotlin compiles against the real platform jar; SQLCipher API use verified against the artifact's signatures; receiver/notification/alarm code paths are wired | Not executed on a device/emulator: no `RECEIVE_SMS` delivery, no heads-up notification, no action receivers, no boot restore |
| Database encryption | Both `PRAGMA key` paths implemented and asserted at runtime; wrong key fails by design; the instrumented test exists | Not executed (needs a device). The main-DB cipher check depends on the `sqlite3mc` build hook actually resolving on the build machine |
| UI | Widgets written and parsed; navigation targets verified against declared routes; money/date helpers unit-tested | `flutter analyze`, widget tests, golden/RTL rendering, accessibility contrast were **not** run (no Flutter SDK) |
| Reminders | Pure scheduling semantics coded (snooze 10, tomorrow, rollover, follow-up indexes); JVM-tested only where pure | AlarmManager behavior, exact-alarm fallback and reboot restore not exercised |
| Voice | Consent flow, settings toggle, error paths written | speech_to_text plugin runtime, fa-IR availability, permission dialog not exercised |

## UNVERIFIED (not executed — reason)

- `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug/--release`:
  **no Flutter SDK exists for Linux arm64** (Flutter publishes only x86_64 Linux archives; the host is
  aarch64 and has no x86 emulation), and no Android SDK/emulator is available. No APK is delivered.
- Instrumented tests in `android/app/src/androidTest` (receiver with synthesized SMS intents,
  encryption header, wrong-key failure, drain/ack idempotency): require a device.
- Real-bank SMS on the user's phone, OEM battery/auto-start behavior, Android 15 sideload
  "restricted settings" flow: **user must verify**; no claim is made.
- aapt2 manifest verification of a built release APK (no build possible here).

## Deviations / decisions (recorded because the spec said to)

1. **Blank lines** are dropped during normalization (in addition to trimming). Templates require an
   exact line count; blank lines carry no information.
2. **Optional spaces after `:`** are accepted in the Melli amount line (`برداشت: -300,000`), and Blu
   sentences allow optional spaces/period variants. The fixtures after normalization still match the
   literal patterns.
3. `transactions` has an extra `label` column (verified bank message type). It is required for display
   and to make the merchant-memory key identical on both sides.
4. **Pigeon**: the shipping implementation uses two `MethodChannel`s with the same method names and
   JSON payloads (`NativeBridge.kt` / `native_bridge.dart`); `pigeons/native_api.dart` is included so a
   Pigeon channel can be generated later. Code generation was not run here.
5. Normalized body is persisted for all messages (the raw body is what it is derived from); OTP bodies
   are stored with the code replaced by `••••••`. The first name inside Blu sentences is discarded
   before storage and never appears in logs, notifications or tests.
6. The fixtures are a partial capture of the user's SMS history, so **B8 → B1** also shows a balance
   gap (43,068,652 Rial) in addition to the documented M5 → M6 (−82,000). The app reports it and never
   auto-corrects, as specified. All *listed* pairs are exactly 0.
7. The brief's documents live in `docs/` with the requested names (README, ARCHITECTURE,
   TEST_REPORT, LIMITATIONS, plus SECURITY); the repository root has a short `README.md` index that
   links to them, so Flutter tooling and a first-time reader both find their entry point.
