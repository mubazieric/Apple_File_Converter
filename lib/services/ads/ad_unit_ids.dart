import 'ad_service.dart';

/// The kind of ad unit, which determines which identifier is used.
enum AdFormat { banner, interstitial, rewarded, native }

/// Ad unit identifier resolution.
///
/// Only Google's **official test ad units** are compiled into the source; they are public
/// constants and never generate revenue. Production identifiers are supplied at build time
/// through `--dart-define` (see the AdMob guide) and are never committed. When a production id
/// is missing the placement simply returns null and no ad is requested, so a mis-configured
/// build degrades to "no ads" rather than crashing.
abstract final class AdUnitIds {
  // Google's documented sample ad units (https://developers.google.com/admob/flutter/test-ads).
  static const String androidTestBanner =
      'ca-app-pub-3940256099942544/6300978111';
  static const String iosTestBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const String androidTestInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String iosTestInterstitial =
      'ca-app-pub-3940256099942544/4411468910';
  static const String androidTestRewarded =
      'ca-app-pub-3940256099942544/5224354917';
  static const String iosTestRewarded =
      'ca-app-pub-3940256099942544/1712485313';
  static const String androidTestNative =
      'ca-app-pub-3940256099942544/2247696110';
  static const String iosTestNative = 'ca-app-pub-3940256099942544/3986624511';

  // Production identifiers, injected at build time only.
  static const String _prodAndroidBanner = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER',
  );
  static const String _prodIosBanner = String.fromEnvironment(
    'ADMOB_IOS_BANNER',
  );
  static const String _prodAndroidInterstitial = String.fromEnvironment(
    'ADMOB_ANDROID_INTERSTITIAL',
  );
  static const String _prodIosInterstitial = String.fromEnvironment(
    'ADMOB_IOS_INTERSTITIAL',
  );
  static const String _prodAndroidRewarded = String.fromEnvironment(
    'ADMOB_ANDROID_REWARDED',
  );
  static const String _prodIosRewarded = String.fromEnvironment(
    'ADMOB_IOS_REWARDED',
  );
  static const String _prodAndroidNative = String.fromEnvironment(
    'ADMOB_ANDROID_NATIVE',
  );
  static const String _prodIosNative = String.fromEnvironment(
    'ADMOB_IOS_NATIVE',
  );

  /// Resolves the unit id for a placement, or null when none is configured.
  static String? resolve(
    AdFormat format, {
    required bool isAndroid,
    required bool useTestAds,
  }) {
    if (useTestAds) {
      return _test(format, isAndroid);
    }
    final value = _production(format, isAndroid);
    return value.isEmpty ? null : value;
  }

  static String _test(AdFormat format, bool isAndroid) {
    return switch (format) {
      AdFormat.banner => isAndroid ? androidTestBanner : iosTestBanner,
      AdFormat.interstitial =>
        isAndroid ? androidTestInterstitial : iosTestInterstitial,
      AdFormat.rewarded => isAndroid ? androidTestRewarded : iosTestRewarded,
      AdFormat.native => isAndroid ? androidTestNative : iosTestNative,
    };
  }

  static String _production(AdFormat format, bool isAndroid) {
    return switch (format) {
      AdFormat.banner => isAndroid ? _prodAndroidBanner : _prodIosBanner,
      AdFormat.interstitial =>
        isAndroid ? _prodAndroidInterstitial : _prodIosInterstitial,
      AdFormat.rewarded => isAndroid ? _prodAndroidRewarded : _prodIosRewarded,
      AdFormat.native => isAndroid ? _prodAndroidNative : _prodIosNative,
    };
  }

  /// The ad format a placement uses.
  static AdFormat formatFor(AdPlacement placement) => switch (placement) {
    AdPlacement.homeBanner || AdPlacement.galleryBanner => AdFormat.banner,
    AdPlacement.toolsNative => AdFormat.native,
    AdPlacement.conversionInterstitial => AdFormat.interstitial,
    AdPlacement.rewardedFeature => AdFormat.rewarded,
  };

  /// Whether ads are switched on for this build at all.
  static const bool enabledByFlag = bool.fromEnvironment('ENABLE_ADS');
}
