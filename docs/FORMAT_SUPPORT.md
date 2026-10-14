# Format support matrix

This matrix is the single source of truth for what the shipped build can actually do. It is
derived directly from `ImageFormat.capabilityFor`, `VideoContainer.capabilityFor` and the
engine implementations — the UI reads the same data, so nothing can be advertised here that the
engine cannot perform.

Legend: **V** = view in the app, **D** = decode, **E** = encode (produce as output).

## Images

| Format | V | D | E | Notes |
| --- | :-: | :-: | :-: | --- |
| JPEG / JPG | ✅ | ✅ | ✅ | Default output. Alpha is flattened onto white (user is warned). |
| PNG | ✅ | ✅ | ✅ | Lossless, alpha preserved. |
| WebP | ✅ | ✅ | ✅ | Pure-Dart codec on both platforms (static images). |
| GIF | ✅ | ✅ | ✅ | First frame only for animated sources (see limitations). |
| BMP | ✅ | ✅ | ✅ | |
| TIFF | ✅ | ✅ | ✅ | |
| ICO | ✅ | ✅ | ✅ | |
| HEIC | ✅ | ✅ | ⛔ | Decode via native stack (Android `ImageDecoder` API 28+, iOS `ImageIO`). Not encodable. |
| HEIF | ✅ | ✅ | ⛔ | As HEIC. |
| AVIF | ⚠️ | ⚠️ | ⛔ | Decode depends on the OS stack (Android 12+, iOS 16+). |
| DNG / RAW | ⚠️ | ⚠️ | ⛔ | iOS only, when the device supports it. |
| SVG | ⛔ | ⛔ | ⛔ | Rasterisation deferred. |
| JPEG 2000 | ⛔ | ⛔ | ⛔ | Not shipped. |
| WBMP | ⛔ | ⛔ | ⛔ | Not supported by the engine (deferred). |

## Video containers

| Container | V | D | E | Notes |
| --- | :-: | :-: | :-: | --- |
| MP4 | ✅ | ✅ | ✅ | Default output. |
| MOV | ✅ | ✅ | ✅ | |
| M4V | ✅ | ✅ | ✅ | |
| MKV | ✅ | ✅ | ✅ | Output depends on the selected codecs. |
| WebM | ✅ | ✅ | ✅ | VP8/VP9/AV1 + Opus/Vorbis. |
| AVI | ✅ | ✅ | ✅ | |
| 3GP | ✅ | ✅ | ✅ | |
| MPEG / MPG | ✅ | ✅ | ✅ | |
| TS / MTS / M2TS | ✅ | ✅ | ✅ | |
| OGV | ✅ | ✅ | ✅ | |
| WMV | ✅ | ✅ | ⛔ | Decode only — no WMV muxer is shipped. |
| FLV | ✅ | ✅ | ⛔ | Decode only. |

## Video codecs

Encoder selection prefers hardware, then a bundled software encoder where one exists. The
shipped FFmpeg build is **LGPL** and therefore contains **no software H.264 encoder** (no
`libx264`) and **no software AV1 encoder**.

| Codec | Android | iOS | Notes |
| --- | --- | --- | --- |
| H.264 / AVC | `h264_mediacodec` | `h264_videotoolbox` | **Hardware only.** Fails honestly if unavailable. |
| H.265 / HEVC | `hevc_mediacodec` | `hevc_videotoolbox` | Software fallback `libkvazaar` is bundled. |
| VP8 | `libvpx` (software) | `libvpx` (software) | |
| VP9 | `vp9_mediacodec` → `libvpx-vp9` | `vp9_videotoolbox` → `libvpx-vp9` | |
| AV1 | `av1_mediacodec` (hardware only) | `av1_videotoolbox` (hardware only) | No software AV1 encoder shipped. |
| MPEG-4 Part 2 | `mpeg4` (software) | `mpeg4` (software) | |
| ProRes | ⛔ | `prores_videotoolbox` → `prores_ks` | Apple-only. |

## Audio codecs

| Codec | Notes |
| --- | --- |
| AAC | Default for MP4/MOV/M4V/MKV/3GP. |
| MP3 | |
| Opus | Default for WebM/OGV. |
| Vorbis | |
| PCM | |

## Capability resolution rules

- **Remux (stream copy) is preferred** only when the target container can legally carry the
  source codec; otherwise the engine transcodes. A remux that the container cannot carry is
  refused rather than producing a broken file.
- **H.264 output requires a hardware encoder.** If none exists, the job fails with
  `encoderUnavailable` and an actionable message instead of silently producing a bad file.
- **HEIC/HEIF/AVIF/DNG are decode-only.** Apple does not expose a supported HEIC encoder to
  third-party apps, and we will not fake one.
- Actual encoder availability is probed at runtime from the FFmpeg build (`EncoderCatalog`), so
  the app never assumes a codec that the installed binary lacks.
