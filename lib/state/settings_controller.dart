import 'package:flutter/foundation.dart';

import '../data/settings_store.dart';
import '../domain/conversion/metadata_policy.dart';
import '../domain/conversion/naming_policy.dart';
import '../domain/conversion/presets.dart';
import '../domain/conversion/video_spec.dart';
import '../domain/media/image_format.dart';
import '../domain/media/video_format.dart';
import '../domain/settings/app_settings.dart';
import '../services/conversion/conversion_coordinator.dart';

/// Owns [AppSettings]: loads them once, exposes immutable snapshots to the UI, persists every
/// change, and pushes the runtime-affecting ones (concurrency, export destination) into the
/// conversion coordinator.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required this._store,
    required this._coordinator,
    int suggestedConcurrency = 2,
  }) : _suggestedConcurrency = suggestedConcurrency.clamp(1, 8);

  final SettingsStore _store;
  final ConversionCoordinator _coordinator;
  final int _suggestedConcurrency;

  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get isLoaded => _loaded;

  /// The device-derived default the UI shows when the user has not overridden concurrency.
  int get suggestedConcurrency => _suggestedConcurrency;

  MetadataPolicy get metadataPolicy => _settings.metadataPolicy;
  NamingPolicy get namingPolicy => _settings.namingPolicy;

  Future<void> load() async {
    _settings = await _store.load();
    _loaded = true;
    _applyRuntime();
    notifyListeners();
  }

  Future<void> _update(AppSettings next) async {
    _settings = next;
    _applyRuntime();
    notifyListeners();
    await _store.save(next);
  }

  void _applyRuntime() {
    _coordinator.setConcurrency(
      _settings.effectiveConcurrency(_suggestedConcurrency),
    );
    _coordinator.updateExportDestination(
      destination: _settings.exportDestination,
      customDirectory: _settings.customExportPath,
    );
  }

  Future<void> setTheme(ThemePreference value) =>
      _update(_settings.copyWith(theme: value));

  Future<void> setDefaultImageFormat(ImageFormat value) =>
      _update(_settings.copyWith(defaultImageFormat: value));

  Future<void> setDefaultImageQuality(int value) =>
      _update(_settings.copyWith(defaultImageQuality: value.clamp(1, 100)));

  Future<void> setDefaultImagePreset(ImagePreset value) =>
      _update(_settings.copyWith(defaultImagePreset: value));

  Future<void> setDefaultVideoContainer(VideoContainer value) =>
      _update(_settings.copyWith(defaultVideoContainer: value));

  Future<void> setDefaultVideoPreset(VideoPreset value) =>
      _update(_settings.copyWith(defaultVideoPreset: value));

  Future<void> setDefaultVideoQuality(VideoQuality value) =>
      _update(_settings.copyWith(defaultVideoQuality: value));

  Future<void> setDefaultResolution(ResolutionPreset value) =>
      _update(_settings.copyWith(defaultResolution: value));

  Future<void> setMetadataPolicy(MetadataPolicy value) =>
      _update(_settings.copyWith(metadataPolicy: value));

  Future<void> setNamingTemplate(String value) => _update(
    _settings.copyWith(
      namingTemplate: value.trim().isEmpty
          ? NamingPolicy.defaultTemplate
          : value.trim(),
    ),
  );

  Future<void> setExportDestination(
    ExportDestination value, {
    String? customPath,
  }) => _update(
    _settings.copyWith(
      exportDestination: value,
      customExportPath: customPath,
      clearCustomExportPath: value != ExportDestination.customFolder,
    ),
  );

  Future<void> setBatchConcurrency(int? value) => _update(
    _settings.copyWith(
      batchConcurrency: value,
      clearBatchConcurrency: value == null,
    ),
  );

  Future<void> setConfirmBeforeDelete(bool value) =>
      _update(_settings.copyWith(confirmBeforeDelete: value));

  Future<void> setGalleryLayout(GalleryLayout value) =>
      _update(_settings.copyWith(galleryLayout: value));

  Future<void> setGalleryGridColumns(int value) =>
      _update(_settings.copyWith(galleryGridColumns: value.clamp(2, 6)));

  Future<void> setGallerySort(SortField value, {bool? ascending}) => _update(
    _settings.copyWith(gallerySort: value, gallerySortAscending: ascending),
  );

  Future<void> setLanguageCode(String value) =>
      _update(_settings.copyWith(languageCode: value));

  Future<void> markAdsConsentDecided() =>
      _update(_settings.copyWith(adsConsentDecided: true));
}
