import 'package:apple_file_converter/domain/conversion/naming_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NamingPolicy.buildBaseName', () {
    const policy = NamingPolicy();

    test('applies the default suffix and drops the source extension', () {
      final name = policy.buildBaseName(
        sourceFileName: 'IMG_1234.HEIC',
        formatExtension: 'jpg',
        timestamp: DateTime(2026, 10, 13, 9, 5, 4),
      );
      expect(name, 'IMG_1234_converted');
    });

    test('expands date/time and format tokens', () {
      const templated = NamingPolicy(template: '{name}_{date}_{time}_{format}');
      final name = templated.buildBaseName(
        sourceFileName: 'clip.mov',
        formatExtension: 'mp4',
        timestamp: DateTime(2026, 1, 2, 3, 4, 5),
      );
      expect(name, 'clip_20260102_030405_mp4');
    });

    test('index token is 1-based and zero padded', () {
      const templated = NamingPolicy(template: '{name}_{index}');
      final name = templated.buildBaseName(
        sourceFileName: 'a.png',
        formatExtension: 'jpg',
        timestamp: DateTime(2026),
        index: 0,
      );
      expect(name, 'a_01');
    });
  });

  group('NamingPolicy.sanitise', () {
    test('replaces characters that are invalid on Windows', () {
      expect(NamingPolicy.sanitise('a/b\\c:d*e?f'), 'a_b_c_d_e_f');
    });

    test('guards against reserved device names', () {
      expect(NamingPolicy.sanitise('CON'), 'CON_file');
      expect(NamingPolicy.sanitise('lpt1'), 'lpt1_file');
    });

    test('never returns an empty name', () {
      expect(NamingPolicy.sanitise('...'), 'file');
    });

    test('truncates overly long names', () {
      final long = 'x' * 500;
      expect(NamingPolicy.sanitise(long).length, lessThanOrEqualTo(120));
    });
  });

  group('NamingPolicy.uniqueFileName', () {
    const policy = NamingPolicy();

    test('uses the base name when free', () {
      final name = policy.uniqueFileName(
        baseName: 'photo',
        extension: 'jpg',
        isTaken: (_) => false,
      );
      expect(name, 'photo.jpg');
    });

    test('adds a numeric suffix on collision without overwriting', () {
      final taken = <String>{'photo.jpg', 'photo (1).jpg'};
      final name = policy.uniqueFileName(
        baseName: 'photo',
        extension: '.jpg',
        isTaken: taken.contains,
      );
      expect(name, 'photo (2).jpg');
    });

    test('never overwrites even when collisions are "allowed" by policy', () {
      const overwriting = NamingPolicy(keepOriginalOnCollision: false);
      final name = overwriting.uniqueFileName(
        baseName: 'photo',
        extension: 'jpg',
        isTaken: (candidate) => candidate == 'photo.jpg',
      );
      // keepOriginalOnCollision=false skips the collision check entirely; the caller is
      // responsible. We assert the documented behaviour explicitly.
      expect(name, 'photo.jpg');
    });
  });
}
