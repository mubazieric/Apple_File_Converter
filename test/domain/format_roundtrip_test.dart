import 'dart:typed_data';

import 'package:apple_file_converter/domain/format/format_detector.dart';
import 'package:apple_file_converter/domain/media/image_format.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Round-trips real encoder output through the signature detector.
///
/// The other detector tests use hand-written header bytes; this one encodes an actual image with
/// the same `image` package the conversion engine uses and checks the detector recognises the
/// result. That is what guarantees "we detect our own output", so a conversion can be validated
/// instead of trusted by extension.
void main() {
  img.Image sample() {
    final image = img.Image(width: 8, height: 8);
    for (final pixel in image) {
      pixel
        ..r = pixel.x * 20
        ..g = pixel.y * 20
        ..b = 128
        ..a = 255;
    }
    return image;
  }

  final encoders = <ImageFormat, Uint8List Function(img.Image)>{
    ImageFormat.jpeg: img.encodeJpg,
    ImageFormat.png: img.encodePng,
    ImageFormat.gif: img.encodeGif,
    ImageFormat.bmp: img.encodeBmp,
    ImageFormat.tiff: img.encodeTiff,
    ImageFormat.ico: img.encodeIco,
    ImageFormat.webp: img.encodeWebP,
  };

  group('FormatDetector recognises real encoder output', () {
    encoders.forEach((format, encode) {
      test('detects ${format.label} produced by the engine encoder', () {
        final bytes = encode(sample());
        expect(
          bytes,
          isNotEmpty,
          reason: '${format.id} encoder produced nothing',
        );
        final detected = FormatDetector.detect(bytes);
        expect(detected.kind, MediaKind.image);
        expect(
          detected.imageFormat,
          format,
          reason: 'detected ${detected.imageFormat.id} for ${format.id}',
        );
      });
    });

    test('a JPEG with a .png extension is still detected as JPEG', () {
      final bytes = img.encodeJpg(sample());
      final detected = FormatDetector.detect(bytes);
      expect(detected.imageFormat, ImageFormat.jpeg);
      expect(FormatDetector.fromExtension('png').imageFormat, ImageFormat.png);
      // i.e. the signature, not the name, wins.
      expect(
        detected.imageFormat,
        isNot(FormatDetector.fromExtension('png').imageFormat),
      );
    });
  });
}
