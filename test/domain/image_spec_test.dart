import 'package:apple_file_converter/domain/conversion/image_spec.dart';
import 'package:apple_file_converter/domain/media/image_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResizeSpec.resolve', () {
    test('none keeps the original dimensions', () {
      expect(const ResizeSpec.none().resolve(4000, 3000), (4000, 3000));
    });

    test('absolute with locked aspect derives height from width', () {
      const spec = ResizeSpec.absolute(width: 1000, height: 9999);
      expect(spec.resolve(4000, 3000), (1000, 750));
    });

    test('absolute never upscales by default', () {
      const spec = ResizeSpec.absolute(
        width: 8000,
        height: 6000,
        lockAspectRatio: false,
      );
      expect(spec.resolve(2000, 1500), (2000, 1500));
    });

    test('absolute upscales when explicitly allowed', () {
      const spec = ResizeSpec.absolute(
        width: 8000,
        height: 6000,
        lockAspectRatio: false,
        allowUpscale: true,
      );
      expect(spec.resolve(2000, 1500), (8000, 6000));
    });

    test('percentage scales both axes', () {
      expect(const ResizeSpec.percentage(50).resolve(1000, 400), (500, 200));
    });

    test('percentage above 100 does not upscale unless allowed', () {
      expect(const ResizeSpec.percentage(200).resolve(1000, 400), (1000, 400));
    });

    test('longest edge fits the long side and preserves aspect', () {
      expect(const ResizeSpec.longestEdge(1000).resolve(4000, 3000), (
        1000,
        750,
      ));
    });

    test('longest edge leaves smaller images untouched', () {
      expect(const ResizeSpec.longestEdge(4000).resolve(1000, 800), (
        1000,
        800,
      ));
    });

    test('never returns zero dimensions for degenerate input', () {
      expect(const ResizeSpec.percentage(0).resolve(100, 100), (1, 1));
    });

    test('round-trips through JSON', () {
      const original = ResizeSpec.absolute(width: 800, height: 600);
      final decoded = ResizeSpec.fromJson(original.toJson());
      expect(decoded, original);
    });
  });

  group('ImageConversionSpec', () {
    test('effective quality falls back to the format default', () {
      expect(
        const ImageConversionSpec(outputFormat: ImageFormat.png)
            .effectiveQuality,
        100,
      );
      expect(
        const ImageConversionSpec(
          outputFormat: ImageFormat.jpeg,
          quality: 42,
        ).effectiveQuality,
        42,
      );
    });

    test('flags transparency loss when converting to an alpha-less format', () {
      const spec = ImageConversionSpec(outputFormat: ImageFormat.jpeg);
      expect(spec.losesAlpha(ImageFormat.png), isTrue);
      expect(spec.losesAlpha(ImageFormat.bmp), isTrue);
      expect(spec.losesAlpha(ImageFormat.webp), isTrue);
      // Converting *to* an alpha-capable format never discards transparency.
      const toWebp = ImageConversionSpec(outputFormat: ImageFormat.webp);
      expect(toWebp.losesAlpha(ImageFormat.png), isFalse);
    });

    test('webp keeps alpha and reports lossless capability', () {
      expect(ImageFormat.webp.hasAlpha, isTrue);
      expect(ImageFormat.webp.losslessCapable, isTrue);
    });
  });

  group('WatermarkSpec', () {
    test('rejects out-of-range opacity', () {
      expect(
        () => WatermarkSpec(text: 'x', opacity: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
