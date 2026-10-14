# Troubleshooting

## Build & tooling

### `flutter analyze` fails on an info-level lint
This project is intentionally strict: every finding is an error. Run
`dart format lib test integration_test` first, then fix the remaining lint rather than
suppressing it. Do not lower `analysis_options.yaml` to get a green build.

### `flutter pub get` cannot resolve versions
You need Flutter 3.47+ / Dart 3.13+. Check with `flutter --version`, then `flutter pub upgrade
--major-versions` is **not** recommended — upgrade the SDK instead so the pinned versions keep
resolving.

### Android build fails with "unsupported class file major version"
Use JDK 17 for the Android build (`flutter config --jdk-dir <path-to-jdk17>`). Newer JDKs can
break the Android Gradle Plugin.

### Android build runs out of memory
The FFmpeg AAR makes the build heavy. Add to `android/gradle.properties`:
`org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g` and avoid running the build and the test
suite simultaneously.

### Gradle cannot download the FFmpeg artifact
`ffmpeg_kit_flutter_new_full` fetches a native package from a Maven repository. Ensure the
machine is online for the **first** build (the app itself is offline at runtime) and that no
proxy blocks `mavenCentral`/the FFmpegKit repository.

### iOS `pod install` fails
Run `cd ios && pod repo update && pod install`. On a fresh machine also run
`sudo xcode-select --switch /Applications/Xcode.app`. iOS builds require macOS; there is no
Windows workaround.

### "No iOS devices/emulators" on Windows
Expected. iOS is validated in CI on `macos-14`. Use an Android device/emulator or a physical
iPhone via a Mac for local iOS testing.

## Runtime

### The gallery is empty or says "Gallery unavailable"
- Ensure the permission was granted. The app asks lazily, at the point of need; if you denied it
  once, re-open the permission from the prompt (or the App Settings deep link shown in the app).
- On Android 14 / iOS 14+ with "limited" access, only the selected items are visible; use the
  in-app "Choose more photos" action.
- On Linux/Windows desktop the gallery is not implemented; the app shows an honest empty state.

### HEIC/HEIF files fail to convert with "unsupported on this device"
The device's OS cannot decode them. This needs Android API 28+ or a reasonably recent iOS. The
message is accurate — there is no Dart HEIC decoder.

### Video conversion fails with "no hardware encoder"
The requested codec has no hardware encoder on this device. H.264 and AV1 are hardware-only in
this build. Choose H.265 (software fallback available), VP8/VP9, or MPEG-4.

### A conversion "succeeds" but the file will not play
It should not — outputs are validated before success is reported (signature, container,
dimensions, duration, streams). If you see this, capture the app version, the input format and
the settings, and open an issue. The validator intentionally rejects renamed-extension output.

### Storage looks like it doubled after exporting to Photos
This is a known limitation: on iOS the app cannot delete its sandbox copy after saving into
Photos, so both copies exist. See `docs/KNOWN_LIMITATIONS.md`.

### Ads do not appear
Ads are off unless the build was compiled with `--dart-define=ENABLE_ADS=true`. With production
IDs in a debug build, Google may serve no-fill; use test IDs during development. If ads are on and
still absent, complete the consent form (Settings → Advertising → Ad privacy). See
`docs/ADS_SETUP.md`.

### The app imports a photo but the output keeps the wrong date or location
Check the metadata policy. The default is "Remove location". "Remove all" writes no EXIF. The
policy is applied to the output, and this is verified by tests.

## Tests

### Tests fail with a Windows temp-directory error
Some engine tests create temp files under the system temp directory. Ensure the drive has free
space and that antivirus is not locking files. The tests clean up after themselves; a failure is
reported, not swallowed.

### An engine test passes locally but not under `flutter test` in CI
Engine tests use `Isolate.run`. Very constrained CI runners may be slow to start isolates; the
default timeout is generous. If a specific machine is flaky, re-run once before investigating.

### I added a media fixture and the suite still skips it
Fixture tests skip when the file is absent *by design*, so a clean checkout passes. Confirm the
file is in `test/fixtures/` with the exact expected name (see `docs/TESTING.md`).
