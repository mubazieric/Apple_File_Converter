# Release checklist

Work top to bottom. Nothing here should be skipped silently; if a step is not applicable, note
why in the release notes.

## 1. Code is green

- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test` passes.
- [ ] `flutter analyze --fatal-infos` prints `No issues found!`.
- [ ] `flutter test` passes the full suite.
- [ ] CI is green on `main` (format, analyze, tests, Android debug build, iOS no-codesign build,
      secret scan, dependency scan).
- [ ] No `TODO`/`FIXME` was left in a code path that claims to be complete.

## 2. Versioning

- [ ] Bump `version:` in `pubspec.yaml` (e.g. `1.0.0+2`); the build number must increase for
      every store upload.
- [ ] Update the changelog / release notes.

## 3. AdMob (only if shipping ads)

- [ ] Replace the two placeholder **app IDs**:
      - [ ] Android `android/app/src/main/AndroidManifest.xml` →
            `com.google.android.gms.ads.APPLICATION_ID`
      - [ ] iOS `ios/Runner/Info.plist` → `GADApplicationIdentifier`
- [ ] Do **not** commit production unit IDs. Put them in repository secrets:
      `ADMOB_ANDROID_BANNER_ID`, `ADMOB_ANDROID_NATIVE_ID`,
      `ADMOB_ANDROID_INTERSTITIAL_ID`, `ADMOB_ANDROID_REWARDED_ID`, and the `ADMOB_IOS_*`
      equivalents.
- [ ] Confirm the release workflow passes them as `--dart-define` values
      (`docs/ADS_SETUP.md`).
- [ ] In a test build with test IDs, verify the consent form appears and ads render after
      consent.
- [ ] Confirm no ad appears over a running conversion.

## 4. Privacy & permissions

- [ ] Privacy policy is published and linked from About / the store listing; it matches
      `docs/legal/PRIVACY_AND_PERMISSIONS.md`.
- [ ] The policy accurately states: on-device processing, no media uploads, and that AdMob is the
      only network component and only when enabled.
- [ ] Android: `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_VISUAL_USER_SELECTED`,
      `ACCESS_MEDIA_LOCATION`, and the legacy `READ_EXTERNAL_STORAGE`/`WRITE_EXTERNAL_STORAGE`
      (maxSdk-gated) are all justified.
- [ ] iOS: `NSPhotoLibraryUsageDescription` and `NSPhotoLibraryAddUsageDescription` are present
      and written for users.
- [ ] Google Play **Data safety** and App Store **Privacy Nutrition Label** match reality.
- [ ] App is offline-capable: airplane-mode conversion of a local image works.

## 5. Signing (never committed)

- [ ] Android: keystore uploaded as `ANDROID_KEYSTORE_BASE64`; `ANDROID_KEY_ALIAS`,
      `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD` set as secrets. `.gitignore` excludes
      `*.jks`, `*.keystore`, `android/key.properties`.
- [ ] iOS: distribution certificate (`IOS_DISTRIBUTION_CERT_P12`, `IOS_CERT_PASSWORD`,
      `IOS_KEYCHAIN_PASSWORD`) and provisioning profile (`IOS_PROVISIONING_PROFILE`) set as
      secrets.
- [ ] `gitleaks` is clean; no key, token, password or production ad ID is in the tree.

## 6. Build artefacts

- [ ] Android AAB built from a `v*` tag (or the manual workflow) with
      `flutter build appbundle --release`.
- [ ] iOS IPA built on `macos-14` with `flutter build ipa --release`.
- [ ] The artefact names and versions in the store console match `pubspec.yaml`.

## 7. Device smoke test (per platform)

- [ ] Grant limited photo access, browse the gallery, open an image full-screen, pinch-zoom.
- [ ] Convert a HEIC → JPEG and confirm the output opens and the before/after sizes are shown.
- [ ] Convert a MOV/HEVC clip → MP4 (hardware H.264) and play it back.
- [ ] Run a batch of ≥5 files and confirm per-file and overall progress, then retry/cancel.
- [ ] Export to the app folder and to the system gallery; confirm the item appears in Photos /
      Gallery.
- [ ] Use the Storage dashboard and temp cleanup.
- [ ] Confirm originals are untouched and collisions produce new names.
- [ ] Kill the app mid-batch and relaunch; queued jobs resume and mid-flight jobs show as failed.
- [ ] With ads enabled: consent → ads; with ads disabled: no network calls from ads.

## 8. Store submission

- [ ] Store listing: name, description, screenshots, category, content rating.
- [ ] Description matches the actual feature set — do not list a deferred feature
      (`docs/KNOWN_LIMITATIONS.md`).
- [ ] Upload to Google Play internal testing, then production.
- [ ] Upload to App Store Connect, then TestFlight, then submit for review.
- [ ] Provide the reviewer with any needed test account/notes (none should be needed — the app
      has no login).

## 9. Post-release

- [ ] Tag the release in git (`git tag vX.Y.Z && git push origin vX.Y.Z`).
- [ ] Record the exact versions, device/OS tested and any residual issues in the release notes.
- [ ] Watch crash/ANR reports for the first days (if a crash reporter is configured).
