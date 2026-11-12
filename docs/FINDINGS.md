# Audit findings — status (2026-11-12)

Audited commit `828f722a80a40a020d59132375e5fb7c6c306dc1` (build 16). This is the honest state of the
28 findings: what is fixed, how it was proven, and what is still open.

Proof levels used here:

* **PROVEN** — checked by a run or a measurement whose output is recorded (CI log, signature check).
* **BUILT** — code is implemented and compiled/analysed by CI, but the behaviour was never executed
  (no device/emulator, no instrumented test).
* **OPEN** — not fixed yet.

| ID | Pri | Short | Status | Proof / note |
| --- | --- | --- | --- | --- |
| F02 | P0 | builds 15/16 signed with throw-away debug keys | **PROVEN** | release 23 signed with `CN=Hamrah`; signer cert SHA-256 equals the keystore cert `9eeeda74…`; no debug fallback (build fails without the key) |
| F01 | P0 | native `sms_events` has no `batch_id`, drain dies with "no such column" | BUILT | `NativeInboxDb` schema 1→2 with in-place `migrateV1ToV2` (adds `batch_id`, `delivered`, index, keeps rows), drain reads `delivered = 0` by cursor, ack sets `delivered = 1` |
| F03 | P0 | OTP body persisted before parsing | BUILT | parse happens first; OTP stores the masked body only; `RedactionTest` added (not executed in CI yet — see F24) |
| F04 | P1 | Blu customer name stored in `sms_events`/`raw_sms` | BUILT | `Normalizer.redactPersonal()` on every persisted body including OTP; unit test added |
| F26 | P1 | empty/malformed whitelist restores seed banks | BUILT | absent → defaults, explicit empty → nothing, invalid → block all |
| F15 | P1 | unrecognised/OTP SMS starve (latest-100 query) | BUILT | delivered-cursor query with `ORDER BY received_at, created_at LIMIT ?` + ack |
| F23 | P2 | unpinned toolchain | PARTIAL | Gradle 9.5.0 / AGP 9.3.1 / Kotlin 2.4.20 pinned in-repo; **Flutter pin and action SHAs need a workflow edit** — the repo token cannot write `.github/workflows`, so CI still uses Flutter "stable" |
| F24 | P2 | CI does not run Kotlin tests | PARTIAL | `android/app/src/test/.../RedactionTest.kt` exists; wiring `./gradlew app:testDebugUnitTest` into the workflow is blocked by the same permission |
| F05 F06 F07 F08 F09 F10 F11 F12 F13 F14 F16 F17 F18 F19 F20 F21 F22 F25 F27 F28 | P1/P2 | idempotency, revisions, alarm scheduling, privacy UI, parser, diagnostics | OPEN | not touched in this batch |

## Why the runtime proofs are missing

No Android SDK, emulator, JDK or Flutter SDK is available in the workspace that produced this commit,
and the app needs a real SMS receiver plus Doze/reboot behaviour. The CI job builds and runs the Dart
tests, but it cannot deliver SMS to a device. Every "BUILT" row therefore needs the acceptance steps in
`docs/TEST_REPORT.md` executed on a phone before it can be called verified.

## Test on the phone (5 minutes, synthetic data only)

1. Install build 23 over build 23 (re-download) — it must update in place, no uninstall.
2. Send a synthetic bank SMS from a whitelisted sender; open Ledger: the transaction appears once.
3. Send 60+ unrecognised messages; check Diagnostics: count decreases batch by batch, no repeats.
4. Force-stop the app, send an OTP-like SMS, start the app, then inspect Diagnostics/SQLite dump: no
   6-digit run and no personal name in `sms_events`.
5. Clear the sender whitelist → send a bank SMS → nothing is imported and the whitelist size is 0.
