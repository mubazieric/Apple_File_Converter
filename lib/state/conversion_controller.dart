import 'package:flutter/foundation.dart';

import '../domain/conversion/conversion_request.dart';
import '../domain/conversion/image_spec.dart';
import '../domain/conversion/presets.dart';
import '../domain/conversion/video_spec.dart';
import '../domain/media/media_item.dart';
import '../services/conversion/conversion_coordinator.dart';
import '../services/storage/storage_service.dart';
import 'gallery_controller.dart';
import 'settings_controller.dart';

/// Outcome of handing a selection to the batch engine.
class ConvertEnqueueResult {
  const ConvertEnqueueResult({
    required this.enqueued,
    required this.unavailable,
  });

  /// Jobs added to the queue.
  final int enqueued;

  /// Items that could not be read (deleted, or iCloud-only and not downloadable).
  final int unavailable;

  bool get hasUnavailable => unavailable > 0;
  bool get nothingToDo => enqueued == 0;
}

/// Edits the current conversion drafts and hands finished requests to the coordinator.
///
/// It is the only place that knows how a UI selection becomes a queue of well-formed requests:
/// resolving source paths, applying the user's metadata/naming policy and choosing the working
/// directory.
class ConversionController extends ChangeNotifier {
  ConversionController({
    required this._coordinator,
    required this._settings,
    required this._gallery,
    required this._storage,
  }) {
    _imageSpec = ImageConversionSpec(
      outputFormat: _settings.settings.defaultImageFormat,
      quality: _settings.settings.defaultImageQuality,
    );
    _videoSpec = _settings.settings.defaultVideoPreset.toSpec().copyWith(
      container: _settings.settings.defaultVideoContainer,
      resolution: _settings.settings.defaultResolution,
      quality: _settings.settings.defaultVideoQuality,
    );
    _settings.addListener(_onSettingsChanged);
  }

  final ConversionCoordinator _coordinator;
  final SettingsController _settings;
  final GalleryController _gallery;
  final StorageService _storage;

  late ImageConversionSpec _imageSpec;
  late VideoConversionSpec _videoSpec;

  ImagePreset _imagePreset = ImagePreset.jpegDefault;
  VideoPreset _videoPreset = VideoPreset.maximumCompatibility;
  bool _busy = false;

  ConversionCoordinator get coordinator => _coordinator;
  ImageConversionSpec get imageSpec => _imageSpec;
  VideoConversionSpec get videoSpec => _videoSpec;
  ImagePreset get imagePreset => _imagePreset;
  VideoPreset get videoPreset => _videoPreset;

  /// True while source paths are being resolved (iCloud downloads can take a moment).
  bool get busy => _busy;

  void applyImagePreset(ImagePreset preset) {
    _imagePreset = preset;
    _imageSpec = preset.toSpec();
    notifyListeners();
  }

  void updateImageSpec(ImageConversionSpec spec) {
    _imageSpec = spec;
    _imagePreset = ImagePreset.custom;
    notifyListeners();
  }

  void applyVideoPreset(VideoPreset preset) {
    _videoPreset = preset;
    _videoSpec = preset.toSpec().copyWith(
      container: _settings.settings.defaultVideoContainer,
      resolution: _settings.settings.defaultResolution,
    );
    notifyListeners();
  }

  void updateVideoSpec(VideoConversionSpec spec) {
    _videoSpec = spec;
    _videoPreset = VideoPreset.custom;
    notifyListeners();
  }

  /// Converts [items] that are images.
  Future<ConvertEnqueueResult> convertImages(
    List<MediaItem> items, {
    ImageConversionSpec? spec,
  }) => _enqueue(
    items.where((item) => item.kind.isImage).toList(),
    imageSpec: spec,
  );

  /// Converts [items] that are videos.
  Future<ConvertEnqueueResult> convertVideos(
    List<MediaItem> items, {
    VideoConversionSpec? spec,
  }) => _enqueue(
    items.where((item) => item.kind.isVideo).toList(),
    videoSpec: spec,
  );

  /// Converts a mixed selection using the current drafts.
  Future<ConvertEnqueueResult> convertSelection(List<MediaItem> items) =>
      _enqueue(items);

  /// Converts a mixed selection with the user's default settings, no configuration UI.
  Future<ConvertEnqueueResult> quickConvert(List<MediaItem> items) {
    final imageItems = items.where((item) => item.kind.isImage).toList();
    final videoItems = items.where((item) => item.kind.isVideo).toList();
    return _enqueue(
      items,
      imageSpec: imageItems.isEmpty
          ? null
          : ImageConversionSpec(
              outputFormat: _settings.settings.defaultImageFormat,
              quality: _settings.settings.defaultImageQuality,
            ),
      videoSpec: videoItems.isEmpty
          ? null
          : _settings.settings.defaultVideoPreset.toSpec().copyWith(
              container: _settings.settings.defaultVideoContainer,
              resolution: _settings.settings.defaultResolution,
              quality: _settings.settings.defaultVideoQuality,
            ),
    );
  }

  Future<ConvertEnqueueResult> _enqueue(
    List<MediaItem> items, {
    ImageConversionSpec? imageSpec,
    VideoConversionSpec? videoSpec,
  }) async {
    if (items.isEmpty) {
      return const ConvertEnqueueResult(enqueued: 0, unavailable: 0);
    }
    _busy = true;
    notifyListeners();
    try {
      final resolved = await _gallery.resolveForConversion(items);
      if (resolved.ready.isEmpty) {
        return ConvertEnqueueResult(
          enqueued: 0,
          unavailable: resolved.unavailable.length,
        );
      }

      final directory = (await _storage.workDirectory()).path;
      final metadata = _settings.metadataPolicy;
      final naming = _settings.namingPolicy;

      final requests = <ConversionRequest>[];
      for (final item in resolved.ready) {
        if (item.kind.isImage) {
          final effective = imageSpec ?? _imageSpec;
          requests.add(
            ImageConversionRequest(
              source: item,
              spec: effective.copyWith(
                keepMetadata: metadata.keepsMetadata,
                stripLocation: metadata.stripsLocation,
              ),
              metadataPolicy: metadata,
              naming: naming,
              outputDirectory: directory,
            ),
          );
        } else if (item.kind.isVideo) {
          final effective = videoSpec ?? _videoSpec;
          requests.add(
            VideoConversionRequest(
              source: item,
              spec: effective.copyWith(keepMetadata: metadata.keepsMetadata),
              metadataPolicy: metadata,
              naming: naming,
              outputDirectory: directory,
            ),
          );
        }
      }

      final enqueued = _coordinator.enqueue(requests);
      return ConvertEnqueueResult(
        enqueued: enqueued,
        unavailable: resolved.unavailable.length,
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _onSettingsChanged() {
    // Settings drive the engine at request time; nothing to copy eagerly.
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
