# ADR 0002 — Media processing engines: pure-Dart images + LGPL FFmpeg + native codecs

* Status: Accepted
* Date: 2026-10-13

## Context

The app must perform genuine encoding/decoding for images and video, on Android and iOS, with a
licence that permits closed-source distribution. The prompt explicitly forbids using the
retired original `ffmpeg-kit` distribution as a new production dependency.

Three broad options exist:

1. Pure-Dart codecs (the `image` package) — no native code, identical on both platforms, but
   limited to a fixed set of image formats and not suitable for video.
2. A maintained FFmpeg Flutter distribution — broad container/codec coverage, but a licence
   and binary-size decision.
3. Native platform APIs — best performance and power characteristics, but two implementations.

## Decision

Use **all three, layered by task**:

* **Images** — the pure-Dart `image` package for JPEG, PNG, WebP, GIF, BMP, TIFF, ICO, and
  (best-effort) AVIF decoding. This guarantees byte-identical behaviour on both platforms and
  is directly unit-testable with fixtures. HEIC/HEIF decode is delegated to native
  `ImageDecoder`/`ImageIO` (see ADR 0007).
* **Video** — `ffmpeg_kit_flutter_new_full` (maintained fork, FFmpeg 8.1.x, **LGPL variant with
  no GPL codecs**). Hardware H.264/HEVC encoders (`*_mediacodec`, `*_videotoolbox`) are
  preferred, so the LGPL build still produces the default H.264/MP4 compatibility output.
* **Remux** — where container-only changes are required, streams are copied (`-c copy`) rather
  than re-encoded.

## Licence analysis (summary, full detail in the licence register)

| Component | Licence | Obligation |
| --- | --- | --- |
| Our application | Proprietary | — |
| `ffmpeg_kit_flutter_new_full` plugin | LGPL-3.0 | Provide licence text + attribution; allow relinking (shipped as separate shared libraries) |
| FFmpeg core | LGPL-2.1+ | Same |
| Bundled LGPL libs (vpx, dav1d, opus, lame, …) | LGPL/BSD-style | Attribution; patent notes |
| **No** x264/x265/xvid/vid.stab | (avoided) | We do **not** take on GPL obligations |

We deliberately do **not** use the `ffmpeg_kit_flutter_new` "Full GPL" package; the default
H.264/HEVC output comes from hardware encoders, which keeps the app LGPL-distributable.

## Consequences

* Video conversion coverage on a given device depends on hardware encoders and the bundled
  LGPL decoders; the capability matrix documents this honestly.
* Image conversion is fast to test in CI (no device needed) and identical cross-platform.
* We ship a licence register and in-app open-source notices.
