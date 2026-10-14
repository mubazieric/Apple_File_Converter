# ADR 0007 — HEIC/HEIF decode via native bridge, then the shared Dart pipeline

* Status: Accepted
* Date: 2026-10-13

## Context

HEIC/HEIF is the headline format. Flutter's own image decoding does not reliably support it,
and the pure-Dart `image` package does not decode HEIF. Android decodes HEIC natively from API
28 (`ImageDecoder`); iOS/macOS decode it natively via ImageIO. The bundled FFmpeg build does not
include libheif, so FFmpeg is not the right tool for single images here.

## Decision

Implement a small `MediaCodecBridge` `MethodChannel`:

* `decodeHeic(bytes) → raw ARGB + width/height/orientation` on both platforms:
  * Android: `ImageDecoder` (API 28+) with a `BitmapFactory` fallback for older devices and a
    clear `UNSUPPORTED` error when neither can decode.
  * iOS: `CGImageSourceCreateWithData` → `CGImage` → pixel buffer.
* `probeImage(bytes) → {format, width, height, hasAlpha, orientation}`.
* `saveToPhotoLibrary(path, kind)` for Android MediaStore inserts and iOS Photos writes.

Once decoded to raw pixels, HEIC is just another source for the **shared** Dart transform +
encode pipeline, so HEIC→JPEG, HEIC→PNG and HEIC→WebP all reuse one code path and one set of
tests.

## Consequences

* We must keep raw-pixel memory bounded: the bridge rejects images above a configurable
  megapixel ceiling with a clear error instead of OOM-ing.
* On devices/OS versions that cannot decode HEIC, the app reports "viewing not supported on
  this device" rather than pretending the conversion worked.
* HEIF *containers* with unsupported codecs (e.g. AV1-in-HEIF) surface as `UNSUPPORTED`.
