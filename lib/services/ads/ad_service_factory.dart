import '../platform/platform_info.dart';
import 'ad_service.dart';
import 'ad_unit_ids.dart';
import 'admob_ad_service.dart';

/// Chooses the ad implementation for this build.
///
/// Ads are **off by default**: they only switch on when the build is compiled with
/// `--dart-define=ENABLE_ADS=true`, which is how the release pipeline enables them after the
/// consent flow and production ad unit ids have been configured.
abstract final class AdServiceFactory {
  static AdService create() {
    if (!AdUnitIds.enabledByFlag) {
      return const NoOpAdService();
    }
    if (!PlatformInfo.isMobile) {
      return const NoOpAdService();
    }
    return AdMobAdService(isAndroid: PlatformInfo.isAndroid);
  }
}
