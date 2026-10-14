import 'dart:typed_data';

import 'package:apple_file_converter/domain/format/format_detector.dart';
import 'package:apple_file_converter/domain/media/image_format.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:apple_file_converter/domain/media/video_format.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

Uint8List _ascii(String value, {int pad = 64}) {
  final list = <int>[...value.codeUnits];
  while (list.length < pad) {
    list.add(0);
  }
  return Uint8List.fromList(list);
}

Uint8List _ftyp(String major, {List<String> compatible = const <String>[]}) {
  final list = <int>[0, 0, 0, 0];
  list.addAll('ftyp'.codeUnits);
  list.addAll(major.padRight(4).substring(0, 4).codeUnits);
  list.addAll(<int>[0, 0, 0, 0]);
  for (final brand in compatible) {
    list.addAll(brand.padRight(4).substring(0, 4).codeUnits);
  }
  return Uint8List.fromList(list);
}

void main() {
  group('FormatDetector.detect', () {
    test('returns unknown for empty input', () {
      expect(FormatDetector.detect(Uint8List(0)).isKnown, isFalse);
    });

    test('detects JPEG from SOI marker', () {
      final result = FormatDetector.detect(
        _bytes(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00]),
      );
      expect(result.kind, MediaKind.image);
      expect(result.imageFormat, ImageFormat.jpeg);
    });

    test('detects PNG', () {
      final result = FormatDetector.detect(
        _bytes(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]),
      );
      expect(result.imageFormat, ImageFormat.png);
    });

    test('detects GIF', () {
      expect(
        FormatDetector.detect(_ascii('GIF89a')).imageFormat,
        ImageFormat.gif,
      );
    });

    test('detects BMP', () {
      expect(FormatDetector.detect(_ascii('BM')).imageFormat, ImageFormat.bmp);
    });

    test('detects little- and big-endian TIFF', () {
      expect(
        FormatDetector.detect(_bytes(<int>[0x49, 0x49, 0x2A, 0x00]))
            .imageFormat,
        ImageFormat.tiff,
      );
      expect(
        FormatDetector.detect(_bytes(<int>[0x4D, 0x4D, 0x00, 0x2A]))
            .imageFormat,
        ImageFormat.tiff,
      );
    });

    test('detects ICO', () {
      expect(
        FormatDetector.detect(_bytes(<int>[0x00, 0x00, 0x01, 0x00, 0x01]))
            .imageFormat,
        ImageFormat.ico,
      );
    });

    test('detects WebP via RIFF fourcc', () {
      final result = FormatDetector.detect(_ascii('RIFF????WEBP'));
      expect(result.imageFormat, ImageFormat.webp);
      expect(result.kind, MediaKind.image);
    });

    test('detects AVI via RIFF fourcc', () {
      final result = FormatDetector.detect(_ascii('RIFF????AVI '));
      expect(result.videoContainer, VideoContainer.avi);
      expect(result.kind, MediaKind.video);
    });

    test('detects HEIC ftyp brand', () {
      final result = FormatDetector.detect(_ftyp('heic'));
      expect(result.kind, MediaKind.image);
      expect(result.imageFormat, ImageFormat.heic);
    });

    test('detects AVIF ftyp brand', () {
      final result = FormatDetector.detect(_ftyp('avif'));
      expect(result.imageFormat, ImageFormat.avif);
    });

    test('detects MP4 ftyp brand', () {
      final result = FormatDetector.detect(_ftyp('isom'));
      expect(result.kind, MediaKind.video);
      expect(result.videoContainer, VideoContainer.mp4);
    });

    test('detects QuickTime MOV', () {
      final result = FormatDetector.detect(_ftyp('qt  '));
      expect(result.videoContainer, VideoContainer.mov);
    });

    test('detects 3GP', () {
      final result = FormatDetector.detect(_ftyp('3gp4'));
      expect(result.videoContainer, VideoContainer.threegp);
    });

    test('treats an unrecognised ftyp brand as a tentative ISO-BMFF video', () {
      final result = FormatDetector.detect(_ftyp('zzzz'));
      expect(result.kind, MediaKind.video);
      expect(result.videoContainer, VideoContainer.mp4);
      expect(result.confidence, DetectionConfidence.tentative);
    });

    test('detects Matroska and WebM from EBML', () {
      final mkv = _ascii('\u{1A}E\u{DF}\u{A3}matroska');
      expect(FormatDetector.detect(mkv).videoContainer, VideoContainer.mkv);

      final webm = _ascii('\u{1A}E\u{DF}\u{A3}webm');
      expect(FormatDetector.detect(webm).videoContainer, VideoContainer.webm);
    });

    test('detects ASF/WMV', () {
      final result = FormatDetector.detect(
        _bytes(<int>[0x30, 0x26, 0xB2, 0x75, 0x00]),
      );
      expect(result.videoContainer, VideoContainer.wmv);
    });

    test('detects FLV', () {
      final result = FormatDetector.detect(
        _bytes(<int>[0x46, 0x4C, 0x56, 0x01, 0x00]),
      );
      expect(result.videoContainer, VideoContainer.flv);
    });

    test('detects Ogg Theora video vs Ogg audio', () {
      final video = _ascii('\u{4F}ggS\u{00}theora');
      expect(FormatDetector.detect(video).videoContainer, VideoContainer.ogv);

      final audioOnly = _bytes(<int>[
        0x4F,
        0x67,
        0x67,
        0x53,
        0x00,
        0x02,
        0x00,
        0x00,
      ]);
      expect(FormatDetector.detect(audioOnly).kind, MediaKind.audio);
    });

    test('detects MPEG transport stream by sync bytes', () {
      final list = List<int>.filled(400, 0);
      list[0] = 0x47;
      list[188] = 0x47;
      expect(
        FormatDetector.detect(Uint8List.fromList(list)).videoContainer,
        VideoContainer.ts,
      );
    });

    test('detects MPEG program stream start code', () {
      final result = FormatDetector.detect(
        _bytes(<int>[0x00, 0x00, 0x01, 0xBA, 0x00]),
      );
      expect(result.videoContainer, VideoContainer.mpeg);
    });

    test('detects SVG as a tentative image', () {
      final result = FormatDetector.detect(
        _ascii('<svg xmlns="http://www.w3.org/2000/svg">'),
      );
      expect(result.imageFormat, ImageFormat.svg);
      expect(result.confidence, DetectionConfidence.tentative);
    });
  });

  group('FormatDetector.fromExtension', () {
    test('maps known image and video extensions', () {
      expect(
        FormatDetector.fromExtension('.jpg').imageFormat,
        ImageFormat.jpeg,
      );
      expect(
        FormatDetector.fromExtension('mp4').videoContainer,
        VideoContainer.mp4,
      );
    });

    test('returns unknown for unrecognised extensions', () {
      expect(FormatDetector.fromExtension('xyz').isKnown, isFalse);
    });
  });
}
