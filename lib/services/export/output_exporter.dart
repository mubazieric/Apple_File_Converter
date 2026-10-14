import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/media/media_kind.dart';
import '../../domain/settings/app_settings.dart';
import '../platform/media_codec_bridge.dart';
import '../storage/storage_service.dart';

/// Where a finished conversion ended up.
class ExportResult {
  const ExportResult({
    required this.path,
    this.savedToPhotos = false,
    this.photoLibraryError,
  });

  /// The stable, app-accessible path of the output.
  final String path;

  /// True when a copy was also written into the system photo library.
  final bool savedToPhotos;

  /// Populated when the photo-library copy failed; the local file still exists.
  final String? photoLibraryError;

  bool get hasPhotoLibraryError => photoLibraryError != null;
}

/// Moves finished conversion output to its final destination.
///
/// The conversion engines write into the app's private working folder; this is the single
/// place that decides where the user will actually find the file. It never deletes or modifies
/// the original media.
abstract interface class OutputExporter {
  Future<ExportResult> export({
    required String filePath,
    required MediaKind kind,
    required ExportDestination destination,
    String? customDirectory,
  });
}

/// The real implementation: the app export folder, an optional user-picked folder, and an
/// optional copy into the system photo library.
class DeviceOutputExporter implements OutputExporter {
  DeviceOutputExporter({required this._storage, MediaCodecBridge? bridge})
    : _bridge = bridge ?? MediaCodecBridge();

  final StorageService _storage;
  final MediaCodecBridge _bridge;

  @override
  Future<ExportResult> export({
    required String filePath,
    required MediaKind kind,
    required ExportDestination destination,
    String? customDirectory,
  }) async {
    Directory target;
    switch (destination) {
      case ExportDestination.customFolder:
        final custom = customDirectory;
        target = (custom != null && custom.trim().isNotEmpty)
            ? Directory(custom)
            : await _storage.exportDirectory();
      case ExportDestination.appFolder:
      case ExportDestination.gallery:
        target = await _storage.exportDirectory();
    }

    final finalPath = await _place(filePath, target);

    if (destination != ExportDestination.gallery) {
      return ExportResult(path: finalPath);
    }

    // Destination "Photos": also write a copy into the system library. The local file is kept
    // so the user can still share or re-open the result from the app; the storage dashboard
    // shows this folder and lets the user clear it.
    try {
      final identifier = await _bridge.saveToPhotoLibrary(
        finalPath,
        isVideo: kind.isVideo,
      );
      if (identifier == null) {
        return ExportResult(
          path: finalPath,
          photoLibraryError:
              'The file was saved to the app folder but could not be added to Photos. '
              'You can still share it from here.',
        );
      }
      return ExportResult(path: finalPath, savedToPhotos: true);
    } catch (_) {
      return ExportResult(
        path: finalPath,
        photoLibraryError:
            'The file was saved to the app folder but could not be added to Photos. '
            'You can still share it from here.',
      );
    }
  }

  /// Moves [filePath] into [target], resolving name collisions, and returns the new path.
  static Future<String> _place(String filePath, Directory target) async {
    final source = File(filePath);
    if (!source.existsSync()) {
      return filePath;
    }
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }
    final sourceDir = p.dirname(source.path);
    if (p.equals(sourceDir, target.path)) {
      return source.path;
    }

    final base = p.basenameWithoutExtension(source.path);
    final extension = p.extension(source.path);
    var candidate = p.join(target.path, '$base$extension');
    var index = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(target.path, '$base ($index)$extension');
      index++;
    }
    try {
      return (await source.rename(candidate)).path;
    } on FileSystemException {
      // Different volumes: copy then remove the working copy.
      try {
        final moved = await source.copy(candidate);
        try {
          await source.delete();
        } catch (_) {
          // Leave the working copy if it cannot be removed; not fatal.
        }
        return moved.path;
      } catch (_) {
        return source.path;
      }
    }
  }
}

/// Exporter used in tests and on platforms without a photo library: no-op.
class PassthroughExporter implements OutputExporter {
  const PassthroughExporter();

  @override
  Future<ExportResult> export({
    required String filePath,
    required MediaKind kind,
    required ExportDestination destination,
    String? customDirectory,
  }) async => ExportResult(path: filePath);
}
