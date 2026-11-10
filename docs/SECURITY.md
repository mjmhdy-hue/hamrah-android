# Security notes

## Threat model and PII rules

- SMS content never leaves the device. The release manifest has **no INTERNET permission**
  (`tools:node="remove"` also strips the permissions the speech plugin would add). No analytics, no
  ads, no third-party SDKs beyond the pinned Flutter plugins.
- The Blu sentence contains the user's first name. It is never persisted: parsing keeps only amount,
  balance, direction, purpose (for the package purchase) and timestamps. The first name does not
  appear in app sources, fixtures inside the APK, logs, notifications or tests.
- Diagnostics store event codes, statuses and 8-character hash prefixes only — never bodies, names,
  amounts, OTP codes or transcripts. `diag_log` is rotated at ~2,000 rows.
- OTP / dynamic-password messages: never a transaction, never a notification, never a log line. The
  persisted body replaces the code with `••••••`; the optional Blu merchant hint keeps only
  `{merchant, amount, time}` for 15 minutes and never the code.
- Non-whitelisted SMS are discarded in the receiver before any persistence or content logging.

## Keys and databases

- Android Keystore AES-256-GCM key (`hamrah_master_v1`), StrongBox when available, non-exportable.
  It wraps two independent 32-byte passphrases stored only as ciphertext in app-private storage.
- `native_inbox.db` is SQLCipher-encrypted and written only by Kotlin. `app.db` uses
  SQLite3MultipleCiphers through the `sqlite3` build hook; the passphrase is handed to Flutter
  in-process and never written to disk.
- On open failure the app shows a blocking recovery screen. It never recreates or deletes a database
  and never regenerates a key that already exists.

## Manifest

`RECEIVE_SMS`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `RECORD_AUDIO`,
`USE_BIOMETRIC` only. No `READ_SMS`, `READ_CONTACTS`, `SYSTEM_ALERT_WINDOW`, `USE_FULL_SCREEN_INTENT`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, no INTERNET/BLUETOOTH*. `allowBackup=false`,
`fullBackupContent=false`, `dataExtractionRules` excludes every domain, `usesCleartextTraffic=false`.
Receivers are non-exported except the SMS receiver (guarded by `BROADCAST_SMS`); PendingIntents are
immutable and explicit.

## Notification privacy

Transaction notifications use `VISIBILITY_PRIVATE` with a redacted public version ("تراکنش جدید /
مبلغ پنهان است"), and the "always hide amounts" setting removes the amount from the notification and
the UI text.

## Residual risks

- SMS sender addresses can be spoofed. The app treats every SMS-derived transaction as
  unauthenticated, editable and deletable; it never auto-confirms a payment or moves money.
- A compromised OS/rooted device can read anything a normal app can; Keystore protection is not a
  defense against a fully compromised OS.
- The speech service is supplied by the device vendor; its privacy behaviour is outside the app's
  control and is disclosed to the user before first use.
