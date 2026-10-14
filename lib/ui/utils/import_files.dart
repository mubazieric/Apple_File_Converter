import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../domain/format/format_detector.dart';
import '../../domain/media/media_item.dart';

/// Converts a local file into a [MediaItem] using signature/extension detection.
///
/// Dimensions and duration are unknown at import time (they are filled in later by the media
/// probe when the engines run).
Future<MediaItem?> mediaItemFromFile(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final extension = path.contains('.')
      ? path.substring(path.lastIndexOf('.') + 1)
      : '';

  var detected = FormatDetector.fromExtension(extension);
  if (!detected.isKnown) {
    try {
      final raf = await file.open();
      final bytes = await raf.read(64);
      await raf.close();
      detected = FormatDetector.detect(bytes);
    } catch (_) {
      // Keep extension-based detection.
    }
  }

  final stat = file.statSync();
  final name = path.split(RegExp(r'[\\/]')).last;
  return MediaItem(
    id: 'import_${stat.modified.millisecondsSinceEpoch}_${file.lengthSync()}_$name',
    kind: detected.kind,
    displayName: name,
    path: path,
    sizeBytes: file.lengthSync(),
    imageFormat: detected.imageFormat,
    videoContainer: detected.videoContainer,
    availability: MediaAvailability.local,
    createdAt: stat.modified,
    modifiedAt: stat.modified,
  );
}

/// Extensions offered by the system file picker.
const List<String> kImportExtensions = <String>[
  // Images
  'heic', 'heif', 'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tif', 'tiff',
  'ico', 'avif', 'svg', 'jp2', 'dng',
  // Videos
  'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp', '3g2', 'mpg', 'mpeg',
  'm2v', 'ts', 'mts', 'm2ts', 'wmv', 'flv', 'ogv', 'ogg',
];

/// Opens the system file picker for convertible media and returns local [MediaItem]s.
Future<List<MediaItem>> pickMediaFiles() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: kImportExtensions,
  );
  final items = <MediaItem>[];
  for (final file in files) {
    final path = file.path;
    if (path == null || path.isEmpty) {
      continue;
    }
    final item = await mediaItemFromFile(path);
    if (item != null && item.kind.isConvertible) {
      items.add(item);
    }
  }
  return items;
}
