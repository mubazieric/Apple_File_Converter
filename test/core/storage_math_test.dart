import 'package:apple_file_converter/core/utils/storage_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageMath.bytesSaved', () {
    test('is positive when the output is smaller', () {
      expect(StorageMath.bytesSaved(1000, 400), 600);
    });

    test('is negative when the output grows', () {
      expect(StorageMath.bytesSaved(1000, 1500), -500);
    });

    test('is null when either side is unknown', () {
      expect(StorageMath.bytesSaved(null, 100), isNull);
      expect(StorageMath.bytesSaved(100, null), isNull);
    });
  });

  group('StorageMath.savedFraction', () {
    test('computes a clamped fraction', () {
      expect(StorageMath.savedFraction(1000, 250), 0.75);
      expect(StorageMath.savedFraction(1000, 3000), -1.0);
    });

    test('is null for a non-positive source', () {
      expect(StorageMath.savedFraction(0, 100), isNull);
    });
  });

  group('StorageMath aggregates', () {
    test('totalSaved ignores unknown pairs', () {
      final total = StorageMath.totalSaved(<(int?, int?)>[
        (1000, 400),
        (null, 100),
        (2000, 2000),
      ]);
      expect(total, 600);
    });

    test('aggregateFraction is total-based', () {
      final fraction = StorageMath.aggregateFraction(<(int?, int?)>[
        (1000, 500),
        (9000, 4500),
      ]);
      expect(fraction, closeTo(0.5, 0.0001));
    });

    test('aggregateFraction is null when nothing is known', () {
      expect(
        StorageMath.aggregateFraction(<(int?, int?)>[(null, null)]),
        isNull,
      );
    });
  });

  group('StorageMath storage checks', () {
    test('fitsInStorage applies a safety margin', () {
      expect(
        StorageMath.fitsInStorage(estimatedBytes: 800, freeBytes: 1000),
        isTrue,
      );
      expect(
        StorageMath.fitsInStorage(estimatedBytes: 900, freeBytes: 1000),
        isFalse,
      );
    });

    test('fitsInStorage is false with no free space', () {
      expect(
        StorageMath.fitsInStorage(estimatedBytes: 1, freeBytes: 0),
        isFalse,
      );
    });

    test('pressure maps free-space ratios to levels', () {
      expect(
        StorageMath.pressure(freeBytes: 4, totalBytes: 100),
        StoragePressure.critical,
      );
      expect(
        StorageMath.pressure(freeBytes: 10, totalBytes: 100),
        StoragePressure.warning,
      );
      expect(
        StorageMath.pressure(freeBytes: 40, totalBytes: 100),
        StoragePressure.ok,
      );
      expect(
        StorageMath.pressure(freeBytes: 1, totalBytes: 0),
        StoragePressure.unknown,
      );
    });
  });
}
