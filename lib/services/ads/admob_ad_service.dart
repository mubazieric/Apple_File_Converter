import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';
import 'ad_unit_ids.dart';

/// AdMob implementation of [AdService].
///
/// Only ever constructed by `AdServiceFactory` when `ENABLE_ADS` is set at build time and the
/// app is running on a mobile platform. It uses Google's test ad units unless production ids
/// were supplied via `--dart-define`, and it honours the UMP consent flow before requesting any
/// ad. It never blocks or interrupts a conversion.
class AdMobAdService implements AdService {
  AdMobAdService({required this.isAndroid, bool? useTestAds})
    : _useTestAds = useTestAds ?? kDebugMode;

  final bool isAndroid;
  final bool _useTestAds;

  bool _initialized = false;
  bool _canRequestAds = false;

  final Map<AdPlacement, InterstitialAd> _interstitials =
      <AdPlacement, InterstitialAd>{};
  final Map<AdPlacement, RewardedAd> _rewardeds = <AdPlacement, RewardedAd>{};

  @override
  bool get isEnabled => true;

  @override
  String get providerName => 'Google AdMob (test ads)';

  bool get useTestAds => _useTestAds;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    try {
      await _updateConsent();
      await showConsentFormIfRequired();
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      if (_canRequestAds) {
        await MobileAds.instance.initialize();
      }
    } catch (error) {
      debugPrint('Ad initialization failed: $error');
      _canRequestAds = false;
    }
  }

  Future<void> _updateConsent() async {
    final completer = Completer<void>();
    void complete() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        complete,
        (error) {
          debugPrint('Consent update failed: ${error.message}');
          complete();
        },
      );
    } catch (error) {
      debugPrint('Consent update threw: $error');
      complete();
    }
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }

  @override
  Future<AdConsentSnapshot> consentSnapshot() async {
    try {
      final status = await ConsentInformation.instance.getConsentStatus();
      final canRequest = await ConsentInformation.instance.canRequestAds();
      return AdConsentSnapshot(
        canRequestAds: canRequest,
        status: _mapStatus(status),
      );
    } catch (_) {
      return AdConsentSnapshot.unavailable;
    }
  }

  static ConsentStatusLevel _mapStatus(ConsentStatus status) =>
      switch (status) {
        ConsentStatus.notRequired => ConsentStatusLevel.notRequired,
        ConsentStatus.obtained => ConsentStatusLevel.obtained,
        ConsentStatus.required => ConsentStatusLevel.required,
        ConsentStatus.unknown => ConsentStatusLevel.unknown,
      };

  @override
  Future<void> requestConsentUpdate() async {
    await _updateConsent();
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
  }

  @override
  Future<void> showConsentFormIfRequired() async {
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) {
          debugPrint('Consent form error: ${error.message}');
        }
      });
    } catch (error) {
      debugPrint('Consent form failed: $error');
    }
  }

  String? _unitIdFor(AdPlacement placement) {
    if (!_canRequestAds) {
      return null;
    }
    return AdUnitIds.resolve(
      AdUnitIds.formatFor(placement),
      isAndroid: isAndroid,
      useTestAds: _useTestAds,
    );
  }

  @override
  Widget? buildBanner(AdPlacement placement) {
    final unitId = _unitIdFor(placement);
    if (unitId == null) {
      return null;
    }
    return _BannerAdSlot(adUnitId: unitId);
  }

  @override
  Widget? buildNative(AdPlacement placement) {
    final unitId = _unitIdFor(placement);
    if (unitId == null) {
      return null;
    }
    return _NativeAdSlot(adUnitId: unitId);
  }

  @override
  Future<void> preloadInterstitial(AdPlacement placement) async {
    if (_interstitials.containsKey(placement)) {
      return;
    }
    final unitId = _unitIdFor(placement);
    if (unitId == null) {
      return;
    }
    try {
      await InterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _interstitials[placement] = ad,
          onAdFailedToLoad: (error) =>
              debugPrint('Interstitial failed to load: ${error.message}'),
        ),
      );
    } catch (error) {
      debugPrint('Interstitial load threw: $error');
    }
  }

  @override
  Future<bool> showInterstitial(AdPlacement placement) async {
    final ad = _interstitials.remove(placement);
    if (ad == null) {
      return false;
    }
    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(true);
        }
        unawaited(preloadInterstitial(placement));
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      },
    );
    try {
      await ad.show();
    } catch (error) {
      debugPrint('Interstitial show threw: $error');
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    return completer.future;
  }

  @override
  Future<void> preloadRewarded(AdPlacement placement) async {
    if (_rewardeds.containsKey(placement)) {
      return;
    }
    final unitId = _unitIdFor(placement);
    if (unitId == null) {
      return;
    }
    try {
      await RewardedAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) => _rewardeds[placement] = ad,
          onAdFailedToLoad: (error) =>
              debugPrint('Rewarded failed to load: ${error.message}'),
        ),
      );
    } catch (error) {
      debugPrint('Rewarded load threw: $error');
    }
  }

  @override
  Future<bool> showRewarded(AdPlacement placement) async {
    final ad = _rewardeds.remove(placement);
    if (ad == null) {
      return false;
    }
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(earned);
        }
        unawaited(preloadRewarded(placement));
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      },
    );
    try {
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          earned = true;
        },
      );
    } catch (error) {
      debugPrint('Rewarded show threw: $error');
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    return completer.future;
  }

  @override
  void dispose() {
    for (final ad in _interstitials.values) {
      ad.dispose();
    }
    _interstitials.clear();
    for (final ad in _rewardeds.values) {
      ad.dispose();
    }
    _rewardeds.clear();
  }
}

/// Loads and shows a single banner, collapsing to nothing on failure.
class _BannerAdSlot extends StatefulWidget {
  const _BannerAdSlot({required this.adUnitId});

  final String adUnitId;

  @override
  State<_BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<_BannerAdSlot> {
  BannerAd? _loadedAd;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loadedAd = ad as BannerAd);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    ad.load();
  }

  @override
  void dispose() {
    _loadedAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _loadedAd;
    if (ad == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}

/// Loads and shows a native ad using Google's medium template.
class _NativeAdSlot extends StatefulWidget {
  const _NativeAdSlot({required this.adUnitId});

  final String adUnitId;

  @override
  State<_NativeAdSlot> createState() => _NativeAdSlotState();
}

class _NativeAdSlotState extends State<_NativeAdSlot> {
  NativeAd? _loadedAd;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final ad = NativeAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loadedAd = ad as NativeAd);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    ad.load();
  }

  @override
  void dispose() {
    _loadedAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _loadedAd;
    if (ad == null) {
      return const SizedBox.shrink();
    }
    return AdWidget(ad: ad);
  }
}
