# AdMob & consent setup

Ads are **off by default**. A normal `flutter run` or `flutter build` produces an app with no ad
network initialised and no ad requested. This is deliberate: it keeps the core product
privacy-first and means the code you review is not secretly monetising a debug build.

Only Google's **public test ad IDs** are committed. Production IDs are supplied at build time
and are never stored in the repository.

## 1. How the switch works

`lib/services/ads/ad_service_factory.dart` picks the implementation:

```dart
if (!AdUnitIds.enabledByFlag) return const NoOpAdService();   // default
if (!PlatformInfo.isMobile)   return const NoOpAdService();   // desktop/web
return AdMobAdService(isAndroid: PlatformInfo.isAndroid);
```

- `ENABLE_ADS` — a compile-time `bool.fromEnvironment` flag. Unset → `NoOpAdService`.
- When the flag is off, `AdService.isEnabled` is `false`, the Settings screen shows
  "Ads are not active in this build.", and every placement builder returns an empty widget.

## 2. Test IDs (already committed)

`lib/services/ads/ad_unit_ids.dart` contains Google's documented sample units, e.g.:

| Format | Android | iOS |
| --- | --- | --- |
| Banner | `ca-app-pub-3940256099942544/6300978111` | `ca-app-pub-3940256099942544/2934735716` |
| Interstitial | `…/1033173712` | `…/4411468910` |
| Rewarded | `…/5224354917` | `…/1712485313` |
| Native | `…/2247696110` | `…/3986624511` |

The **app IDs** are placeholders too:

- Android `AndroidManifest.xml` → `ca-app-pub-3940256099942544~3347511713`
- iOS `Info.plist` → `GADApplicationIdentifier` = `ca-app-pub-3940256099942544~1458002511`

These are Google's sample app IDs. Replace both with your real app IDs for production.

## 3. Enabling ads in a build

Pass your production IDs (and the app IDs above) at build time:

```bash
flutter build appbundle --release \
  --dart-define=ENABLE_ADS=true \
  --dart-define=ADMOB_ANDROID_BANNER=ca-app-pub-<pub>/<unit> \
  --dart-define=ADMOB_ANDROID_NATIVE=ca-app-pub-<pub>/<unit> \
  --dart-define=ADMOB_ANDROID_INTERSTITIAL=ca-app-pub-<pub>/<unit> \
  --dart-define=ADMOB_ANDROID_REWARDED=ca-app-pub-<pub>/<unit>
```

```bash
flutter build ipa --release \
  --dart-define=ENABLE_ADS=true \
  --dart-define=ADMOB_IOS_BANNER=ca-app-pub-<pub>/<unit> \
  --dart-define=ADMOB_IOS_NATIVE=ca-app-pub-<pub>/<unit> \
  --dart-define=ADMOB_IOS_INTERSTITIAL=ca-app-pub-<pub>/<unit> \
  --dart-define=ADMOB_IOS_REWARDED=ca-app-pub-<pub>/<unit>
```

All eight keys (`ADMOB_{ANDROID,IOS}_{BANNER,NATIVE,INTERSTITIAL,REWARDED}`) are read via
`String.fromEnvironment`. **If a key is missing, that placement resolves to `null` and no ad is
requested** — the app degrades to fewer/no ads instead of failing.

### In CI

The release workflow (`.github/workflows/release.yml`) reads the same values from repository
secrets (e.g. `ADMOB_ANDROID_BANNER`, `ADMOB_IOS_BANNER`). Configure those secrets rather than
committing IDs. Never commit a keystore, provisioning profile or password.

## 4. Consent (Google UMP)

When ads are enabled, the app must run Google's User Messaging Platform flow before requesting
ads. This is implemented in `AdMobAdService` and driven from `_ConsentGate` in `lib/app/app.dart`
on first frame:

1. `initialize()` the Mobile Ads SDK.
2. `requestConsentUpdate()` — refreshes consent state for the user's region.
3. `showConsentFormIfRequired()` — shows the form when the region requires it.
4. Only after that are ads requested.

Users can revisit the form any time from **Settings → Advertising → Ad privacy**, which shows the
current consent status and re-runs the flow.

## 5. Placement rules

Ads are only ever placed where they cannot interrupt the core job:

| Placement | Format | Where |
| --- | --- | --- |
| `homeBanner` | Banner | Home tab, below the fold |
| `galleryBanner` | Banner | Gallery, as a grid item |
| `toolsNative` | Native | Tools tab |
| `conversionInterstitial` | Interstitial | Only after a batch completes |
| `rewardedFeature` | Rewarded | Only behind an explicit user tap |

**No ad is shown over a running conversion**, and interstitials never appear between the tap and
the result of a single conversion. See `lib/ui/widgets/ad_slot.dart` for the slot widget.

## 6. Verifying

```bash
# Ads off (default): Settings shows "Ads are not active in this build."
flutter run

# Ads on with test IDs: real Google test ads should appear after consent.
flutter run --dart-define=ENABLE_ADS=true
```

With production IDs in a debug build, Google may serve no-fill — that is expected; use the test
IDs (i.e. `ENABLE_ADS=true` without production keys) to see ads during development.

## 7. Privacy

AdMob is the only network component, and it is only active when compiled in. No media, file
name, path or metadata is ever passed to it. The privacy policy must accurately state this. See
`docs/legal/PRIVACY_AND_PERMISSIONS.md`.
