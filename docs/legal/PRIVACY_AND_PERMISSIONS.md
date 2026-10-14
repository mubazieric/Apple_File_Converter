# Privacy & permissions guide — Apple File Converter

**Developer:** Iwat Digital
**Data controller:** Iwat Digital (contact details are placeholders until verified — see below)

## 1. Plain-language summary

Apple File Converter converts and manages photos and videos **on your device**. It does not
upload your photos, videos, file names or metadata to us or to any conversion service. There is
no account system and no cloud storage. The only third party that receives any data is Google's
advertising SDK, and only when advertising is enabled and consent has been given.

## 2. What the app accesses and why

| Data | When | Where it stays | Why |
| --- | --- | --- | --- |
| Photos & videos in your library | When you open Gallery or pick files | On device | To show, convert and manage them |
| File name, size, dimensions, duration, dates | When listing media | On device (app database) | Gallery metadata, history, storage dashboard |
| EXIF/creation metadata | During conversion | In the output file, if you keep metadata | Faithful conversion; you can choose to strip it |
| Selected export folder | When you export | On device | To write converted files |

## 3. What is *never* sent anywhere

* Photo or video content.
* File names or paths.
* EXIF/GPS/depth/Live Photo data.
* Conversion contents or results.

There is **no analytics SDK**, **no crash-reporting SDK** and **no backend server** in this app.

## 4. Advertising (Google AdMob)

When advertising is enabled in a release build:

* The Google Mobile Ads SDK may collect device identifiers, approximate location derived from
  IP, and ad-interaction data, as described by Google's policies.
* Before any ad is requested, the app runs Google's **User Messaging Platform (UMP)** consent
  flow where required by your region. Personalised ads are only requested after consent.
* You can change or withdraw consent at any time in **Settings → Privacy → Ad privacy options**.
* We never pass media, file names or metadata to the advertising SDK.

If advertising is disabled (development builds, or `AdConfig.enabled = false`), no ad SDK is
initialised and no ad data leaves the device.

## 5. Permissions requested

### Android

| Permission | Purpose | When requested |
| --- | --- | --- |
| `READ_MEDIA_IMAGES` (33+) | Read photos | First Gallery open |
| `READ_MEDIA_VIDEO` (33+) | Read videos | First Gallery open |
| `READ_MEDIA_VISUAL_USER_SELECTED` (34+) | Limited access support | First Gallery open |
| `READ_EXTERNAL_STORAGE` (≤32) | Read media on older Android | First Gallery open |
| `WRITE_EXTERNAL_STORAGE` (≤28) | Save exports on very old Android | On first export |
| `ACCESS_MEDIA_LOCATION` | **Not requested.** Only needed for GPS EXIF; we strip location rather than request it | — |
| `INTERNET` | AdMob only (no other network use) | Manifest |
| `POST_NOTIFICATIONS` (33+) | Optional foreground job progress | When you start a long batch |

### iOS

| Key | Purpose | When requested |
| --- | --- | --- |
| `NSPhotoLibraryUsageDescription` | Read photos/videos | First Gallery open |
| `NSPhotoLibraryAddUsageDescription` | Save conversions | On first save |
| `NSCameraUsageDescription` | Only if you use the camera shortcut | On first camera use |
| `NSMicrophoneUsageDescription` | Only if you record audio with camera | On first camera use |
| `NSAppTransportSecurity` | Restricted; only the ad SDK domains are permitted | — |

The app supports iOS **Limited Photos** access and offers a "Select more photos" action
(`PHPhotoLibrary.presentLimited`) when access is limited.

## 6. Temporary files and retention

* Conversion temp files live in the app cache directory and are deleted on job completion, on
  cancelling, and by a sweep on launch.
* Conversion history stores only paths, formats, sizes and timestamps. You can clear it at any
  time in **Settings → Storage → Clear history**.
* Deleting the app removes all app data, including history and settings.

## 7. Children

The app is a general-purpose utility, not directed at children. Ad requests are configured so
that child-directed treatment can be enabled if the store listing changes audience; the default
is not child-directed.

## 8. Your rights

Because we do not collect or store your personal media or an account, there is little personal
data for us to hold. To withdraw ad consent, use the in-app control or your device settings. To
delete app data, clear app storage or uninstall the app.

## 9. Contact

**Privacy contact: PLACEHOLDER — not yet verified.**
Do **not** publish this policy until the developer supplies a real contact address and,
where required, a company address. The in-app About screen links to a configurable URL
(`AppInfo.privacyPolicyUrl`) which is empty by default.
