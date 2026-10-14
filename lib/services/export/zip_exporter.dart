import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// The outcome of archiving a set of finished outputs.
class ZipResult {
  const ZipResult({
    this.outputPath,
    this.bytes = 0,
    this.fileCount = 0,
    this.error,
  });

  /// Absolute path of the written ZIP, or null on failure.
  final String? outputPath;

  /// Size of the written ZIP in bytes.
  final int bytes;

  /// How many source files were included.
  final int fileCount;

  /// A short, user-facing reason when the archive could not be produced.
  final String? error;

  bool get isSuccess => outputPath != null && error == null;
}

/// Bundles completed output files into a single ZIP.
///
/// This is pure Dart (the `archive` package), so it is fully unit-testable and needs no native
/// code. Missing source files are skipped rather than failing the whole archive, and duplicate
/// base names are disambiguated so the archive is always a valid ZIP.
abstract interface class ZipExporter {
  Future<ZipResult> zipFiles(List<String> paths, {required String outputPath});
}

class ArchiveZipExporter implements ZipExporter {
  const ArchiveZipExporter();

  @override
  Future<ZipResult> zipFiles(
    List<String> paths, {
    required String outputPath,
  }) async {
    try {
      final archive = Archive();
      final usedNames = <String>{};
      var fileCount = 0;

      for (final path in paths) {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }
        final name = _uniqueName(p.basename(path), usedNames);
        archive.addFile(ArchiveFile.bytes(name, await file.readAsBytes()));
        fileCount++;
      }

      if (fileCount == 0) {
        return const ZipResult(error: 'There are no output files to archive.');
      }

      final bytes = ZipEncoder().encodeBytes(archive);
      final output = File(outputPath);
      output.parent.createSync(recursive: true);
      await output.writeAsBytes(bytes, flush: true);

      return ZipResult(
        outputPath: outputPath,
        bytes: bytes.length,
        fileCount: fileCount,
      );
    } catch (error) {
      return ZipResult(
        error: 'The ZIP could not be created (${error.runtimeType}).',
      );
    }
  }

  /// Returns [name] if unused, otherwise `base (2).ext`, `base (3).ext`, …
  static String _uniqueName(String name, Set<String> used) {
    if (used.add(name)) {
      return name;
    }
    final base = p.basenameWithoutExtension(name);
    final extension = p.extension(name);
    var index = 2;
    var candidate = '$base ($index)$extension';
    while (!used.add(candidate)) {
      index++;
      candidate = '$base ($index)$extension';
    }
    return candidate;
  }
}
