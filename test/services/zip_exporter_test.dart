import 'dart:io';

import 'package:apple_file_converter/services/export/zip_exporter.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// ZIP export is pure Dart, so it is fully testable here. These tests prove the archive is a
/// real ZIP (correct magic bytes and readable entries), that missing files are skipped rather
/// than corrupting the archive, and that a no-op request fails honestly.
void main() {
  late Directory dir;
  const exporter = ArchiveZipExporter();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('afc_zip_');
  });

  tearDown(() {
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Best-effort on Windows.
    }
  });

  File writeFile(String name, String content) {
    final file = File(p.join(dir.path, name));
    file.writeAsStringSync(content);
    return file;
  }

  String outPath() => p.join(dir.path, 'archive.zip');

  test('archives the given files into a readable ZIP', () async {
    final a = writeFile('a.jpg', 'jpeg-bytes');
    final b = writeFile('b.png', 'png-bytes');
    final output = outPath();

    final result = await exporter.zipFiles(<String>[
      a.path,
      b.path,
    ], outputPath: output);

    expect(result.isSuccess, isTrue, reason: result.error);
    expect(result.fileCount, 2);
    expect(result.bytes, greaterThan(0));

    final bytes = File(output).readAsBytesSync();
    expect(bytes.sublist(0, 2), <int>[
      0x50,
      0x4B,
    ], reason: 'a ZIP starts with "PK"');

    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.files.map((file) => file.name).toSet(),
      containsAll(<String>['a.jpg', 'b.png']),
    );
  });

  test('skips files that no longer exist', () async {
    final a = writeFile('a.jpg', 'x');

    final result = await exporter.zipFiles(<String>[
      a.path,
      p.join(dir.path, 'gone.jpg'),
    ], outputPath: outPath());

    expect(result.isSuccess, isTrue);
    expect(result.fileCount, 1);
  });

  test('fails honestly when there is nothing to archive', () async {
    final output = outPath();

    final result = await exporter.zipFiles(<String>[
      p.join(dir.path, 'missing.jpg'),
    ], outputPath: output);

    expect(result.isSuccess, isFalse);
    expect(result.error, isNotNull);
    expect(
      File(output).existsSync(),
      isFalse,
      reason: 'no empty archive should be left behind',
    );
  });

  test('duplicate base names are disambiguated inside the archive', () async {
    final first = Directory(p.join(dir.path, 'one'))..createSync();
    final second = Directory(p.join(dir.path, 'two'))..createSync();
    final f1 = File(p.join(first.path, 'x.jpg'))..writeAsStringSync('1');
    final f2 = File(p.join(second.path, 'x.jpg'))..writeAsStringSync('2');
    final output = outPath();

    final result = await exporter.zipFiles(<String>[
      f1.path,
      f2.path,
    ], outputPath: output);

    expect(result.fileCount, 2);
    final archive = ZipDecoder().decodeBytes(File(output).readAsBytesSync());
    final names = archive.files.map((file) => file.name).toList();
    expect(names.toSet().length, 2, reason: 'names must be unique: $names');
  });
}
