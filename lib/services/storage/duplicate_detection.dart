import 'dart:io';

import 'package:crypto/crypto.dart';

/// One file participating in a duplicate group.
class DuplicateFile {
  const DuplicateFile({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;

  String get name => path.split(RegExp(r'[\\/]')).last;
}

/// A set of files with identical content (same size and hash).
class DuplicateGroup {
  const DuplicateGroup({required this.hash, required this.files});

  final String hash;
  final List<DuplicateFile> files;

  /// Bytes that could be reclaimed by keeping only the first file.
  int get reclaimableBytes =>
      files.length > 1 ? (files.length - 1) * files.first.sizeBytes : 0;
}

/// Finds exact duplicates by content hash.
///
/// Sizes are compared first so we only hash files that could actually collide. This is used on
/// the app's own export folder where the app has full read/write control; scanning the whole
/// system gallery would require reading every asset and is intentionally not offered.
abstract final class DuplicateDetector {
  static Future<List<DuplicateGroup>> scan(
    Directory root, {
    void Function(int scanned, int total)? onProgress,
  }) async {
    if (!root.existsSync()) {
      return const <DuplicateGroup>[];
    }

    final filesBySize = <int, List<File>>{};
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path != '.DS_Store') {
        filesBySize
            .putIfAbsent(entity.lengthSync(), () => <File>[])
            .add(entity);
      }
    }

    final candidates = filesBySize.values
        .where((files) => files.length > 1)
        .expand((files) => files)
        .toList(growable: false);

    final groups = <DuplicateGroup>[];
    final byHash = <String, List<File>>{};
    for (var i = 0; i < candidates.length; i++) {
      final file = candidates[i];
      byHash.putIfAbsent(_hashOf(file), () => <File>[]).add(file);
      onProgress?.call(i + 1, candidates.length);
    }

    for (final entry in byHash.entries) {
      if (entry.value.length < 2) {
        continue;
      }
      final files =
          entry.value
              .map(
                (file) => DuplicateFile(
                  path: file.path,
                  sizeBytes: file.lengthSync(),
                ),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      groups.add(
        DuplicateGroup(hash: entry.key.substring(0, 12), files: files),
      );
    }
    groups.sort((a, b) => b.reclaimableBytes.compareTo(a.reclaimableBytes));
    return groups;
  }

  static String _hashOf(File file) =>
      md5.convert(file.readAsBytesSync()).toString();
}
