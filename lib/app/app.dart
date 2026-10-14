import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/settings/app_settings.dart';
import '../services/ads/ad_service.dart';
import '../services/conversion/conversion_coordinator.dart';
import '../services/export/zip_exporter.dart';
import '../services/gallery/gallery_service.dart';
import '../services/storage/storage_service.dart';
import '../state/conversion_controller.dart';
import '../state/gallery_controller.dart';
import '../state/settings_controller.dart';
import '../state/shell_controller.dart';
import '../ui/screens/root_shell.dart';
import '../ui/theme/app_theme.dart';
import 'app_services.dart';

/// Wires the controllers into the widget tree and applies the chosen theme.
class AppleFileConverterApp extends StatelessWidget {
  const AppleFileConverterApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        Provider<AdService>.value(value: services.ads),
        Provider<StorageService>.value(value: services.storage),
        ChangeNotifierProvider<ConversionCoordinator>.value(
          value: services.coordinator,
        ),
        Provider<GalleryService>.value(value: services.galleryService),
        Provider<ZipExporter>.value(value: services.zipExporter),
        ChangeNotifierProvider<SettingsController>.value(
          value: services.settings,
        ),
        ChangeNotifierProvider<GalleryController>.value(
          value: services.gallery,
        ),
        ChangeNotifierProvider<ConversionController>.value(
          value: services.conversion,
        ),
        ChangeNotifierProvider<ShellController>.value(value: services.shell),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settings, child) {
          return MaterialApp(
            title: 'Apple File Converter',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _themeMode(settings.settings.theme),
            home: const _ConsentGate(child: RootShell()),
          );
        },
      ),
    );
  }

  static ThemeMode _themeMode(ThemePreference preference) =>
      switch (preference) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      };
}

/// Runs the ad-consent flow once, after the first frame.
///
/// Ads are disabled by default, so for most builds this is a no-op. When ads are enabled it
/// shows the Google UMP form if the user's region requires it, then records that the decision
/// was made so settings can show the right state.
class _ConsentGate extends StatefulWidget {
  const _ConsentGate({required this.child});

  final Widget child;

  @override
  State<_ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<_ConsentGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) {
      return;
    }
    final services = context.read<AppServices>();
    final settings = services.settings;
    try {
      await services.ads.initialize();
      if (!services.ads.isEnabled) {
        return;
      }
      await services.ads.requestConsentUpdate();
      await services.ads.showConsentFormIfRequired();
      if (!mounted) {
        return;
      }
      if (!settings.settings.adsConsentDecided) {
        await settings.markAdsConsentDecided();
      }
    } catch (_) {
      // Never let the consent flow block the app.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
