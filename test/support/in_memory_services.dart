import 'dart:io';

import 'package:apple_file_converter/app/app_services.dart';
import 'package:apple_file_converter/data/history_store.dart';
import 'package:apple_file_converter/data/settings_store.dart';
import 'package:apple_file_converter/domain/media/capability.dart';
import 'package:apple_file_converter/domain/settings/app_settings.dart';
import 'package:apple_file_converter/services/ads/ad_service.dart';
import 'package:apple_file_converter/services/conversion/conversion_coordinator.dart';
import 'package:apple_file_converter/services/conversion/conversion_engine.dart';
import 'package:apple_file_converter/services/conversion/ffmpeg_runner.dart';
import 'package:apple_file_converter/services/conversion/image_conversion_engine.dart';
import 'package:apple_file_converter/services/conversion/media_probe.dart';
import 'package:apple_file_converter/services/conversion/video_conversion_engine.dart';
import 'package:apple_file_converter/services/export/output_exporter.dart';
import 'package:apple_file_converter/services/gallery/gallery_service.dart';
import 'package:apple_file_converter/services/storage/storage_service.dart';
import 'package:apple_file_converter/state/conversion_controller.dart';
import 'package:apple_file_converter/state/gallery_controller.dart';
import 'package:apple_file_converter/state/settings_controller.dart';
import 'package:apple_file_converter/state/shell_controller.dart';

/// A real [FfmpegRunner] that performs no native work. It lets the whole application be built
/// and driven in tests without the FFmpeg binary; any attempt to actually convert fails
/// honestly instead of silently succeeding.
class OfflineFfmpegRunner implements FfmpegRunner {
  const OfflineFfmpegRunner();

  @override
  Future<FfmpegRunResult> runArguments(
    List<String> arguments, {
    Duration? totalDuration,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    return const FfmpegRunResult(
      returnCode: 1,
      errorOutput: 'OfflineFfmpegRunner: no native FFmpeg in tests.',
    );
  }

  @override
  Future<MediaProbeResult> probe(String path) async {
    return const MediaProbeResult(error: 'OfflineFfmpegRunner');
  }

  @override
  Future<EncoderCatalog> encoderCatalog({
    required PlatformKind platform,
  }) async {
    return EncoderCatalog.defaultFor(isApple: platform == PlatformKind.ios);
  }
}

/// Builds a fully in-memory [AppServices] for widget tests: no plugins, no platform channels,
/// no network, no advertising. Storage writes into a throwaway temporary directory.
Future<AppServices> buildTestServices({Directory? directory}) async {
  final root = directory ?? Directory.systemTemp.createTempSync('afc_test_');
  final work = Directory('${root.path}${Platform.pathSeparator}work');
  final exports = Directory('${root.path}${Platform.pathSeparator}exports');

  final historyStore = MemoryHistoryStore();
  final settingsStore = MemorySettingsStore();
  final storage = AppStorageService(
    workDirectoryProvider: () async => work,
    exportDirectoryProvider: () async => exports,
  );

  final coordinator = ConversionCoordinator(
    imageEngine: ImageConversionEngine(),
    videoEngine: VideoConversionEngine(const OfflineFfmpegRunner()),
    historyStore: historyStore,
    exportDestination: const AppSettings().exportDestination,
    exporter: DeviceOutputExporter(storage: storage),
    concurrency: 2,
  );

  final settings = SettingsController(
    store: settingsStore,
    coordinator: coordinator,
    suggestedConcurrency: 2,
  );
  await settings.load();

  const galleryService = UnsupportedGalleryService();
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
    ads: const NoOpAdService(),
    storage: storage,
    coordinator: coordinator,
    galleryService: galleryService,
  );
}

/// Deletes a throwaway test directory. Safe to call more than once.
void disposeTestDirectory(Directory directory) {
  try {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  } catch (_) {
    // Test cleanup is best-effort on Windows where files may still be locked.
  }
}
