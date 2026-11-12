# Signing (F02)

Builds 15 and 16 were signed with throw-away **debug** certificates generated on each CI run, so one
could never be installed over the other. Release builds now require the project keystore and there is
**no debug fallback**: `android/app/build.gradle.kts` throws if `android/key.properties` is missing.

## Where the key lives

| File | Purpose |
| --- | --- |
| `android/keystore/hamrah-release.p12` | RSA-2048, self-signed `CN=Hamrah`, valid 30 years, PKCS12 |
| `android/key.properties` | alias/password/store path (referenced by Gradle) |

Both are **versioned in this repository on purpose**: the app is distributed by sideload only, CI has
no secret store, and every rebuild must keep the same certificate so an update can replace the
previous install without uninstalling (which would destroy the encrypted databases).

This is a deliberate exception to "never commit keys". The key protects update integrity, not
confidentiality — it grants no access to user data. Rotate it (and accept that old installs must be
uninstalled) before publishing on any store, or move it to `KEYSTORE_BASE64`/`KEY_PROPERTIES`
secrets and delete the committed copies.

## Version code policy

`versionCode` follows `pubspec.yaml` (`1.0.0+N` -> N). Every published build must raise `N`, otherwise
Android refuses the in-place update. Bump the `+N` suffix in `pubspec.yaml` for any release you hand
out.

## Recovery for installs on build 15/16 (different signer)

Android rejects an update signed by a different key. The only path is uninstall -> install, which
**permanently deletes both encrypted databases** (there is no backup feature). Before doing that:

1. Open the app, go to Settings -> diagnostics, and export/screenshot whatever you need (there is no
   export feature, so screenshots of the ledger only).
2. Uninstall, install the new APK, grant the SMS permission again.
3. SMS that arrived while the app was uninstalled are *not* imported automatically on most Android
   versions; only new messages are captured.

There is no way to migrate data across signers; the databases are protected by the Keystore key.
