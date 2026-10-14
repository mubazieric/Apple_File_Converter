import 'dart:io';

import 'package:apple_file_converter/domain/conversion/conversion_error.dart';
import 'package:apple_file_converter/domain/conversion/conversion_request.dart';
import 'package:apple_file_converter/domain/conversion/image_spec.dart';
import 'package:apple_file_converter/domain/conversion/metadata_policy.dart';
import 'package:apple_file_converter/domain/media/image_format.dart';
import 'package:apple_file_converter/domain/media/media_item.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:apple_file_converter/services/conversion/image_conversion_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Proves the metadata policy is actually applied to image output.
///
/// Before this was implemented the policy was accepted by the UI and passed into the engine but
/// ignored at encode time, so "Remove all" silently kept EXIF. These tests encode a JPEG that
/// carries a DateTime tag and a GPS block, convert it under each policy, and inspect the result.
void main() {
  late Directory dir;
  final engine = ImageConversionEngine();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('afc_meta_');
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

  img.ExifData taggedExif() {
    final exif = img.ExifData();
    exif.imageIfd[0x0132] = img.IfdValueAscii(
      '2020:01:01 00:00:00',
    ); // DateTime
    final gps = img.IfdDirectory();
    gps[0x0001] = img.IfdValueAscii('N'); // GPSLatitudeRef
    exif.imageIfd.sub['gps'] = gps;
    return exif;
  }

  File writeTaggedJpeg() {
    final image = img.Image(width: 8, height: 8);
    for (final pixel in image) {
      pixel
        ..r = 120
        ..g = 130
        ..b = 140
        ..a = 255;
    }
    image.exif = taggedExif();
    final file = File('${dir.path}${Platform.pathSeparator}tagged.jpg');
    file.writeAsBytesSync(img.encodeJpg(image, quality: 90), flush: true);
    return file;
  }

  img.Image decodeOutput(String path) {
    final decoded = img.decodeJpg(File(path).readAsBytesSync());
    expect(decoded, isNotNull, reason: 'output must be a decodable JPEG');
    return decoded!;
  }

  Future<String> convert(File source, MetadataPolicy policy) async {
    final outcome = await engine.convert(
      ImageConversionRequest(
        source: MediaItem(
          id: source.path,
          kind: MediaKind.image,
          displayName: 'tagged.jpg',
          path: source.path,
          imageFormat: ImageFormat.jpeg,
        ),
        spec: const ImageConversionSpec(
          outputFormat: ImageFormat.jpeg,
          quality: 90,
        ),
        metadataPolicy: policy,
        outputDirectory: dir.path,
      ),
    );
    expect(outcome, isA<ConversionSuccess>(), reason: '$outcome');
    return (outcome as ConversionSuccess).outputPath;
  }

  test('the source fixture really carries EXIF with GPS', () {
    final exif = decodeOutput(writeTaggedJpeg().path).exif;
    // The image package always exposes an ExifData object, so `isEmpty`/tag presence are the
    // meaningful signals, not `hasExif`.
    expect(exif.isEmpty, isFalse);
    expect(exif.imageIfd.data.containsKey(0x0132), isTrue); // DateTime
    expect(exif.imageIfd.sub.containsKey('gps'), isTrue);
  });

  test('"Keep all" preserves EXIF including GPS', () async {
    final source = writeTaggedJpeg();
    final exif = decodeOutput(await convert(source, MetadataPolicy.preserve))
        .exif;
    expect(exif.isEmpty, isFalse);
    expect(exif.imageIfd.data.containsKey(0x0132), isTrue);
    expect(exif.imageIfd.sub.containsKey('gps'), isTrue);
  });

  test('"Remove location" keeps other EXIF but drops GPS', () async {
    final source = writeTaggedJpeg();
    final exif = decodeOutput(
      await convert(source, MetadataPolicy.stripLocation),
    ).exif;
    expect(exif.imageIfd.data.containsKey(0x0132), isTrue);
    expect(
      exif.imageIfd.sub.containsKey('gps'),
      isFalse,
      reason: 'GPS block must be removed',
    );
  });

  test('"Remove all" writes no EXIF at all', () async {
    final source = writeTaggedJpeg();
    final exif = decodeOutput(await convert(source, MetadataPolicy.stripAll))
        .exif;
    expect(
      exif.isEmpty,
      isTrue,
      reason: 'Remove all must actually strip metadata',
    );
  });
}
