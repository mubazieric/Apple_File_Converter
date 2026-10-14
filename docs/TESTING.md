# Testing guide

## Running the suite

```bash
flutter analyze                                          # must be clean
dart format --set-exit-if-changed lib test integration_test
flutter test                                             # unit + widget
flutter test integration_test/app_test.dart              # needs a device/emulator
```

`flutter analyze` treats **every** finding — including info-level lints — as a failure. Merge
only when it prints `No issues found!`.

## What is covered

| File | What it proves |
| --- | --- |
| `test/domain/format_detector_test.dart` | Signature detection for every supported container/format |
| `test/domain/format_roundtrip_test.dart` | The detector recognises **real encoder output** (JPEG/PNG/GIF/BMP/TIFF/ICO/WebP) |
| `test/domain/output_validation_test.dart` | Outputs are validated (format, container, dimensions, duration, streams); a renamed file is rejected |
| `test/services/image_conversion_engine_test.dart` | **End-to-end**: a file is converted, the output is verified by signature, failures leave no file |
| `test/services/ffmpeg_command_builder_test.dart` | Encoder selection, remux-vs-transcode, filters/flags |
| `test/domain/*_spec_test.dart`, `naming_policy_test.dart`, `app_settings_test.dart` | Spec/preset/policy/default logic |
| `test/domain/conversion_queue_test.dart` | Queue states, concurrency, retry/cancel, recovery |
| `test/domain/queue_persistence_test.dart` | A queued batch survives a JSON round-trip; unfinished jobs are restored, mid-flight ones as failed |
| `test/data/queue_store_test.dart` | The file queue store round-trips and tolerates a missing/corrupt file |
| `test/core/*` | Byte/storage formatting and maths |
| `test/ui/app_smoke_test.dart` | The whole widget tree builds, every tab renders, no platform channel is touched unexpectedly |
| `integration_test/app_test.dart` | The **real** composition root boots on a device and every tab renders |

The image-engine test is the most important one: it exercises the same code path the UI uses and
asserts on the produced file, not on a mock.

## Adding real media fixtures

Some behaviours (HEIC decode, MOV/HEVC probe, HDR, VFR) need real Apple-produced files that
cannot be generated on a Windows/Linux CI runner. To cover them:

1. Create `test/fixtures/` and drop real files in, for example:
   - `heic_iphone.heic` — a photo straight out of an iPhone
   - `mov_hevc_1080p.mov` — HEVC in a QuickTime container
   - `mp4_h264_aac.mp4`, `mp4_vfr.mov` (variable frame rate), `hdr10.mp4`
   - `rotated_exif.jpg`, `with_gps.jpg`, `corrupt.jpg`, `large_50mp.jpg`
2. Keep them **small** (< ~2 MB each) and commit only media you have the rights to.
3. Add a test that reads them, converts them, and asserts on `OutputValidator` results. A
   fixture that is missing should make its test **skip**, not fail, so the suite still runs on a
   clean checkout:

   ```dart
   final fixture = File('test/fixtures/heic_iphone.heic');
   if (!fixture.existsSync()) {
     markTestSkipped('fixture not present');
     return;
   }
   ```

> Nothing in the app depends on a fixture existing at runtime. Fixtures exist purely so the
> native decode/probe paths can be exercised on a machine that has the samples.

## Device-only checks

These cannot be verified by `flutter test` and are run manually or in CI device jobs:

- HEIC/HEIF and AVIF decoding on a real device.
- Saving to Photos / MediaStore and the resulting item appearing in the gallery.
- Video conversion (needs the FFmpeg binaries) including remux and hardware encoders.
- The UMP consent form.
- Photo-library permission prompts and the limited-access picker.

Record the device, OS version and result for each manual check in the release notes.

## CI

`.github/workflows/ci.yml` runs, on push/PR:

1. `dart format --set-exit-if-changed`
2. `flutter analyze`
3. `flutter test`
4. Android debug build (Linux)
5. iOS compile validation (macOS `macos-14`)
6. Dependency and secret scanning

The release workflow (`release.yml`) builds signed artefacts from repository secrets and never
commits keys.
