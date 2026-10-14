# ADR 0003 — Gallery access via photo_manager with least-privilege permissions

* Status: Accepted
* Date: 2026-10-13

## Context

The gallery must browse the device photo/video library with real thumbnails, metadata, albums,
multi-select and delete, without duplicating the library and while respecting scoped storage
(Android 10+) and the iOS Photos permission model (including limited access and iCloud-only
assets).

## Decision

Use **`photo_manager`** as the discovery layer. It maps to `MediaStore` on Android and
`PHAsset`/`PHAssetCollection` on iOS, provides paginated asset queries, native thumbnail bytes,
stable asset IDs, album enumeration, change notifications, iCloud progress callbacks and
edit/delete APIs. Rendering uses `photo_manager_image_provider` so thumbnails are cached by the
framework image cache rather than copied to disk by us.

Permissions are requested **lazily and narrowly**:

* Read image/video only when the Gallery tab is first opened.
* Add-only (Android 13+ is implicit; iOS `NSPhotoLibraryAddUsageDescription`) only when saving.
* No `MANAGE_MEDIA`, no `ACCESS_MEDIA_LOCATION`, no legacy external storage by default.

## Alternatives considered

* **Build a MediaStore/PHPhotoLibrary bridge ourselves.** Rejected: re-implementing paging,
  change notification and iCloud progress is a large, risky surface for no user-visible gain.
* **`image_picker`/`file_picker` only.** Rejected: that is a picker, not a gallery; the prompt
  requires a standalone gallery.

## Consequences

* We inherit `photo_manager`'s platform minimums (Android 16 / iOS 9, we target far higher).
* "My Conversions" is an *app-owned* collection (files we produced), not a system album, so it
  works even when the photo library is not granted.
* Limited-access and iCloud-download states must be surfaced in the UI; we provide
  `presentLimited()` recovery and a progress handler for iCloud fetches.
