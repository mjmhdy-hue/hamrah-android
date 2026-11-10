# همراه (Hamrah)

Offline-first Android app: bank SMS → parsed, deduplicated, categorized transactions + Jalali-native
reminders. Flutter UI (RTL, Vazirmatn, Persian digits) over a Kotlin background layer. No backend, no
INTERNET permission in the release manifest, both databases encrypted.

- **Build & run (Windows):** [`docs/README.md`](docs/README.md)
- **Architecture, data model, contract:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **What was executed and what was not:** [`docs/TEST_REPORT.md`](docs/TEST_REPORT.md)
- **Scope cuts and unverified behaviour:** [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md)
- **Privacy / encryption / manifest:** [`docs/SECURITY.md`](docs/SECURITY.md)
- **Raw evidence logs:** [`docs/evidence/`](docs/evidence/)

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze ; flutter test
flutter build apk --release
```

> No APK ships with this delivery: the build host is aarch64 Linux without a Flutter/Android SDK.
