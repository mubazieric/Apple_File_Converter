# Development setup

## 1. Prerequisites

| Tool | Version used to build this project |
| --- | --- |
| Flutter | 3.47.7 (stable) |
| Dart | 3.13.5 |
| Android SDK | compileSdk/targetSdk from the Flutter defaults; minSdk = Flutter default (24) |
| Xcode | 15+ (iOS builds require macOS) |
| JDK | 17 (Android Gradle plugin) |

Check your toolchain:

```bash
flutter --version
flutter doctor -v
```

> On Windows, if Flutter is not on `PATH`, prefix commands with
> `$env:Path = "C:\flutter\bin;" + $env:Path` in PowerShell, or call
> `C:\flutter\bin\flutter.bat`.

## 2. Get the code and dependencies

```bash
git clone https://github.com/mubazieric/Apple_File_Converter.git
cd Apple_File_Converter
flutter pub get
```

`flutter pub get` pulls the shared Dart dependencies plus the platform plugins
(`photo_manager`, `ffmpeg_kit_flutter_new_full`, `google_mobile_ads`, …). See
`docs/legal/LICENCE_REGISTER.md` for the full list and licences.

## 3. Run the static checks and tests

```bash
dart format --set-exit-if-changed lib test integration_test
flutter analyze          # must print "No issues found!"
flutter test             # unit + widget tests
```

`flutter analyze` is strict here: **any** issue (including info-level lints) fails the build.
Do not merge a change that is not format-clean and analyze-clean.

## 4. Run on a device

```bash
flutter devices
flutter run                    # debug build on the selected device
flutter run -d <device-id>
```

Debug builds use Google **test** ad IDs and have ads disabled unless you opt in (see
`docs/ADS_SETUP.md`).

## 5. Android build

```bash
flutter build apk --debug                 # quick sanity build
flutter build appbundle --release         # Play Store bundle (AAB)
flutter build apk --release --split-per-abi
```

Release signing is **not** committed. Configure it with `android/key.properties` (see
`android/key.properties.example` if present) or pass the values from CI secrets. Never commit a
keystore or its passwords.

## 6. iOS build (macOS only)

```bash
cd ios && pod install && cd ..
flutter build ios --release --no-codesign  # compile validation without signing
open ios/Runner.xcworkspace                # archive/upload from Xcode
```

iOS builds cannot be produced on Windows; use the `macos-14` job in
`.github/workflows/ci.yml`.

## 7. Enabling ads (optional)

Ads are compiled out by default. To build with ads enabled, provide your own IDs:

```bash
flutter build appbundle --release \
  --dart-define=ENABLE_ADS=true \
  --dart-define=ADMOB_ANDROID_BANNER=ca-app-pub-XXXXXXXX/YYYY \
  --dart-define=ADMOB_ANDROID_NATIVE=ca-app-pub-XXXXXXXX/YYYY \
  --dart-define=ADMOB_ANDROID_INTERSTITIAL=ca-app-pub-XXXXXXXX/YYYY \
  --dart-define=ADMOB_ANDROID_REWARDED=ca-app-pub-XXXXXXXX/YYYY
```

Full details, including the iOS keys and the required `Info.plist`/manifest app IDs, are in
`docs/ADS_SETUP.md`.

## 8. Project layout

```
lib/
  app/            composition root + MaterialApp
  core/utils/     formatting/maths helpers
  domain/         pure logic (no Flutter/plugins): formats, specs, queue, validation
  data/           persistence behind interfaces (settings, history, queue recovery)
  services/       engines, gallery, storage, export, ads, platform bridge
  state/          ChangeNotifier controllers
  ui/             screens, theme, widgets
android/          Kotlin host (MethodChannel)
ios/              Swift host (MethodChannel)
test/             unit + widget tests
integration_test/ on-device smoke test
docs/             this documentation set + ADRs
```

Architecture rules and rationale are in `docs/architecture/ARCHITECTURE.md` and `docs/adr/`.
