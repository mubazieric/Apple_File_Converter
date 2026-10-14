# Test fixtures

Drop **real** media files here to exercise the native decode/probe paths that cannot be
generated on a build machine. Nothing in the app depends on these at runtime; tests that use a
fixture should **skip** (not fail) when it is absent so a clean checkout still passes.

Suggested files (keep each under ~2 MB, and only commit media you have the rights to):

| Filename | What it exercises |
| --- | --- |
| `heic_iphone.heic` | Native HEIC decode → shared pipeline |
| `heif_iphone.heif` | HEIF decode |
| `avif_sample.avif` | OS-dependent AVIF decode |
| `mov_hevc_1080p.mov` | MOV container + HEVC probe/transcode |
| `mp4_h264_aac.mp4` | Baseline H.264/AAC |
| `mp4_vfr.mov` | Variable frame rate handling |
| `hdr10.mp4` | HDR / wide-gamut tone-mapping |
| `rotated_exif.jpg` | EXIF orientation |
| `with_gps.jpg` | Metadata stripping (GPS) |
| `large_50mp.jpg` | Memory-bounded streaming |
| `corrupt.jpg` | Honest failure (no output) |

Example test guard:

```dart
final fixture = File('test/fixtures/heic_iphone.heic');
if (!fixture.existsSync()) {
  markTestSkipped('heic fixture not present');
  return;
}
```

See `docs/TESTING.md` for how to write the assertions around `OutputValidator`.
