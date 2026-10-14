# Feature matrix

Status values:

- **Implemented** — the feature does real work and is reachable in the UI.
- **Partial** — works, but with a documented platform or scope limit.
- **Deferred** — deliberately not shipped; **no UI implies otherwise.**

"Tested" means covered by an automated test in `test/` or `integration_test/`. Features that
require a device are marked *device* — validated by the CI device jobs, not by `flutter test`.

## Navigation & shell

| Feature | Status | Tested | Notes |
| --- | --- | --- | --- |
| Bottom navigation: Home, Gallery, Convert, Tools, Settings | Implemented | widget | `test/ui/app_smoke_test.dart` |
| Dark / light / system theme | Implemented | widget | Persisted in settings |
| Responsive / tablet layout | Implemented | – | Width-driven layouts |
| Conversion mini-bar above the nav bar | Implemented | – | Shows active batch progress |

## Gallery

| Feature | Status | Tested | Notes |
| --- | --- | --- | --- |
| MediaStore (Android) / Photos (iOS) browsing | Implemented | device | `photo_manager` |
| Least-privilege, lazy permission requests | Implemented | unit | ADR 0003 |
| Grid / list layout | Implemented | widget | |
| Search, filter (photos/videos/favourites), sort | Partial | unit | Name/size/format/duration sort is client-side over loaded pages |
| Multi-select and batch hand-off | Implemented | widget | |
| Full-screen image viewer (pinch + double-tap zoom, swipe) | Implemented | – | `photo_view` |
| Video playback (full-screen) | Implemented | device | `video_player` |
| Favourites toggle | Implemented | – | Native favourite where supported |
| Delete with confirmation | Implemented | – | Never deletes originals on convert |
| Limited-access picker (iOS / Android 14) | Implemented | device | |
| Duplicate detection | Partial | unit | Scans the **app exports folder only** |
| Storage analysis | Implemented | unit | Per-category sizes, unknown shown honestly |

## Image conversion

| Feature | Status | Tested | Notes |
| --- | --- | --- | --- |
| Format selection (JPEG/PNG/WebP/GIF/BMP/TIFF/ICO) | Implemented | unit | Capability-driven |
| HEIC/HEIF/AVIF/DNG decode → JPEG/PNG/WebP | Implemented | device | Native decode + Dart pipeline |
| Quality control | Implemented | unit | |
| Resize (presets + custom dimensions) | Implemented | unit | |
| Rotate / flip | Implemented | unit | EXIF orientation honoured |
| Metadata strip / keep | Implemented | unit | GPS strip by default |
| Transparency warning before lossy JPEG | Implemented | – | |
| Text watermark | Implemented | unit | |
| Before/after size display | Implemented | unit | |
| ZIP batch export | Implemented | unit | `zip_exporter_test.dart`; "Share all as ZIP" in the batch queue |
| Crop | Deferred | – | No button is shown |

## Video conversion

| Feature | Status | Tested | Notes |
| --- | --- | --- | --- |
| Container selection | Implemented | unit | |
| Codec selection (H.264/HEVC/VP8/VP9/AV1/MPEG-4/ProRes) | Implemented | unit | Hardware-first, honest failure |
| Remux vs transcode decision | Implemented | unit | Refuses impossible remux |
| Resolution / frame rate / bitrate | Implemented | unit | |
| Trim start/end | Implemented | unit | |
| Rotate | Implemented | unit | |
| Speed change (0.5×–4×) | Implemented | unit | |
| Keep / remove audio | Implemented | unit | |
| Hardware acceleration (auto / require) | Implemented | unit | |
| Output validation (signature/streams/duration) | Implemented | unit | ADR 0008 |

## Tools

| Tool | Status | Tested | Notes |
| --- | --- | --- | --- |
| Compress photos | Implemented | – | Studio preset |
| Compress videos | Implemented | – | Studio preset |
| Rotate & flip | Implemented | unit | |
| Remove metadata | Implemented | unit | |
| Add watermark | Implemented | unit | |
| Make thumbnails | Implemented | – | Downscale preset |
| Trim video | Implemented | unit | |
| Change speed | Implemented | unit | |
| Remove audio | Implemented | unit | |
| Extract audio | Implemented | – | Audio-only preset |
| Find duplicates | Implemented | unit | App exports folder only |
| Storage dashboard / temp cleanup | Implemented | unit | |
| Conversion history | Implemented | unit | |
| Images → PDF | Deferred | – | Engine not implemented; no button |
| GIF creation | Deferred | – | No button |
| Frame extraction | Deferred | – | No button |
| Video merge | Deferred | – | No button |

## Batch engine

| Feature | Status | Tested | Notes |
| --- | --- | --- | --- |
| Persistent queue with states | Implemented | unit | `ConversionQueue` + `FileQueueStore` (JSON snapshot) |
| Per-file + overall progress | Implemented | – | |
| Retry (one / all failed) | Implemented | unit | |
| Cancel (one / all) | Implemented | unit | Cooperative |
| Pause / resume | Deferred | – | Not genuinely supported; cancel/retry offered instead |
| Collision-safe naming | Implemented | unit | `NamingPolicy` |
| Recovery after process kill | Implemented | unit | Queued jobs resume; mid-flight jobs restored as failed |
| Bounded concurrency | Implemented | unit | Device-derived default |
| Streaming to temp files | Implemented | – | No full-batch buffering |

## Ads & privacy

| Feature | Status | Tested | Notes |
| --- | --- | --- | --- |
| AdService abstraction + NoOp default | Implemented | unit | Ads off unless compiled in |
| Google test IDs committed only | Implemented | – | Production via `--dart-define` |
| UMP consent flow | Implemented | device | |
| Banner / native placements | Implemented | – | Never over a running conversion |
| Rewarded / interstitial plumbing | Partial | – | Only requested at defined placements |

## Platform & settings

| Feature | Status | Tested | Notes |
| --- | --- | --- | --- |
| Settings persistence (corruption-safe) | Implemented | unit | `shared_preferences` |
| Default image/video formats & quality | Implemented | unit | |
| Export destination (gallery / app folder / custom) | Implemented | – | |
| Batch concurrency, delete confirmations, gallery layout | Implemented | unit | |
| Ad-privacy status shown in Settings | Implemented | – | |
| Language architecture (English initial) | Implemented | – | Localisation-ready strings |
| About screen, licences, Iwat Digital credit | Implemented | – | |
