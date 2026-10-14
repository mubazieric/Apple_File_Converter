import 'dart:io';

import 'package:apple_file_converter/data/queue_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MemoryQueueStore', () {
    test('round-trips a snapshot and clears', () async {
      final store = MemoryQueueStore();
      expect(await store.load(), isEmpty);

      await store.save(<Map<String, Object?>>[
        <String, Object?>{'id': 'a', 'status': 'queued'},
      ]);
      expect((await store.load()).single['id'], 'a');

      await store.clear();
      expect(await store.load(), isEmpty);
    });
  });

  group('FileQueueStore', () {
    late Directory directory;
    late FileQueueStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('afc_queue_');
      store = FileQueueStore(directoryProvider: () async => directory);
    });

    tearDown(() {
      try {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      } catch (_) {
        // Best-effort cleanup on Windows where files may still be locked.
      }
    });

    File queueFilePath() =>
        File(p.join(directory.path, 'conversion_queue.json'));

    test('persists a snapshot that a fresh instance can read', () async {
      await store.save(<Map<String, Object?>>[
        <String, Object?>{'id': 'a', 'status': 'queued'},
        <String, Object?>{'id': 'b', 'status': 'failed'},
      ]);

      final reloaded = FileQueueStore(directoryProvider: () async => directory);
      final loaded = await reloaded.load();
      expect(loaded.map((map) => map['id']), <String>['a', 'b']);
    });

    test('a missing file loads as an empty queue', () async {
      expect(await store.load(), isEmpty);
    });

    test('a corrupt file loads as empty instead of throwing', () async {
      await queueFilePath().writeAsString('{ this is not valid json');
      expect(await store.load(), isEmpty);
    });

    test('clear removes the persisted file', () async {
      await store.save(<Map<String, Object?>>[
        <String, Object?>{'id': 'a'},
      ]);
      expect(queueFilePath().existsSync(), isTrue);

      await store.clear();
      expect(await store.load(), isEmpty);
    });
  });
}
