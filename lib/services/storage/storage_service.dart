import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/media_codec_bridge.dart';

/// A snapshot of storage usage that the storage dashboard can display honestly.
class StorageReport {
  const StorageReport({
    required this.deviceTotalBytes,
    required this.deviceFreeBytes,
    required this.workBytes,
    required this.exportBytes,
    required this.workFileCount,
    required this.exportFileCount,
  });

  /// Null when the OS does not expose it (the UI then says "unavailable").
  final int? deviceTotalBytes;
  final int? deviceFreeBytes;

  /// Bytes held in the app's private working folder (intermediate conversion output).
  final int workBytes;

  /// Bytes held in the app's export folder.
  final int exportBytes;

  final int workFileCount;
  final int exportFileCount;

  bool get hasDeviceInfo =>
      deviceTotalBytes != null && (deviceTotalBytes ?? 0) > 0;

  int get deviceUsedBytes {
    final total = deviceTotalBytes ?? 0;
    final free = deviceFreeBytes ?? 0;
    return (total - free).clamp(0, total);
  }

  int get appManagedBytes => workBytes + exportBytes;

  double get deviceUsedFraction {
    final total = deviceTotalBytes ?? 0;
    return total == 0 ? 0 : (deviceUsedBytes / total).clamp(0, 1).toDouble();
  }
}

/// Storage housekeeping: measuring the app's own folders and clearing intermediate files.
///
/// It only ever touches the app's private working folder and export folder — never the
/// system temp directory and never the user's media.
abstract interface class StorageService {
  Future<StorageReport> report();

  /// Deletes the app's intermediate working files. Returns the number of bytes freed.
  Future<int> cleanWorkFiles();

  /// Where exported files are written for the "app folder" destination.
  Future<Directory> exportDirectory();

  /// The private working directory used for intermediate conversion output.
  Future<Directory> workDirectory();
}

class AppStorageService implements StorageService {
  AppStorageService({
    Future<Directory> Function()? workDirectoryProvider,
    Future<Directory> Function()? exportDirectoryProvider,
    MediaCodecBridge? bridge,
  }) : _workDirectoryProvider = workDirectoryProvider ?? _defaultWorkDirectory,
       _exportDirectoryProvider =
           exportDirectoryProvider ?? _defaultExportDirectory,
       _bridge = bridge ?? MediaCodecBridge();

  final Future<Directory> Function() _workDirectoryProvider;
  final Future<Directory> Function() _exportDirectoryProvider;
  final MediaCodecBridge _bridge;

  static const String _workFolderName = 'apple_file_converter_work';
  static const String _exportFolderName = 'Apple File Converter';

  @override
  Future<Directory> workDirectory() => _ensure(_workDirectoryProvider);

  @override
  Future<Directory> exportDirectory() => _ensure(_exportDirectoryProvider);

  Future<Directory> _ensure(Future<Directory> Function() provider) async {
    final directory = await provider();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<Directory> _defaultWorkDirectory() async {
    final base = await getTemporaryDirectory();
    return Directory(p.join(base.path, _workFolderName));
  }

  static Future<Directory> _defaultExportDirectory() async {
    // Android: app-specific external storage, visible via a file manager / SAF.
    // iOS/macOS: the Documents directory, exposed through the Files app when file sharing is on.
    Directory base;
    if (Platform.isAndroid) {
      base =
          (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    return Directory(p.join(base.path, _exportFolderName));
  }

  @override
  Future<StorageReport> report() async {
    final work = _measure(await workDirectory());
    final exports = _measure(await exportDirectory());
    final device = await _bridge.deviceStorage();
    return StorageReport(
      deviceTotalBytes: device?.totalBytes,
      deviceFreeBytes: device?.freeBytes,
      workBytes: work.bytes,
      exportBytes: exports.bytes,
      workFileCount: work.files,
      exportFileCount: exports.files,
    );
  }

  @override
  Future<int> cleanWorkFiles() async {
    final directory = await workDirectory();
    if (!directory.existsSync()) {
      return 0;
    }
    var freed = 0;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      try {
        freed += entity.lengthSync();
        entity.deleteSync();
      } catch (_) {
        // A file may be locked; skip it rather than failing the whole cleanup.
      }
    }
    return freed;
  }

  static ({int bytes, int files}) _measure(Directory directory) {
    if (!directory.existsSync()) {
      return (bytes: 0, files: 0);
    }
    var bytes = 0;
    var files = 0;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      try {
        bytes += entity.lengthSync();
        files++;
      } catch (_) {
        // Ignore unreadable entries.
      }
    }
    return (bytes: bytes, files: files);
  }
}
