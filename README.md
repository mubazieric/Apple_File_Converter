# Apple File Converter

> Gallery, image converter and video converter for Apple formats and everyday media.
> **Developed by Iwat Digital.**

Apple File Converter is a Flutter (Android + iOS) application that views, converts and
compresses the photos and videos already on your device. It is built around one hard rule:
**it does real work or it says it cannot.** No fake progress bars, no renamed-extension
"conversions", no buttons that imply a feature that is not wired up.

Everything runs **on-device**. No media, file name, EXIF value or frame is ever uploaded.

---

## Highlights

- **Gallery** — browse photos and videos from MediaStore (Android) / Photos (iOS), grid or
  list, search, filter, sort, favourites, multi-select, full-screen viewer with pinch/double-tap
  zoom for images and playback for video.
- **Image conversion** — JPEG, PNG, WebP, GIF, BMP, TIFF, ICO (encode); HEIC/HEIF, AVIF, DNG
  (decode, device permitting). Resize, rotate/flip, quality control, metadata stripping, text
  watermark, batch, ZIP export, before/after sizes.
- **Video conversion** — MP4/MOV/M4V/MKV/WebM/AVI/3GP and more as containers; H.264, H.265/HEVC,
  VP8/VP9, AV1, MPEG-4, ProRes as codecs (subject to device encoders). Safe **remux** (stream
  copy) vs **transcode**, resolution/frame-rate/bitrate control, trim, rotate, speed, audio
  tracks, hardware acceleration.
- **Tools** — batch compress, rotate/flip, strip metadata, text watermark, make thumbnails,
  trim video, change speed, remove/extract audio, storage dashboard, conversion history,
  duplicate finder, temp cleanup.
- **Batch engine** — a persistent queue with per-file and overall progress, retry, cancel,
  resume of unfinished jobs after a process kill (mid-flight jobs are marked failed),
  collision-safe naming and bounded concurrency.
- **Honest validation** — every output is re-opened and checked (signature, container,
  dimensions, duration, streams) before it is reported as a success.

## Status

| Area | State |
| --- | --- |
| Shared Dart domain, engines, queue, UI | Implemented and unit/widget tested |
| Android native channel (HEIC decode, MediaStore save, HW encoder probe) | Implemented (not runtime-verified in this workspace) |
| iOS native channel (ImageIO decode, Photos save, VideoToolbox probe) | Implemented; CI build job configured (not yet run) |
| AdMob + UMP | Implemented behind a flag, **off by default** |
| Image/video conversion end-to-end on device | Requires a device build (see *Testing*) |

See `docs/KNOWN_LIMITATIONS.md` for the exact list of what is deferred and why.

## Documentation map

| Document | Contents |
| --- | --- |
| `docs/architecture/ARCHITECTURE.md` | Layering, modules, processing model |
| `docs/DELIVERY_REPORT.md` | Final delivery report: state, features, tests, builds, remaining work |
| `docs/FEATURE_MATRIX.md` | Every feature with implemented / tested / partial / deferred status |
| `docs/FORMAT_SUPPORT.md` | Per-format capability matrix (view / decode / encode) |
| `docs/DEV_SETUP.md` | Exact commands to run on Windows, macOS, Android and iOS |
| `docs/TESTING.md` | How to run the tests and how to add media fixtures |
| `docs/RELEASE_CHECKLIST.md` | Store-submission checklist |
| `docs/KNOWN_LIMITATIONS.md` | Honest list of gaps and platform limits |
| `docs/TROUBLESHOOTING.md` | Build and runtime problems |
| `docs/ADS_SETUP.md` | AdMob unit IDs, UMP consent, enabling ads |
| `docs/legal/PRIVACY_AND_PERMISSIONS.md` | Privacy posture and permission rationale |
| `docs/legal/LICENCE_REGISTER.md` | Third-party dependency register |
| `docs/adr/` | Architecture Decision Records 0001–0008 |

## Quick start

```bash
# Requirements: Flutter 3.47+ (Dart 3.13+), Android SDK / Xcode.
flutter pub get
flutter analyze                 # must be clean (zero issues)
flutter test                    # unit + widget tests
flutter run                     # on a connected device or emulator
```

Full instructions, including iOS and release builds, are in `docs/DEV_SETUP.md`.

## Privacy in one paragraph

The app processes media locally and keeps originals untouched. The only optional network
component is Google AdMob, which is compiled out unless you explicitly enable it and supply
your own unit IDs. When ads are enabled, Google's UMP consent flow runs first, and no media or
metadata is ever shared with any ad network. See `docs/legal/PRIVACY_AND_PERMISSIONS.md`.

## Licence

Application code © Iwat Digital. Third-party dependencies retain their own licences; the full
register is in `docs/legal/LICENCE_REGISTER.md`. The media engine is the **LGPL** FFmpegKit
distribution with no GPL codecs (see ADR 0002).
