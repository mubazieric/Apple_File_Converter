import 'package:apple_file_converter/core/utils/byte_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ByteFormat.binary', () {
    test('formats small values in bytes', () {
      expect(ByteFormat.binary(0), '0 B');
      expect(ByteFormat.binary(999), '999 B');
    });

    test('scales to KB/MB/GB with one decimal', () {
      expect(ByteFormat.binary(1500), '1.5 KB');
      expect(ByteFormat.binary(2500000), '2.5 MB');
      expect(ByteFormat.binary(3000000000), '3.0 GB');
    });

    test('omits decimals for large magnitudes', () {
      expect(ByteFormat.binary(123400000), '123 MB');
    });

    test('never throws on unknown values', () {
      expect(ByteFormat.binary(null), ByteFormat.unknown);
      expect(ByteFormat.binary(-1), ByteFormat.unknown);
    });
  });

  group('ByteFormat.difference', () {
    test('uses a true minus sign for savings and plus for growth', () {
      expect(ByteFormat.difference(2048), '−2.0 KB');
      expect(ByteFormat.difference(-2048), '+2.0 KB');
      expect(ByteFormat.difference(0), '0 B');
    });
  });

  group('ByteFormat.percent', () {
    test('converts fractions to percentages', () {
      expect(ByteFormat.percent(0.5), '50%');
      expect(ByteFormat.percent(0.123, decimals: 1), '12.3%');
    });

    test('handles invalid input', () {
      expect(ByteFormat.percent(null), ByteFormat.unknown);
      expect(ByteFormat.percent(double.nan), ByteFormat.unknown);
    });
  });

  group('ByteFormat.duration', () {
    test('formats under an hour as m:ss', () {
      expect(
        ByteFormat.duration(const Duration(minutes: 3, seconds: 7)),
        '3:07',
      );
    });

    test('formats an hour or more as h:mm:ss', () {
      expect(
        ByteFormat.duration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('handles negatives as unknown', () {
      expect(
        ByteFormat.duration(const Duration(seconds: -5)),
        ByteFormat.unknown,
      );
    });
  });

  group('ByteFormat.durationPrecise', () {
    test('appends tenths of a second', () {
      expect(
        ByteFormat.durationPrecise(
          const Duration(minutes: 1, seconds: 2, milliseconds: 300),
        ),
        '1:02.3',
      );
    });
  });

  group('ByteFormat.count', () {
    test('abbreviates thousands and millions', () {
      expect(ByteFormat.count(999), '999');
      expect(ByteFormat.count(1500), '1.5k');
      expect(ByteFormat.count(1500000), '1.5M');
    });
  });
}
