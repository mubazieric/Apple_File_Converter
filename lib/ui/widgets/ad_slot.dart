import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ads/ad_service.dart';
import '../theme/app_theme.dart';

/// Renders a banner ad when the [AdService] provides one.
///
/// When ads are disabled (the default) [AdService.buildBanner] returns null and this collapses
/// to nothing — there is no reserved empty space and no placeholder.
class AdBannerSlot extends StatelessWidget {
  const AdBannerSlot({super.key, required this.placement});

  final AdPlacement placement;

  @override
  Widget build(BuildContext context) {
    final banner = context.read<AdService>().buildBanner(placement);
    if (banner == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: banner,
    );
  }
}

/// Renders a native ad when the [AdService] provides one.
class AdNativeSlot extends StatelessWidget {
  const AdNativeSlot({super.key, required this.placement});

  final AdPlacement placement;

  @override
  Widget build(BuildContext context) {
    final native = context.read<AdService>().buildNative(placement);
    if (native == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: native,
    );
  }
}
