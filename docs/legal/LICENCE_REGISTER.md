# Licence register — Apple File Converter (Iwat Digital)

This register lists the direct dependencies and the notable bundled binaries, their licences
and the obligations that follow. It must be reviewed before every store submission.

> Status legend: **OK** = compatible with proprietary distribution; **REVIEW** = requires a
> deliberate decision; **AVOID** = must not be shipped.

## Flutter / Dart packages

| Package | Version | Licence | Status | Notes |
| --- | --- | --- | --- | --- |
| flutter / dart | SDK 3.47.7 / 3.13.5 | BSD-3-Clause | OK | App framework |
| provider | ^6.1.5 | MIT | OK | State management |
| shared_preferences | ^2.5.6 | BSD-3-Clause | OK | Settings |
| sqflite | ^2.4.4 | MIT | OK | Conversion history |
| path | ^1.9.1 | BSD-3-Clause | OK | Path joining |
| path_provider | ^2.1.6 | BSD-3-Clause | OK | App directories (queue snapshot, exports) |
| photo_manager | ^3.12.0 | Apache-2.0 | OK | Gallery access |
| photo_manager_image_provider | ^2.2.0 | Apache-2.0 | OK | Gallery thumbnails |
| image | ^4.12.0 | MIT | OK | Pure-Dart image codecs |
| archive | ^4.5.2 | MIT | OK | ZIP export |
| crypto | ^3.0.7 | BSD-3-Clause | OK | Content hashing for duplicate detection |
| intl | ^0.20.3 | BSD-3-Clause | OK | Formatting / i18n |
| collection | ^1.19.1 | BSD-3-Clause | OK | Utilities |
| video_player | ^2.14.1 | BSD-3-Clause | OK | Video preview |
| share_plus | ^13.3.1 | BSD-3-Clause | OK | Share sheet |
| file_picker | ^13.1.0 | MIT | OK | Picking non-gallery files |
| image_picker | ^1.2.4 | Apache-2.0 | OK | Camera / quick pick |
| permission_handler | ^13.0.2 | MIT | OK | Explicit permission UX |
| url_launcher | ^6.3.3 | BSD-3-Clause | OK | Privacy/support links |
| package_info_plus | ^10.2.2 | BSD-3-Clause | OK | Version/build display |
| device_info_plus | ^13.3.0 | BSD-3-Clause | OK | Capability tuning |
| open_filex | ^4.7.0 | MIT | OK | Open exported file |
| google_mobile_ads | ^9.1.0 | Apache-2.0 (SDK: Google Mobile Ads terms) | REVIEW | Ad network terms apply; consent required |
| flutter_localizations | SDK | BSD-3-Clause | OK | Localisation |

Dev-only (not shipped): `flutter_test`, `flutter_lints` (BSD-3-Clause), `integration_test`,
`mocktail` (MIT).

## Bundled native / binary components

| Component | Version | Licence | Status | Notes |
| --- | --- | --- | --- | --- |
| `ffmpeg_kit_flutter_new_full` plugin | ^2.5.7 | LGPL-3.0 | OK | **No GPL codecs included.** Ship licence text + attribution; ships as separate shared libs (relinkable) |
| FFmpeg core | 8.1.x | LGPL-2.1-or-later | OK | Configured without `--enable-gpl` |
| libvpx (VP8/VP9) | bundled | BSD-3-Clause | OK | Patent grant included |
| dav1d (AV1) | bundled | BSD-2-Clause | OK | |
| opus, libvorbis, lame (mp3), speex, etc. | bundled | BSD / Xiph / LGPL | OK | Attribution required |
| Android MediaCodec / MediaMuxer | OS | OS APIs | OK | Preferred hardware encoders |
| Apple VideoToolbox / ImageIO / AVFoundation | OS | OS APIs | OK | Preferred hardware encoders + HEIC decode |
| Google Mobile Ads SDK | via plugin | Google terms | REVIEW | Data collection disclosure in privacy policy |

### Explicitly excluded

| Component | Why excluded |
| --- | --- |
| `ffmpeg_kit_flutter_new` (Full **GPL**) | Pulls in x264/x265 → GPL-3.0 obligations on the whole app |
| Original `ffmpeg-kit` / `ffmpeg_kit_flutter` | Retired upstream; not a supported dependency |
| `video_thumbnail` | Declares Dart SDK `<3.0.0`; incompatible; thumbnails are produced via FFmpeg/photo_manager instead |
| `flutter_staggered_grid_view` | Declares Dart SDK `<3.0.0`; incompatible; a standard `GridView` is used |

## Obligations checklist

- [ ] `THIRD_PARTY_NOTICES.md` is generated from the resolved lockfile before release.
- [ ] The LGPL-3.0 text for FFmpegKit and FFmpeg is bundled in-app (Open-source licences screen).
- [ ] No GPL-only codec is present in the shipped binaries (`ffmpeg -buildconf` check in CI).
- [ ] AdMob data collection is disclosed in the published privacy policy.
- [ ] Patent notes for H.264/H.265/VP9/AV1 are acknowledged (hardware paths preferred).
