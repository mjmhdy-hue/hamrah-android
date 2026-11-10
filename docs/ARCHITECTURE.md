# Architecture

## Process / layer ownership

| Layer | Owns | Writer |
| --- | --- | --- |
| Flutter (`lib/`, Dart) | `app.db` (Drift + SQLite3MultipleCiphers) | Flutter only |
| Kotlin (`android/app/src/main/kotlin`) | `native_inbox.db` (SQLCipher), alarms, notifications | Kotlin only |

The native path works with **no Flutter engine**: whitelist → normalize → template → dedupe →
persist → notify → category resolution. Alarms, follow-ups, snooze, "tomorrow", rollover and boot
restore are all native. Flutter is the system of record for transactions, categories, accounts,
reminders, occurrences and history.

```
SMS_RECEIVED ──▶ SmsReceiver ──▶ SmsPipeline ──▶ NativeInboxDb (SQLCipher)
                                     │                    │
                                     ├──▶ TxNotifier      │ drainInbox()/ackInbox()
                                     │      └ actions ──▶ resolutions
                                     └──▶ diag_log         ▼
                                                    ImportService (one Drift transaction)
                                                          │
                                                          ▼
                                                app.db (SQLite3MultipleCiphers)

AlarmManager ──▶ AlarmReceiver ──▶ notification ──▶ AlarmActionReceiver ──▶ outcome_events
                     ▲                                             │
                     └──────────── AlarmScheduler ◀────────────────┘
```

## Contract (version 1)

Implemented over two `MethodChannel`s in `android/app/src/main/kotlin/com/hamrah/app/bridge/NativeBridge.kt`
and `lib/native/native_bridge.dart`. `pigeons/native_api.dart` documents the same typed surface for
generating a Pigeon channel later.

Flutter → native:

| Method | Payload | Meaning |
| --- | --- | --- |
| `getDbKey()` | – | main DB passphrase from Keystore (in-process only) |
| `syncSnapshot(json)` | categories, merchant memory, whitelist, settings | whole config; also before SMS permission request |
| `upsertAlarm(json)` | occurrenceUid, reminderId, rev, title, scheduledFor, followupCount, followupIntervalMin, priority | rev-monotonic; native ignores older rev and never resurrects resolved occurrences |
| `cancelAlarm(uid)` | occurrence uid | cancels occurrence + follow-ups, marks dismissed |
| `drainInbox(limit)` | – | batch JSON (at-least-once) |
| `ackInbox(batchId)` | – | mark batch imported |
| `getDiagnostics()` | – | permissions, key, native DB, last SMS, 200 log lines |
| permission helpers | – | SMS/mic/notification request, exact-alarm and battery/settings screens, `consumePendingRoute()` |

Native → Flutter: `events` channel pushes a `route` when a notification is tapped while the engine
is alive; otherwise the route waits in SharedPreferences until `consumePendingRoute()`.

Batch shape:

```json
{"batchId":"…","contractVersion":1,
 "sms":[{"eventUid":"…","sender":"…","body":"…","receivedAt":0,"parseStatus":"parsed",
         "templateId":"melli_v1","bankCode":"melli","errorCode":null,"hash":"…","partCount":2}],
 "transactions":[{"txUid":"…","smsEventUid":"…","smsHash":"…","bankCode":"blu","accountHint":"",
                  "direction":"out","amountRial":2600000,"occurredAt":0,"timeSource":"body",
                  "counterparty":null,"counterpartySource":null,"purposeText":null,
                  "label":"برداشت پول","balanceAfterRial":50038727,"suggestionKey":"برداشت پول"}],
 "resolutions":[{"eventUid":"…","txUid":"…","action":"categorize","categoryId":"…","note":null,"createdAt":0}],
 "outcomes":[{"eventUid":"…","occurrenceUid":"…","reminderId":"…","rev":2,"outcome":"done","snoozedUntil":null,"resolvedAt":0}],
 "occurrences":[{"eventUid":"…","occurrenceUid":"…","reminderId":"…","rev":2,"title":"…","scheduledFor":0,"reason":"rolled_over"}]}
```

Import order inside one Drift transaction: `raw_sms` (INSERT OR IGNORE on hash) → accounts →
transactions (INSERT OR IGNORE on `tx_uid`) with gap bookkeeping → resolutions → occurrences →
outcomes → `import_log` (event_uid). Then `ackInbox`. A crash before ack replays the batch; all
writes are idempotent.

`contract_version` mismatches refuse the import and write a diagnostic.

## Encryption and keys

- One non-exportable Android Keystore AES-256-GCM key (`hamrah_master_v1`), StrongBox when the
  device offers it. It wraps two independent random 32-byte passphrases (`keys/main.key`,
  `keys/native.key`) stored as version|iv|ciphertext in app-private storage.
- `getDbKey()` hands the main passphrase to Flutter in-process only. No plaintext passphrase is
  written to disk or logs.
- Native DB: SQLCipher (`net.zetetic:sqlcipher-android`). Main DB: Drift + `sqlite3` built with
  SQLite3MultipleCiphers (`hooks:` in `pubspec.yaml`) and `PRAGMA key` in `NativeDatabase.setup`.
  Both sides verify the cipher at open; failure shows a blocking recovery screen and **never
  recreates or deletes the database**.

## Database schema (main, Drift)

`categories`, `accounts`, `raw_sms`, `transactions`, `merchant_memory`, `reminders`,
`reminder_occurrences`, `settings`, `import_log` — columns as specified in the brief, plus
`transactions.label` (the verified bank message type, needed for display and the merchant-memory
key). Money is `INTEGER` Rial (int64), time is UTC.

Gap bookkeeping: `gap = actual - (previousBalance + signed amount)` on import, recomputed for the
immediately following transaction when an older one arrives. Gaps are surfaced, never auto-fixed.

Soft delete keeps `raw_sms.hash`, so a deleted transaction is never re-created from the same SMS.

## Native inbox schema

`sms_events` (raw/normalized + status + unique hash), `tx_events` (parsed, `imported` flag),
`resolutions`, `alarms` (pending occurrences with rev + follow-ups), `outcome_events`,
`occurrence_events`, `snapshot`, `otp_hints` (P2, 15-minute TTL, never the code), `diag_log`
(rotated at ~2000 rows, codes only).

## Alarm semantics

- One PendingIntent identity per occurrence **and** follow-up index (`hamrah://alarm/<uid>/<index>`).
- `setExactAndAllowWhileIdle` when `canScheduleExactAlarms()`, otherwise `setAndAllowWhileIdle` plus
  a visible warning in the UI.
- Follow-ups: after firing index *i*, schedule *i+1* at `now + interval` while `i+1 < followupCount`.
- Snooze: same occurrence rescheduled at +10 min, `snooze_count + 1`, follow-ups reset.
- Tomorrow: outcome `deferred_tomorrow`, new occurrence next day at the same clock time.
- Rollover: a daily alarm at the configured time plus catch-up at boot/app start; overdue pending
  occurrences become `rolled_over`, a next-day occurrence is created at the same clock time and
  `rollover_count` increments. No duplicate occurrences thanks to `UNIQUE(reminder_id, scheduled_for)`.

## Normalization / templates

`Normalizer` handles Arabic yeh/kaf → Persian, Persian/Arabic-Indic digits, ZWNJ/ZWJ/bidi/BOM,
NBSP, CRLF, per-line trim and space collapsing (blank lines dropped). Sender canonicalization
removes separators, one leading `+`/`00`, one leading `98`, one leading `0`. Templates are anchored
regexes in `core/SmsParser.kt`; only the verified labels/types create transactions. OTP shapes never
create transactions, never notify, and persist a masked body.

## Threading

`Application.onCreate` warms the native DB on a background thread, restores alarms, runs rollover
catch-up and SMS recovery. Receivers use `goAsync()` + a short thread. Drift runs on its own
background isolate (`NativeDatabase.createInBackground`).
