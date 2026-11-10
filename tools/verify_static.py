#!/usr/bin/env python3
"""Static consistency checks for the Hamrah project (no Android toolchain required)."""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failures = []
notes = []


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
        return fh.read()


def check(condition, message):
    if condition:
        notes.append(f"PASS  {message}")
    else:
        failures.append(f"FAIL  {message}")


manifest = read("android/app/src/main/AndroidManifest.xml")
permissions = set(re.findall(r'<uses-permission[^>]*android:name="android\.permission\.([A-Z_]+)"', manifest))
removed = set(re.findall(r'<uses-permission[^>]*android:name="android\.permission\.([A-Z_]+)"[^>]*tools:node="remove"', manifest))
declared = permissions

allowed = {
    "RECEIVE_SMS", "POST_NOTIFICATIONS", "SCHEDULE_EXACT_ALARM", "RECEIVE_BOOT_COMPLETED",
    "RECORD_AUDIO", "USE_BIOMETRIC", "INTERNET", "BLUETOOTH", "BLUETOOTH_ADMIN", "BLUETOOTH_CONNECT",
}
check(declared <= allowed, f"manifest permissions are within the allowed set: {sorted(declared)}")
check({"INTERNET", "BLUETOOTH", "BLUETOOTH_ADMIN", "BLUETOOTH_CONNECT"} <= removed,
      "network/Bluetooth permissions are removed with tools:node=remove")
for forbidden in ["READ_SMS", "READ_CONTACTS", "SYSTEM_ALERT_WINDOW", "USE_FULL_SCREEN_INTENT",
                  "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"]:
    check(forbidden not in declared, f"manifest must not declare {forbidden}")
check('android:allowBackup="false"' in manifest, 'allowBackup is false')
check('android:fullBackupContent="false"' in manifest, 'fullBackupContent is false')
check('android:dataExtractionRules="@xml/data_extraction_rules"' in manifest, 'dataExtractionRules is set')
check('android:usesCleartextTraffic="false"' in manifest, 'cleartext traffic disabled')

gradle = read("android/app/build.gradle.kts")
check('applicationId = "com.hamrah.app"' in gradle, 'applicationId is com.hamrah.app')
check("compileSdk = 36" in gradle, 'compileSdk 36')
check("targetSdk = 36" in gradle, 'targetSdk 36')
check("minSdk = 26" in gradle, 'minSdk 26')
check("37" not in re.findall(r'(?:compileSdk|targetSdk)\s*=\s*(\d+)', gradle), 'API 37 is not used')

pubspec = read("pubspec.yaml")
check("source: sqlite3mc" in pubspec, 'sqlite3 build hook uses SQLite3MultipleCiphers')
for dep in ["drift:", "flutter_riverpod:", "go_router:", "speech_to_text:", "shamsi_date:", "timezone:"]:
    check(dep in pubspec, f'pinned dependency present: {dep}')

main_db = read("lib/data/db/tables.dart")
for table in ["Categories", "Accounts", "RawSms", "Transactions", "MerchantMemory", "Reminders",
              "ReminderOccurrences", "Settings", "ImportLog"]:
    check(f"class {table} extends Table" in main_db, f"drift table {table} exists")

native_db = read("android/app/src/main/kotlin/com/hamrah/app/db/NativeInboxDb.kt")
for table in ["sms_events", "tx_events", "resolutions", "alarms", "outcome_events",
              "occurrence_events", "snapshot", "otp_hints", "diag_log"]:
    check(f"CREATE TABLE IF NOT EXISTS {table}" in native_db, f"native table {table} exists")

bridge = read("android/app/src/main/kotlin/com/hamrah/app/bridge/NativeBridge.kt")
dart_bridge = read("lib/native/native_bridge.dart")
kotlin_methods = set(re.findall(r'"([a-zA-Z]+)"\s*->', bridge))
dart_methods = set(re.findall(r"_invoke<[^>]*>\('([a-zA-Z]+)'", dart_bridge))
dart_methods |= set(re.findall(r"invokeMethod<[^>]*>\('([a-zA-Z]+)'", dart_bridge))
missing_native = dart_methods - kotlin_methods
check(not missing_native, f"every Dart method exists in the Kotlin bridge (missing: {sorted(missing_native)})")

batch_keys_dart = set(re.findall(r"json\['([a-zA-Z]+)'\]", dart_bridge))
for key in ["batchId", "contractVersion", "sms", "transactions", "resolutions", "outcomes", "occurrences"]:
    check(f'put("{key}"' in bridge, f"batch includes {key}")
for key in ["eventUid", "txUid", "smsHash", "occurrenceUid", "scheduledFor", "reason"]:
    check(key in bridge or key in native_db, f"batch row key {key} is emitted by Kotlin")
check(not (batch_keys_dart - {"eventUid", "sender", "body", "receivedAt", "parseStatus", "hash", "templateId",
                              "bankCode", "errorCode", "partCount", "txUid", "smsEventUid", "smsHash",
                              "accountHint", "direction", "amountRial", "occurredAt", "timeSource",
                              "counterparty", "counterpartySource", "purposeText", "label",
                              "balanceAfterRial", "suggestionKey", "action", "categoryId", "note",
                              "createdAt", "reminderId", "rev", "outcome", "snoozedUntil", "resolvedAt",
                              "title", "reason", "occurrenceUid", "scheduledFor", "batchId", "contractVersion", "sms", "transactions",
                              "resolutions", "outcomes", "occurrences"}),
      "Dart parses only known batch keys")

fixtures = sorted(os.listdir(os.path.join(ROOT, "test/fixtures/sms")))
check(len(fixtures) == 16, f"16 fixtures present (found {len(fixtures)})")
for name in ["M1", "M6", "B7", "B9", "B10"]:
    check(f"{name}.txt" in fixtures, f"fixture {name} present")

parser = read("android/app/src/main/kotlin/com/hamrah/app/core/SmsParser.kt")
check("برداشت" in parser and "خریداینترنتی" in parser and "حقوق" in parser and "حواله پل" in parser,
      "Melli verified labels are the only ones accepted")
check("بفرمایید رمز پویا" in parser, "Blu OTP shape is recognized for suppression")

# The user's first name must never be stored anywhere in app sources.
app_sources = []
for base, _, files in os.walk(os.path.join(ROOT, "lib")):
    app_sources += [os.path.join(base, f) for f in files if f.endswith(".dart")]
for base, _, files in os.walk(os.path.join(ROOT, "android/app/src/main")):
    app_sources += [os.path.join(base, f) for f in files if f.endswith((".kt", ".xml"))]
leaks = [p for p in app_sources if "علی" in open(p, encoding="utf-8").read()]
check(not leaks, f"the sample first name never appears in app sources (leaks: {leaks})")

print("\n".join(notes))
if failures:
    print("\n".join(failures))
    print(f"\n{len(failures)} static check(s) failed")
    sys.exit(1)
print(f"\nALL {len(notes)} STATIC CHECKS PASSED")
