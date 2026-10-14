import 'package:flutter/widgets.dart';

/// Where an ad may appear.
///
/// Placements are deliberately specific so the UI can never accidentally show an ad over a
/// conversion result, and so the policy is auditable in one place.
enum AdPlacement {
  homeBanner('home_banner'),
  galleryBanner('gallery_banner'),
  toolsNative('tools_native'),
  conversionInterstitial('conversion_interstitial'),
  rewardedFeature('rewarded_feature');

  const AdPlacement(this.id);

  final String id;
}

/// Plain-language mirror of the UMP consent status, so the UI does not depend on the ads SDK.
enum ConsentStatusLevel { unknown, notRequired, required, obtained }

class AdConsentSnapshot {
  const AdConsentSnapshot({required this.canRequestAds, required this.status});

  final bool canRequestAds;
  final ConsentStatusLevel status;

  static const AdConsentSnapshot unavailable = AdConsentSnapshot(
    canRequestAds: false,
    status: ConsentStatusLevel.unknown,
  );
}

/// The app's entire advertising surface.
///
/// The rest of the app only ever talks to this interface. The default implementation is
/// [NoOpAdService] (see `ad_service_factory.dart`), so release builds without configured ad
/// unit IDs, debug builds and tests are completely ad-free and offline.
abstract interface class AdService {
  /// False when the NoOp service is in use.
  bool get isEnabled;

  /// Human-readable provider name for the "Ad privacy" settings row.
  String get providerName;

  Future<void> initialize();

  Future<AdConsentSnapshot> consentSnapshot();

  /// Re-requests consent information from the consent management platform.
  Future<void> requestConsentUpdate();

  /// Shows the consent form when the platform says it is required.
  Future<void> showConsentFormIfRequired();

  /// A banner ready to be embedded, or null when ads must not be shown.
  Widget? buildBanner(AdPlacement placement);

  /// A native ad ready to be embedded, or null when ads must not be shown.
  Widget? buildNative(AdPlacement placement);

  Future<void> preloadInterstitial(AdPlacement placement);

  /// Shows an interstitial. Returns true when the ad was actually shown and dismissed.
  /// Callers must **never** await this before completing user-initiated work; it is only used
  /// between screens, never during a conversion.
  Future<bool> showInterstitial(AdPlacement placement);

  Future<void> preloadRewarded(AdPlacement placement);

  /// Shows a rewarded ad. Returns true only when the reward was actually earned.
  Future<bool> showRewarded(AdPlacement placement);

  void dispose();
}

/// The default, privacy-preserving implementation: it shows nothing and does nothing.
class NoOpAdService implements AdService {
  const NoOpAdService();

  @override
  bool get isEnabled => false;

  @override
  String get providerName => 'None';

  @override
  Future<void> initialize() async {}

  @override
  Future<AdConsentSnapshot> consentSnapshot() async =>
      AdConsentSnapshot.unavailable;

  @override
  Future<void> requestConsentUpdate() async {}

  @override
  Future<void> showConsentFormIfRequired() async {}

  @override
  Widget? buildBanner(AdPlacement placement) => null;

  @override
  Widget? buildNative(AdPlacement placement) => null;

  @override
  Future<void> preloadInterstitial(AdPlacement placement) async {}

  @override
  Future<bool> showInterstitial(AdPlacement placement) async => false;

  @override
  Future<void> preloadRewarded(AdPlacement placement) async {}

  @override
  Future<bool> showRewarded(AdPlacement placement) async => false;

  @override
  void dispose() {}
}
