# ADR 0006 — Advertising: optional AdMob behind a feature flag with UMP consent

* Status: Accepted
* Date: 2026-10-13

## Context

Monetisation uses Google AdMob, but advertising must never obstruct conversion controls or
interrupt a running job, must not send media/filenames/metadata to the ad network, and must be
testable with the SDK disabled. Regional law requires a consent (UMP) flow before requesting
personalised ads.

## Decision

* Wrap `google_mobile_ads` behind an `AdService` interface with a `NoOpAdService`. The active
  implementation is chosen from `AdConfig.enabled` (feature flag) which is `false` in debug
  and in tests.
* Only **test** ad unit IDs are committed (`AdConfig.testBannerId`, …). Production IDs are read
  from `--dart-define` values and are empty by default; `AdService` refuses to load a
  production unit whose ID is empty and disables ads instead of crashing.
* `ConsentService` wraps the UMP SDK: request consent info → load & show form if required →
  only then initialise the Mobile Ads SDK with `canRequestAds`.
* Ad placement policy (enforced in code review + tests):
  * Banner: Home and Settings only.
  * Interstitial: after a *batch completes* and the user returns to Home — never mid-job.
  * Rewarded: none shipped (no honest reward model yet), interface kept for extension.

## Consequences

* The app is fully functional with ads off; CI runs with `AdConfig.enabled == false`.
* We must document the exact `--dart-define` keys for release builds.
