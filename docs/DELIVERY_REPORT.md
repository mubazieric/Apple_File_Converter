# Delivery report — Apple File Converter

**Developed by Iwat Digital.** Flutter (Android + iOS) gallery, image converter and video
converter for Apple formats and everyday media.

---

## 1. Prior repository state

The repository `mubazieric/Apple_File_Converter` was **empty** — no commits, no files, no
`README`. Work began with a fresh `git init` on `main` and the configured `origin` remote.

## 2. Architecture

Single Flutter/Dart codebase for both platforms; Kotlin and Swift only where an OS API is
required. Layers (inward-only dependencies):

```
lib/ui, lib/state  →  lib/domain  →  (implementation)  lib/services, lib/data  →  platform channel
```

- **Domain** (`lib/domain/**`) is pure Dart with no Flutter/plugin imports, hence fully testable
  on the Dart VM: format taxonomy, conversion specs, presets, naming, metadata policy, the queue
  state machine, the signature detector and the output validator.
- **Services** (`lib/services/**`) hold the engines (pure-Dart image pipeline; FFmpeg video
  engine), the gallery adapter, storage/export, ads, and the native `MediaCodecBridge`.
- **Data** (`lib/data/**`) holds the settings, history and queue-recovery stores behind
  interfaces.
- **UI** (`lib/ui/**`, `lib/state/**`) is the screens + `ChangeNotifier` controllers.
- `lib/app/app_services.dart` is the composition root.

Decisions are recorded in eight ADRs (`docs/adr/0001`–`0008`): shared codebase, media engine
(LGPL FFmpegKit + hardware encoders), gallery access, state management, persistence, advertising,
native HEIC decode, and mandatory output validation.

## 3. What is in the repository

| Area | Files |
| --- | --- |
| Dart source (`lib/`) | 70 files, ~14.2k lines |
| Tests (`test/`) | 17 `*_test.dart` + an in-memory service helper |
| On-device test (`integration_test/`) | `app_test.dart` |
| Android native | `MainActivity.kt` (MethodChannel) |
| iOS native | `AppDelegate.swift`, `SceneDelegate.swift` (MethodChannel) |
| Docs (`docs/`) | README, architecture, 8 ADRs, feature/format matrices, dev/testing/release/limitations/troubleshooting/ads guides, privacy + licence registers, this report |
| CI (`.github/workflows/`) | `ci.yml` (format/analyze/tests/builds/secret + dependency scan), `release.yml` (signed AAB/IPA) |

## 4. Features

See `docs/FEATURE_MATRIX.md` for the full implemented / partial / deferred breakdown. In summary:

- **Gallery** — MediaStore/Photos browsing, grid/list, multi-select, full-screen viewer with
  zoom and video playback, search/filter/sort, favourites, delete, limited-access support,
  app-exports-folder duplicate detection, storage analysis.
- **Image conversion** — JPEG/PNG/WebP/GIF/BMP/TIFF/ICO encode; HEIC/HEIF/AVIF/DNG decode
  (device permitting); quality, resize, rotate/flip, watermark, metadata policy, before/after
  sizes, batch, ZIP export.
- **Video conversion** — MP4/MOV/M4V/MKV/WebM/AVI/3GP/MPEG/TS/OGV output (WMV/FLV decode-only);
  H.264/HEVC/VP8/VP9/AV1/MPEG-4/ProRes selection with hardware preference; remux-vs-transcode;
  resolution/frame-rate/bitrate; trim, rotate, speed, audio; hardware-acceleration policy.
- **Tools** — compress photos/videos, rotate & flip, strip metadata, watermark, thumbnails, trim,
  speed change, remove audio, extract audio, duplicates, storage dashboard/cleanup, history.
- **Batch engine** — queue persisted to a JSON snapshot (unfinished jobs survive a restart;
  mid-flight jobs are restored as failed), per-file + overall progress, retry, cancel,
  collision-safe naming, bounded concurrency, streaming to temp files.
- **Ads** — `AdService` with a no-op default, Google test IDs only, UMP consent, defined
  placements; **off unless compiled with `ENABLE_ADS=true`**.
- **Settings & About** — appearance, default formats/qualities, metadata, naming, export
  destination, batch defaults, delete confirmations, gallery layout, storage, ad privacy,
  localisation-ready strings, About with Iwat Digital credit and OSS licences.

## 5. Verified format support

Full matrix in `docs/FORMAT_SUPPORT.md`. Highlights:

- **Round-trip (decode + encode):** JPEG, PNG, WebP, GIF (static), BMP, TIFF, ICO.
- **Decode only:** HEIC, HEIF, AVIF, DNG (OS-dependent), WMV, FLV.
- **Unsupported / deferred:** SVG, JPEG 2000, WBMP.
- **Video codecs:** H.264 and AV1 are hardware-only (no GPL `libx264`/software AV1 in the LGPL
  build); HEVC has a bundled software fallback (`libkvazaar`); VP8/VP9/MPEG-4/ProRes available.

## 6. Test results (this workspace)

| Command | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | 0 changes needed |
| `flutter analyze --fatal-infos` | **No issues found!** |
| `flutter test` | **168 tests passed** |

Notable coverage:

- `test/services/image_conversion_engine_test.dart` — **real end-to-end** conversion: a file is
  converted and the output is verified **by signature**, corrupt input fails honestly with no
  output file, collisions create a new file.
- `test/services/image_metadata_test.dart` — the metadata policy is actually enforced: "Keep all"
  keeps EXIF+GPS, "Remove location" drops the GPS block, "Remove all" writes no EXIF.
- `test/domain/output_validation_test.dart` — renamed-extension output is rejected.
- `test/domain/format_roundtrip_test.dart` — the detector recognises real encoder output.
- `test/services/zip_exporter_test.dart` — a real ZIP (PK magic, readable entries) is produced;
  missing files are skipped and an empty request fails honestly.
- `test/domain/queue_persistence_test.dart` — a queued batch survives a real JSON round-trip;
  jobs that were mid-flight are restored as failed, never as "still running".
- `test/data/queue_store_test.dart` — the file queue store round-trips and treats a missing or
  corrupt file as an empty queue instead of throwing.
- `test/ui/app_smoke_test.dart` — the whole widget tree builds and every tab renders.
- `integration_test/app_test.dart` — the real composition root boots on a device.

## 7. Build results

| Build | Status |
| --- | --- |
| `flutter pub get` | ✅ resolved |
| `flutter analyze` / `flutter test` | ✅ (above) |
| Android debug/release build | ⛔ **Not run in this workspace** — Gradle + the native FFmpeg AAR are heavy and disk on the build host was tight; the CI `ubuntu-latest` job builds a debug APK |
| iOS build | ⛔ **Not possible on Windows** — CI `macos-14` job runs `flutter build ios --release --no-codesign` |
| Native bridge / AdMob / gallery / FFmpeg runtime | ⛔ Requires a device or emulator; implemented but not runtime-verified here |

This separation is deliberate and honest: everything runnable without a device is green, and
everything device-only is delegated to CI and manual device smoke testing
(`docs/RELEASE_CHECKLIST.md`).

## 8. Defects found and fixed during the build

- **Crash on launch (debug):** `ConversionCoordinator` (a `ChangeNotifier`) was provided with a
  plain `Provider`, which triggers an assertion in debug builds. Fixed to
  `ChangeNotifierProvider`; caught by the new widget smoke test.
- **Metadata policy was cosmetic:** the image pipeline accepted the policy but never applied it,
  so "Remove all" silently kept EXIF. Now implemented and tested.
- **Released ads would never have enabled:** the release workflow set environment variables, but
  `String.fromEnvironment` only reads `--dart-define` values. The workflow now passes the IDs as
  `--dart-define` and derives `ENABLE_ADS` from whether an ID secret exists.
- **Dead/misleading code removed:** the unused native `encodeWebp` bridge method (its comment
  wrongly claimed Dart could not encode WebP) was deleted from Dart, Kotlin and Swift.
- **Queue persistence was inert:** `ConversionQueue.toSnapshot()` / `recoverAfterRestart()` existed
  but nothing serialised a request, wrote a snapshot, or restored one at startup. The request/spec
  tree now serialises to JSON, `FileQueueStore` persists unfinished jobs, and `restoreQueue()` runs
  during bootstrap — with tests for the round-trip and the corrupt-file path.

## 9. Issues and limitations

See `docs/KNOWN_LIMITATIONS.md`. The most important:

- Deferred with **no UI shown**: crop, images→PDF, GIF creation, frame extraction, video merge,
  batch pause/resume.
- Animated GIF/WebP are reduced to a single frame; animated WebP is not produced.
- H.264/AV1 output needs a hardware encoder; if absent the job fails honestly.
- Gallery non-date sorting/search is client-side over loaded pages.
- Exporting to the system gallery keeps an app-sandbox copy on iOS (double storage).
- Image EXIF is carried for JPEG/TIFF/WebP (not PNG); ICC for JPEG/PNG/WebP.
- A restored batch re-runs unfinished jobs from scratch (no mid-file resume); jobs that were
  running when the app closed are shown as failed so the user can retry them.

## 10. AdMob setup

See `docs/ADS_SETUP.md`. Only Google **test** app/unit IDs are committed. Production IDs are
injected with `--dart-define` (or CI secrets) and `ENABLE_ADS=true`; a build with ads off makes no
ad requests. The UMP consent flow runs before any ad is requested.

## 11. How to run, test and build

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos
flutter test

flutter run                                   # device / emulator
flutter test integration_test/app_test.dart   # on-device smoke test

flutter build appbundle --release             # Play Store
flutter build ios --release --no-codesign     # macOS only
```

Full instructions: `docs/DEV_SETUP.md`, `docs/TESTING.md`, `docs/RELEASE_CHECKLIST.md`.

## 12. Prioritised remaining work

1. **Device verification** of the native bridge (HEIC decode, save-to-Photos), the video engine
   (remux + hardware encoders) and AdMob. This is the highest-value next step and cannot be done
   in this workspace.
2. **Add real media fixtures** (`test/fixtures/`, see its README) and turn on the device tests in
   CI, including HDR/VFR/rotated/corrupt cases.
3. **Implement the deferred tools** the product brief listed, one at a time, each with tests and
   the UI wired only when it works: crop, frame extraction, GIF creation, merge, images→PDF.
4. **Preserve Apple-specific data where possible**: Live Photo pairing, depth/portrait data.
5. **Server-side gallery sorting/search** to remove the loaded-page limitation.
6. **Localisation**: extract the (already localisation-ready) strings.
7. **Generate `THIRD_PARTY_NOTICES.md`** from the lockfile in CI and surface it in the About
   screen's licence view.
