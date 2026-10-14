import 'dart:io';

import 'package:apple_file_converter/domain/conversion/conversion_error.dart';
import 'package:apple_file_converter/domain/conversion/conversion_request.dart';
import 'package:apple_file_converter/domain/conversion/image_spec.dart';
import 'package:apple_file_converter/domain/format/format_detector.dart';
import 'package:apple_file_converter/domain/media/image_format.dart';
import 'package:apple_file_converter/domain/media/media_item.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:apple_file_converter/services/conversion/image_conversion_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// End-to-end tests of the image engine: a real file goes in, a real file comes out, and the
/// output is verified by signature — exactly the path the UI uses. No native bridge is needed
/// for these formats, so this runs anywhere `flutter test` runs.
///
/// The engine itself never touches the network or the platform channel for PNG/JPEG/WebP/etc.
void main() {
  late Directory dir;
  final engine = ImageConversionEngine();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('afc_engine_');
  });

  tearDown(() {
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup on Windows.
    }
  });

  File writeSource(
    String name, {
    required img.Image image,
    ImageFormat format = ImageFormat.png,
  }) {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final bytes = switch (format) {
      ImageFormat.png => img.encodePng(image),
      ImageFormat.jpeg => img.encodeJpg(image),
      _ => img.encodePng(image),
    };
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  MediaItem itemFor(File file, ImageFormat format, {int? width, int? height}) {
    return MediaItem(
      id: file.path,
      kind: MediaKind.image,
      displayName: file.uri.pathSegments.last,
      path: file.path,
      imageFormat: format,
      width: width,
      height: height,
    );
  }

  img.Image sample({int width = 8, int height = 8}) {
    final image = img.Image(width: width, height: height);
    for (final pixel in image) {
      pixel
        ..r = 200
        ..g = 100
        ..b = 50
        ..a = 255;
    }
    return image;
  }

  test('PNG converts to a verified JPEG of the same size', () async {
    final file = writeSource('photo.png', image: sample());
    final request = ImageConversionRequest(
      source: itemFor(file, ImageFormat.png, width: 8, height: 8),
      spec: const ImageConversionSpec(
        outputFormat: ImageFormat.jpeg,
        quality: 90,
      ),
      outputDirectory: dir.path,
    );

    final outcome = await engine.convert(request);

    expect(outcome, isA<ConversionSuccess>(), reason: '$outcome');
    final success = outcome as ConversionSuccess;
    final out = File(success.outputPath);
    expect(out.existsSync(), isTrue);
    expect(success.width, 8);
    expect(success.height, 8);
    final header = out.readAsBytesSync().sublist(0, 3);
    expect(
      FormatDetector.detect(header).imageFormat,
      ImageFormat.jpeg,
      reason: 'output must really be a JPEG',
    );
  });

  test('PNG converts to WebP and is detected as WebP', () async {
    final file = writeSource('photo.png', image: sample());
    final outcome = await engine.convert(
      ImageConversionRequest(
        source: itemFor(file, ImageFormat.png),
        spec: const ImageConversionSpec(outputFormat: ImageFormat.webp),
        outputDirectory: dir.path,
      ),
    );

    expect(outcome, isA<ConversionSuccess>(), reason: '$outcome');
    final out = File((outcome as ConversionSuccess).outputPath);
    expect(
      FormatDetector.detect(out.readAsBytesSync()).imageFormat,
      ImageFormat.webp,
    );
  });

  test('a resize changes the reported dimensions', () async {
    final file = writeSource('big.png', image: sample(width: 40, height: 20));
    final outcome = await engine.convert(
      ImageConversionRequest(
        source: itemFor(file, ImageFormat.png),
        spec: const ImageConversionSpec(
          outputFormat: ImageFormat.png,
          resize: ResizeSpec.longestEdge(10),
        ),
        outputDirectory: dir.path,
      ),
    );

    final success = outcome as ConversionSuccess;
    expect(success.width, 10);
    expect(success.height, 5);
  });

  test('a 90-degree rotation swaps the output axes', () async {
    final file = writeSource('wide.png', image: sample(width: 20, height: 10));
    final outcome = await engine.convert(
      ImageConversionRequest(
        source: itemFor(file, ImageFormat.png),
        spec: const ImageConversionSpec(
          outputFormat: ImageFormat.png,
          rotation: Rotation.clockwise90,
        ),
        outputDirectory: dir.path,
      ),
    );

    final success = outcome as ConversionSuccess;
    expect(success.width, 10);
    expect(success.height, 20);
  });

  test('a corrupt file fails honestly instead of producing output', () async {
    final broken = File('${dir.path}${Platform.pathSeparator}broken.png');
    broken.writeAsBytesSync(<int>[0x6E, 0x6F, 0x74, 0x20, 0x61, 0x6E]);
    final outcome = await engine.convert(
      ImageConversionRequest(
        source: itemFor(broken, ImageFormat.png),
        spec: const ImageConversionSpec(outputFormat: ImageFormat.jpeg),
        outputDirectory: dir.path,
      ),
    );

    expect(outcome, isA<ConversionFailure>());
    final failure = outcome as ConversionFailure;
    expect(failure.error.code, ConversionErrorCode.decodeFailed);
    // No leftover file for a failed conversion.
    final assets = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .toList();
    expect(assets, isEmpty);
  });

  test(
    'two conversions of the same name do not overwrite each other',
    () async {
      final file = writeSource('same.png', image: sample());
      ImageConversionRequest request() => ImageConversionRequest(
        source: itemFor(file, ImageFormat.png),
        spec: const ImageConversionSpec(outputFormat: ImageFormat.png),
        outputDirectory: dir.path,
      );

      final first = await engine.convert(request());
      final second = await engine.convert(request());

      expect(first, isA<ConversionSuccess>());
      expect(second, isA<ConversionSuccess>());
      expect(
        (first as ConversionSuccess).outputPath,
        isNot((second as ConversionSuccess).outputPath),
        reason: 'collision handling must produce a second file',
      );
    },
  );

  test('canHandle is true for a supported decode/encode pair', () async {
    final file = writeSource('any.png', image: sample());
    final supported = await engine.canHandle(
      ImageConversionRequest(
        source: itemFor(file, ImageFormat.png),
        spec: const ImageConversionSpec(outputFormat: ImageFormat.jpeg),
      ),
    );
    expect(supported, isTrue);
  });
}
