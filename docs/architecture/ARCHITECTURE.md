# Architecture — Apple File Converter

> Developed by **Iwat Digital**. This document describes the shipped architecture of the
> application. It is a living document; see `docs/adr/` for the decisions behind it.

## 1. Goals and constraints

| Goal | Consequence for the architecture |
| --- | --- |
| Identical feature set on Android and iOS | Single Flutter/Dart codebase, platform behaviour behind interfaces |
| Real (not simulated) conversion | A conversion engine that runs native codecs and validates outputs |
| Offline-first, privacy-first | All processing on-device; no backend; no media leaves the device |
| Responsive UI during long jobs | Work runs in isolates / native worker threads; UI only observes progress |
| Apple formats (HEIC/HEIF/MOV/HEVC) must work | Native ImageIO/ImageDecoder decode + hardware HEVC paths |
| LGPL-clean, shippable | `ffmpeg_kit_flutter_new_full` (no GPL codecs); hardware H.264/HEVC encoders |

## 2. Layering

```
┌───────────────────────────────────────────────────────────────┐
│ presentation  lib/ui/screens/**            (screens)           │
│               lib/ui/widgets/**            (shared widgets)    │
├───────────────────────────────────────────────────────────────┤
│ application   lib/state/**               (ChangeNotifier)     │
│               lib/domain/**              (pure logic, testable)│
├───────────────────────────────────────────────────────────────┤
│ infrastructure lib/services/**           (engines, platform)  │
│               lib/data/**                (repos, persistence) │
├───────────────────────────────────────────────────────────────┤
│ platform      android/** Kotlin, ios/** Swift, MethodChannels │
└───────────────────────────────────────────────────────────────┘
```

The dependency rule is **inward only**: `presentation → application → domain`.
`domain` has no Flutter, plugin or platform imports and is therefore fully unit-testable on
the Dart VM. `services` implement interfaces declared in `domain`.

## 3. Modules

| Module | Responsibility | Key types |
| --- | --- | --- |
| `domain/media` | Media model + format taxonomy + capability matrix | `MediaItem`, `MediaKind`, `ImageFormat`, `VideoContainer`, `FormatCapability` |
| `domain/format` | Signature-based format detection | `FormatDetector`, `DetectedFormat` |
| `domain/conversion` | Conversion request/spec, presets, naming, metadata policy, result validation | `ConversionRequest`, `ImageConversionSpec`, `VideoConversionSpec`, `NamingPolicy`, `MetadataPolicy`, `OutputValidator`, `OutputProbe`, `OutputExpectation` |
| `domain/queue` | Queue state machine + batch orchestration rules | `ConversionJob`, `JobStatus`, `ConversionQueue`, `QueueStats` |
| `domain/history` | Converted-file record model | `ConversionRecord` |
| `domain/settings` | Persisted preferences model + defaults | `AppSettings`, `ThemePreference`, `ExportDestination` |
| `services/conversion` | Engine selection, command building, probing, execution | `ImageConversionEngine`, `VideoConversionEngine`, `FfmpegCommandBuilder`, `FfmpegRunner`, `MediaProbe`, `ConversionCoordinator` |
| `services/gallery` | Device media access | `GalleryService`, `PhotoManagerGalleryService`, `UnsupportedGalleryService` |
| `services/storage` | Storage stats, temp cleanup, duplicate scan | `StorageService`, `AppStorageService`, `DuplicateGroup` |
| `services/export` | Move a validated output to its final destination | `OutputExporter`, `DeviceOutputExporter`, `PassthroughExporter` |
| `services/ads` | AdMob + UMP consent, optional | `AdService`, `AdMobAdService`, `NoOpAdService`, `AdUnitIds` |
| `services/platform` | Native channel + platform detection | `MediaCodecBridge`, `PlatformInfo` |
| `data` | Persistence behind interfaces | `SettingsStore`/`SharedPreferencesSettingsStore`, `HistoryStore`/`SqliteHistoryStore` |

`lib/state/**` holds the `ChangeNotifier` controllers (`SettingsController`,
`GalleryController`, `ConversionController`, `ShellController`) and `lib/ui/**` holds the screens,
theme and shared widgets. `lib/app/app_services.dart` is the composition root.

## 4. Processing model

* **Image pipeline** — pure-Dart `image` package inside a worker isolate (`Isolate.run` per
  job with bounded concurrency). Decode → optional transform (resize/rotate/flip/watermark →
  metadata policy) → encode → `OutputValidator`. HEIC/HEIF/AVIF/DNG decode is delegated to the
  native bridge first (Android `ImageDecoder`, iOS `ImageIO`), returning raw pixels, then the
  same Dart pipeline runs.
* **Video pipeline** — FFmpeg sessions via `ffmpeg_kit_flutter_new_full`. The engine never
  assumes codec availability: `MediaProbe` (via `FFprobeKit`) inspects the input, and
  `VideoCapability` decides remux (stream copy) vs transcode. Hardware encoders
  (`h264_mediacodec`/`hevc_mediacodec` on Android, `h264_videotoolbox`/`hevc_videotoolbox` on
  iOS) are preferred; software fallbacks are used only where the bundled build provides them.

## 5. Concurrency and resource bounds

* A `ConversionQueue` owns at most `maxConcurrentJobs` running jobs. The default is derived
  from `device_info_plus` (2 on low-RAM devices, up to `min(cores, 4)` otherwise).
* Jobs stream to temp files; full-resolution buffers are never held for a whole batch.
* Cancellation is cooperative and honest: a job that cannot resume from a partial output
  reports `JobStatus.cancelled` and restarts from scratch if retried.
* The batch queue is persisted (job request + status, never media bytes) as a JSON file so an
  interrupted batch is not lost. Queued jobs resume on the next launch; jobs that were mid-flight
  are restored as failed (`Interrupted`) — never shown as still running. Only unfinished jobs are
  written, because completed work lives in the conversion history.

## 6. Security and privacy

* No network access except the ad/consent SDKs and the optional placeholder info links.
* No analytics. No media, file name or EXIF value is ever sent to an ad or analytics SDK.
* Temp artefacts live under the app cache directory and are swept on launch and on demand.
* Filenames are sanitised; export paths are confined to app-controlled or user-picked roots.
* Secrets: only Google *test* ad IDs are committed; production IDs are injected at build time.

## 7. Testing strategy

| Layer | Tool | Examples |
| --- | --- | --- |
| domain unit | `flutter_test` | format detection, naming/collision, metadata policy, queue transitions, storage maths |
| service unit | `flutter_test` + fakes | coordinator engine selection, validation, error mapping |
| widget | `flutter_test` | navigation, theme switching, format selector, empty/error states |
| integration | `integration_test` | convert a fixture, validate output, cancel, retry |
| static | `flutter analyze`, `dart format --set-exit-if-changed` | CI gate |
