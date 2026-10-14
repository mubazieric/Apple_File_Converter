import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists the conversion queue so an interrupted batch is not silently lost on the next
/// launch.
///
/// Only paths, the conversion request (source metadata + spec) and job status are written —
/// never media bytes. The store is deliberately best-effort: a corrupt file yields an empty
/// queue rather than a crash, and a failed write never interrupts a conversion.
abstract interface class QueueStore {
  Future<List<Map<String, Object?>>> load();

  Future<void> save(List<Map<String, Object?>> snapshot);

  Future<void> clear();
}

/// Stores the queue as a single JSON file in the app support directory.
class FileQueueStore implements QueueStore {
  FileQueueStore({
    this.fileName = 'conversion_queue.json',
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final String fileName;
  final Future<Directory> Function() _directoryProvider;
  File? _file;

  Future<File> _resolve() async {
    final existing = _file;
    if (existing != null) {
      return existing;
    }
    final directory = await _directoryProvider();
    final file = File(p.join(directory.path, fileName));
    _file = file;
    return file;
  }

  @override
  Future<List<Map<String, Object?>>> load() async {
    try {
      final file = await _resolve();
      if (!file.existsSync()) {
        return const <Map<String, Object?>>[];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return const <Map<String, Object?>>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <Map<String, Object?>>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map((entry) => entry.cast<String, Object?>())
          .toList(growable: false);
    } catch (_) {
      // A damaged queue file must never stop the app: start with an empty queue instead.
      return const <Map<String, Object?>>[];
    }
  }

  @override
  Future<void> save(List<Map<String, Object?>> snapshot) async {
    try {
      final file = await _resolve();
      file.parent.createSync(recursive: true);
      await file.writeAsString(jsonEncode(snapshot), flush: true);
    } catch (_) {
      // Queue persistence is a convenience; never break the app because of it.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _resolve();
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore.
    }
  }
}

/// Non-persistent queue store for tests and previews.
class MemoryQueueStore implements QueueStore {
  List<Map<String, Object?>> _snapshot = const <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> load() async => _snapshot;

  @override
  Future<void> save(List<Map<String, Object?>> snapshot) async {
    _snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    _snapshot = const <Map<String, Object?>>[];
  }
}
