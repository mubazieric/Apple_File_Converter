import 'dart:io';

import '../data/history_store.dart';
import '../data/queue_store.dart';
import '../data/settings_store.dart';
import '../services/ads/ad_service.dart';
import '../services/ads/ad_service_factory.dart';
import '../services/conversion/conversion_coordinator.dart';
import '../services/conversion/ffmpeg_runner.dart';
import '../services/conversion/image_conversion_engine.dart';
import '../services/conversion/video_conversion_engine.dart';
import '../services/export/output_exporter.dart';
import '../services/export/zip_exporter.dart';
import '../services/gallery/gallery_service.dart';
import '../services/platform/media_codec_bridge.dart';
import '../services/platform/platform_info.dart';
import '../services/storage/storage_service.dart';
import '../state/conversion_controller.dart';
import '../state/gallery_controller.dart';
import '../state/settings_controller.dart';
import '../state/shell_controller.dart';

/// The composition root: builds every long-lived service once and hands the UI plain
/// controllers.
///
/// Nothing here reaches the network. Ads, when enabled by a release build, are the only
/// component that would, and they are off unless explicitly compiled in.
class AppServices {
  AppServices({
    required this.settings,
    required this.gallery,
    required this.conversion,
    required this.shell,
    required this.ads,
    required this.storage,
    required this.coordinator,
    required this.galleryService,
    ZipExporter? zipExporter,
  }) : zipExporter = zipExporter ?? const ArchiveZipExporter();

  final SettingsController settings;
  final GalleryController gallery;
  final ConversionController conversion;
  final ShellController shell;
  final AdService ads;
  final StorageService storage;
  final ConversionCoordinator coordinator;
  final GalleryService galleryService;
  final ZipExporter zipExporter;

  static Future<AppServices> bootstrap() async {
    final SettingsStore settingsStore = SharedPreferencesSettingsStore();
    final HistoryStore historyStore = SqliteHistoryStore();
    try {
      await historyStore.init();
    } catch (_) {
      // A missing database must never stop the app from starting.
    }

    final bridge = MediaCodecBridge();
    final storage = AppStorageService(bridge: bridge);
    final galleryService = PlatformInfo.isMobile
        ? PhotoManagerGalleryService()
        : const UnsupportedGalleryService();

    final imageEngine = ImageConversionEngine(bridge: bridge);
    final videoEngine = VideoConversionEngine(FfmpegKitRunner());
    final exporter = DeviceOutputExporter(storage: storage, bridge: bridge);
    final ads = AdServiceFactory.create();

    final initialSettings = await settingsStore.load();
    final suggestedConcurrency = _suggestedConcurrency();

    final coordinator = ConversionCoordinator(
      imageEngine: imageEngine,
      videoEngine: videoEngine,
      historyStore: historyStore,
      exportDestination: initialSettings.exportDestination,
      exporter: exporter,
      customExportDirectory: initialSettings.customExportPath,
      queueStore: FileQueueStore(),
      concurrency: initialSettings.effectiveConcurrency(suggestedConcurrency),
    );

    // Restore any batch that was interrupted by the app being closed, and mark the jobs that
    // were mid-flight as failed so nothing is silently pretended to still be running.
    try {
      await coordinator.restoreQueue();
    } catch (_) {
      // A damaged queue file must never stop the app from starting.
    }

    final settings = SettingsController(
      store: settingsStore,
      coordinator: coordinator,
      suggestedConcurrency: suggestedConcurrency,
    );
    await settings.load();

    final gallery = GalleryController(galleryService);

    return AppServices(
      settings: settings,
      gallery: gallery,
      conversion: ConversionController(
        coordinator: coordinator,
        settings: settings,
        gallery: gallery,
        storage: storage,
      ),
      shell: ShellController(),
      ads: ads,
      storage: storage,
      coordinator: coordinator,
      galleryService: galleryService,
    );
  }

  /// Half the available cores, capped at 4: enough to overlap I/O without exhausting memory on
  /// phones encoding large videos.
  static int _suggestedConcurrency() {
    final cores = Platform.numberOfProcessors;
    return (cores ~/ 2).clamp(1, 4);
  }

  void dispose() {
    coordinator.dispose();
    settings.dispose();
    gallery.dispose();
    conversion.dispose();
    shell.dispose();
    ads.dispose();
  }
}
