# همراه (Hamrah)

Offline-first Android app that turns bank SMS into categorized transactions and runs Jalali
reminders natively. Flutter UI (RTL, Vazirmatn, Persian digits) + Kotlin background layer.
No backend, no INTERNET permission in the release manifest, both databases encrypted.

> **وضعیت این نسخه:** کد کامل پروژه در این پوشه است، اما APK در این محیط ساخته نشده
> (جزئیات در `docs/TEST_REPORT.md`). روی ویندوز با دستورهای زیر بسازید.

## Build on Windows (PowerShell)

Prerequisites: Flutter stable (Dart >= 3.9), JDK 17, Android SDK with **platform 36** and
**build-tools 36**, a device/emulator with Android 8.0+ (API 26).

```powershell
flutter doctor -v                     # must be green for Android toolchain
cd <this folder>
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates lib/data/db/app_db.g.dart
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release --split-per-abi      # only if android\key.properties exists
```

Verify the release manifest (must NOT contain INTERNET / READ_SMS):

```powershell
& "$env:ANDROID_HOME\build-tools\36.0.0\aapt2.exe" dump permissions build\app\outputs\flutter-apk\app-release.apk
```

Install and smoke test:

```powershell
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb emu sms send 9830009417 "ASCII smoke test"     # emulator only, ASCII
adb shell dumpsys alarm | Select-String "com.hamrah.app"
adb reboot                                          # after unlock: alarms restored, Diagnostics shows it
```

`flutter pub get` must resolve `sqlite3` with the `sqlite3mc` build hook (`hooks:` section in
`pubspec.yaml`); the app asserts `PRAGMA cipher` at runtime and refuses to open the DB without it.

## Release signing

```powershell
keytool -genkey -v -keystore android\app\hamrah-release.jks -keyalg RSA -keysize 2048 `
  -validity 10000 -alias hamrah
```

Create `android\key.properties` (never commit it):

```properties
storePassword=...
keyPassword=...
keyAlias=hamrah
storeFile=hamrah-release.jks
```

Back up the keystore **and** `key.properties`: without them you cannot update an installed app.

## What the app does

- **دریافت پیامک بانک → تراکنش:** receiver نیتیو (بدون Flutter)، فقط فرستنده‌های تأییدشده،
  نرمال‌سازی فارسی/عربی، دو قالب تأییدشدهٔ بانک ملی و بلو، حذف تکراری با SHA-256، مسدودسازی
  پیامک رمز پویا، اعلان heads-up با دو پیشنهاد دسته و «بعداً»، دسته‌بندی با لمس یا صدا.
- **یادآور:** عنوان متنی/صوتی، تاریخ و ساعت شمسی، آلارم نیتیو، ۰–۲ یادآوری دوباره، تعویق ۱۰
  دقیقه، «فردا»، انتقال خودکار پایان روز، بازیابی آلارم‌ها بعد از ری‌استارت.
- **مالی:** ماندهٔ اعلامی بانک، تشخیص اختلاف مانده، جست‌وجو، حذف نرم، حافظهٔ دستهٔ فروشنده.

## Docs

- `docs/ARCHITECTURE.md` — ownership, contract, keys, database schema, alarm semantics.
- `docs/TEST_REPORT.md` — every check with TESTED / PARTIALLY TESTED / UNVERIFIED.
- `docs/LIMITATIONS.md` — what is deliberately out of scope and what was not verifiable here.
- `docs/SECURITY.md` — threat model and PII rules.
