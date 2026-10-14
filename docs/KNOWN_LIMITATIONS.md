# Known limitations

This is the honest list of what the app does **not** do, or does only partially. Everything
here is either absent from the UI (so nothing implies it works) or disclosed in the app.

## Deferred features (no UI is shown for these)

| Feature | Why it is deferred |
| --- | --- |
| Crop (image and video) | Not implemented in the engine; no button is shown. Use rotate/resize instead. |
| Images → PDF | No PDF engine is bundled. |
| GIF creation (from images/video) | Not implemented. GIF *conversion* works; *creation* does not. |
| Video frame extraction | Not implemented. |
| Video merge / concat | Not implemented (no concat demuxer wiring). |
| Pause / resume a batch | The queue only supports cancel and retry. A real pause would need per-file suspension that the engines do not provide, so it is not offered rather than faked. |

## Format limitations

- **HEIC, HEIF, AVIF and DNG cannot be encoded.** Apple does not expose a supported HEIC encoder
  to third-party apps, and no LGPL AVIF/DNG encoder is bundled. These are decode-only.
- **SVG, JPEG 2000 (JP2) and WBMP are unsupported** (no view, decode or encode).
- **WMV and FLV are decode-only** — no muxer is shipped for them.
- **H.264 and AV1 output require a hardware encoder.** The bundled FFmpeg is the **LGPL** build
  with no `libx264` and no software AV1 encoder. If the device has no hardware encoder for the
  requested codec, the job fails with a clear message instead of producing a bad file.
- **Software H.265 fallback is `libkvazaar`** (not `libx265`, which is GPL).
- **WebP output is static only**; animated WebP is decoded to its first frame, and animation is
  not written.
- **Animated GIF sources become single-frame output.**
- **AVIF/DNG decode depends on the OS.** Older Android/iOS versions cannot decode them; the app
  reports "unsupported on this device" rather than failing silently.

## Metadata

- **Image EXIF is carried for JPEG, TIFF and WebP**; **ICC profiles for JPEG, PNG and WebP**.
  PNG EXIF is not written (the bundled encoder has no PNG EXIF writer), and GIF/BMP/ICO have no
  metadata container at all.
- **"Remove all" and "Remove location" are enforced** at encode time: the first writes no EXIF,
  the second removes the GPS IFD while keeping the rest. This is covered by
  `test/services/image_metadata_test.dart`.
- **HEIC/AVIF/DNG conversions cannot retain EXIF**, because the native decode path returns raw
  pixels only. The metadata policy still applies (nothing is invented), but the original tags are
  not available to carry across.
- **Video metadata** is handled by FFmpeg; "remove all" strips container metadata, and GPS/date
  are dropped with it.

## Gallery

- **Search and non-date sorting are client-side.** Dates are sorted by the platform; name, size,
  format and duration are sorted and searched over the pages that have been loaded so far. For a
  very large library this means results refine as more pages load. This is disclosed in the UI.
- **Duplicate detection scans the app's own exports folder only**, not the whole system library.
  Scanning all of MediaStore/Photos is intentionally not offered (privacy and performance).
- **Exporting to the system gallery keeps a copy in the app's exports folder.** On iOS there is
  no supported way for a third-party app to move a file out of its sandbox, so the app retains a
  local copy and also saves one into Photos. Converting a very large library therefore uses
  roughly twice the disk space of the outputs. Use "app exports folder" as the destination and
  clean up with the Storage tool if space is tight.
- **"Storage analysis" may show an "unknown" bucket** for items whose size the platform does not
  report. It is shown rather than hidden.

## Apple-specific behaviour

- **Live Photos are treated as their individual assets.** The paired still and video are browsable
  and convertible separately; the Live Photo pairing is not preserved through conversion.
- **Portrait / depth maps are not preserved.** Only the primary image is converted.
- **Wide-gamut and HDR stills are tone-mapped to 8-bit sRGB** on decode (the shared pipeline is
  8-bit). This can shift very saturated colours slightly.
- **VFR (variable frame rate) video** is handled by FFmpeg; setting a fixed output frame rate will
  convert the clip to CFR.
- **iCloud-only assets** may need downloading before they can be converted; the gallery marks them
  as remote rather than failing silently.

## Platform verification status

- **iOS is not built in this development environment** (Windows). iOS compile validation runs in
  the `macos-14` CI job; on-device iOS behaviour must be checked on a Mac/device.
- **The native bridge and AdMob paths are implemented but not runtime-verified here** (no device
  or emulator available in this workspace). Ads are off by default, so a default build exercises
  none of the ad code.
- **Video conversion requires the FFmpeg native binaries**, so the video engine cannot run under
  `flutter test` on the host. The command *builder* is unit-tested; actual encoding is verified on
  a device.

## Other

- The conversion history database is not encrypted (it stores file names and sizes, no media).
- UI strings are English only; the localisation architecture is in place for other languages.
- The app never overwrites an original file. On a name collision it writes a new, suffixed file.

If a limitation above becomes acceptable to change, it should be turned into a real feature with
tests and the corresponding docs updated — not quietly enabled.
