import 'dart:typed_data';

import '../media/image_format.dart';
import '../media/media_kind.dart';
import '../media/video_format.dart';

/// The result of inspecting the leading bytes of a file.
class DetectedFormat {
  const DetectedFormat({
    required this.kind,
    this.imageFormat = ImageFormat.unknown,
    this.videoContainer = VideoContainer.unknown,
    this.containerBrand,
    this.confidence = DetectionConfidence.definite,
  });

  final MediaKind kind;
  final ImageFormat imageFormat;
  final VideoContainer videoContainer;

  /// Raw `ftyp` brand or EBML doc-type, useful for diagnostics and the capability matrix.
  final String? containerBrand;

  final DetectionConfidence confidence;

  bool get isKnown => kind != MediaKind.unknown;
  bool get isImage => kind == MediaKind.image;
  bool get isVideo => kind == MediaKind.video;

  static const DetectedFormat unknown = DetectedFormat(kind: MediaKind.unknown);

  @override
  String toString() =>
      'DetectedFormat(kind: $kind, image: ${imageFormat.id}, video: ${videoContainer.id}, '
      'brand: $containerBrand, confidence: $confidence)';
}

enum DetectionConfidence {
  /// A magic-number match — trustworthy.
  definite,

  /// Only an extension or a heuristic was available.
  tentative,

  /// Nothing matched.
  none,
}

/// Signature-based format detection.
///
/// This module is pure Dart and has no I/O, so it is exhaustively unit-testable. It is the
/// single source of truth used by both the importer and the output validator: we never trust a
/// file extension alone.
abstract final class FormatDetector {
  /// JPEG SOI + marker.
  static bool _isJpeg(Uint8List b) =>
      b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

  static bool _startsWith(Uint8List b, List<int> sig, [int offset = 0]) {
    if (b.length < offset + sig.length) {
      return false;
    }
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) {
        return false;
      }
    }
    return true;
  }

  static String _ascii(Uint8List b, int start, int length) {
    if (b.length < start + length) {
      return '';
    }
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.writeCharCode(b[start + i]);
    }
    return buffer.toString();
  }

  /// Inspects the first bytes of [bytes] and returns the detected format.
  ///
  /// [bytes] should contain at least the first 64 bytes of the file for best accuracy, but a
  /// shorter buffer will still be handled gracefully.
  static DetectedFormat detect(Uint8List bytes) {
    if (bytes.isEmpty) {
      return DetectedFormat.unknown;
    }

    // --- Images ---------------------------------------------------------------
    if (_isJpeg(bytes)) {
      return const DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.jpeg,
      );
    }
    if (_startsWith(bytes, <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ])) {
      return const DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.png,
      );
    }
    if (_startsWith(bytes, <int>[0x47, 0x49, 0x46, 0x38])) {
      // "GIF8" — 7a/9a follows.
      return const DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.gif,
      );
    }
    if (_startsWith(bytes, <int>[0x42, 0x4D])) {
      return const DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.bmp,
      );
    }
    if (_startsWith(bytes, <int>[0x49, 0x49, 0x2A, 0x00]) ||
        _startsWith(bytes, <int>[0x4D, 0x4D, 0x00, 0x2A])) {
      // TIFF; DNG shares this container but is only treated as DNG when the extension says so.
      return const DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.tiff,
      );
    }
    if (_startsWith(bytes, <int>[0x00, 0x00, 0x01, 0x00])) {
      return const DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.ico,
      );
    }
    if (_startsWith(bytes, <int>[
      0x00,
      0x00,
      0x00,
      0x0C,
      0x6A,
      0x50,
      0x20,
      0x20,
    ])) {
      return const DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.jp2,
      );
    }

    // WBMP: fixed header 0x00 0x00 (type 0, no fixed header). Ambiguous with other 0x00
    // leaders, so it is only accepted as a tentative match.
    if (_startsWith(bytes, <int>[0x00, 0x00]) &&
        bytes.length > 4 &&
        bytes[2] == 0x00) {
      // Defer: handled below by extension fallback. Avoid false positives.
    }

    // --- RIFF family ----------------------------------------------------------
    if (_startsWith(bytes, <int>[0x52, 0x49, 0x46, 0x46])) {
      final fourcc = _ascii(bytes, 8, 4);
      switch (fourcc) {
        case 'WEBP':
          return const DetectedFormat(
            kind: MediaKind.image,
            imageFormat: ImageFormat.webp,
          );
        case 'AVI ':
          return const DetectedFormat(
            kind: MediaKind.video,
            videoContainer: VideoContainer.avi,
            containerBrand: 'AVI',
          );
      }
    }

    // --- ISO base media (ftyp) -----------------------------------------------
    if (_ascii(bytes, 4, 4) == 'ftyp') {
      final brands = _ftypBrands(bytes);
      final major = brands.isNotEmpty ? brands.first : '';
      final combined = brands.map((b) => b.trim()).toSet();
      return _fromFtyp(major.trim(), combined);
    }

    // --- Matroska / WebM (EBML) ----------------------------------------------
    if (_startsWith(bytes, <int>[0x1A, 0x45, 0xDF, 0xA3])) {
      final head = _ascii(bytes, 0, bytes.length);
      final isWebm = head.contains('webm');
      return DetectedFormat(
        kind: MediaKind.video,
        videoContainer: isWebm ? VideoContainer.webm : VideoContainer.mkv,
        containerBrand: isWebm ? 'webm' : 'matroska',
      );
    }

    // --- ASF / WMV ------------------------------------------------------------
    if (_startsWith(bytes, <int>[0x30, 0x26, 0xB2, 0x75])) {
      return const DetectedFormat(
        kind: MediaKind.video,
        videoContainer: VideoContainer.wmv,
        containerBrand: 'asf',
      );
    }

    // --- FLV ------------------------------------------------------------------
    if (_startsWith(bytes, <int>[0x46, 0x4C, 0x56, 0x01])) {
      return const DetectedFormat(
        kind: MediaKind.video,
        videoContainer: VideoContainer.flv,
        containerBrand: 'flv',
      );
    }

    // --- Ogg ------------------------------------------------------------------
    if (_startsWith(bytes, <int>[0x4F, 0x67, 0x67, 0x53])) {
      final head = _ascii(bytes, 0, bytes.length);
      if (head.contains('theora') || head.contains('video')) {
        return const DetectedFormat(
          kind: MediaKind.video,
          videoContainer: VideoContainer.ogv,
          containerBrand: 'ogg',
        );
      }
      return const DetectedFormat(kind: MediaKind.audio, containerBrand: 'ogg');
    }

    // --- MPEG transport stream ------------------------------------------------
    if (bytes.length >= 377 && bytes[0] == 0x47 && bytes[188] == 0x47) {
      return const DetectedFormat(
        kind: MediaKind.video,
        videoContainer: VideoContainer.ts,
        containerBrand: 'mpegts',
      );
    }

    // --- MPEG program stream / elementary -------------------------------------
    if (_startsWith(bytes, <int>[0x00, 0x00, 0x01, 0xBA]) ||
        _startsWith(bytes, <int>[0x00, 0x00, 0x01, 0xB3])) {
      return const DetectedFormat(
        kind: MediaKind.video,
        videoContainer: VideoContainer.mpeg,
        containerBrand: 'mpeg',
      );
    }

    // --- SVG (text based) -----------------------------------------------------
    final head = _ascii(
      bytes,
      0,
      bytes.length < 512 ? bytes.length : 512,
    ).trimLeft();
    if (head.startsWith('<?xml') || head.startsWith('<svg')) {
      if (head.contains('<svg')) {
        return const DetectedFormat(
          kind: MediaKind.image,
          imageFormat: ImageFormat.svg,
          confidence: DetectionConfidence.tentative,
        );
      }
    }

    return DetectedFormat.unknown;
  }

  static DetectedFormat _fromFtyp(String major, Set<String> brands) {
    bool has(String b) => brands.contains(b) || major == b;

    if (has('avif') || has('avis')) {
      return DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.avif,
        containerBrand: major,
      );
    }
    const heicBrands = <String>{
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'hevm',
      'hevs',
    };
    if (heicBrands.contains(major) || brands.any(heicBrands.contains)) {
      return DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.heic,
        containerBrand: major,
      );
    }
    if (has('mif1') || has('msf1') || major == 'mif1') {
      return DetectedFormat(
        kind: MediaKind.image,
        imageFormat: ImageFormat.heif,
        containerBrand: major,
      );
    }
    if (has('M4V') || has('M4VH') || has('M4VP')) {
      return DetectedFormat(
        kind: MediaKind.video,
        videoContainer: VideoContainer.m4v,
        containerBrand: major,
      );
    }
    if (major == 'qt') {
      return DetectedFormat(
        kind: MediaKind.video,
        videoContainer: VideoContainer.mov,
        containerBrand: major,
      );
    }
    const threeGp = <String>{
      '3gp4',
      '3gp5',
      '3gp6',
      '3g2a',
      '3g2b',
      '3gr6',
      '3gs6',
    };
    if (threeGp.contains(major) || brands.any(threeGp.contains)) {
      return DetectedFormat(
        kind: MediaKind.video,
        videoContainer: VideoContainer.threegp,
        containerBrand: major,
      );
    }
    const mp4Brands = <String>{
      'isom',
      'iso2',
      'iso4',
      'iso5',
      'iso6',
      'mp41',
      'mp42',
      'avc1',
      'dash',
      'msdh',
      'msix',
      'mmp4',
    };
    if (mp4Brands.contains(major) || brands.any(mp4Brands.contains)) {
      return DetectedFormat(
        kind: MediaKind.video,
        videoContainer: VideoContainer.mp4,
        containerBrand: major,
      );
    }
    // Unknown ftyp brand: assume an ISO-BMFF video container rather than nothing.
    return DetectedFormat(
      kind: MediaKind.video,
      videoContainer: VideoContainer.mp4,
      containerBrand: major,
      confidence: DetectionConfidence.tentative,
    );
  }

  static List<String> _ftypBrands(Uint8List bytes) {
    // Layout: [size:4][ftyp:4][major:4][minor:4][compatible*:4]
    if (bytes.length < 12) {
      return const <String>[];
    }
    final brands = <String>[_ascii(bytes, 8, 4)];
    var offset = 16;
    // Bound the scan to the first box / first 64 bytes to avoid runaway loops.
    final limit = bytes.length < 68 ? bytes.length : 68;
    while (offset + 4 <= limit) {
      brands.add(_ascii(bytes, offset, 4));
      offset += 4;
    }
    return brands;
  }

  /// Extension-based hint, used only to disambiguate ambiguous containers (e.g. DNG vs TIFF)
  /// and as a low-confidence fallback. Never authoritative on its own.
  static DetectedFormat fromExtension(String extension) {
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    final image = ImageFormat.fromExtension(normalized);
    if (image != ImageFormat.unknown) {
      return DetectedFormat(
        kind: MediaKind.image,
        imageFormat: image,
        confidence: DetectionConfidence.tentative,
      );
    }
    final video = VideoContainer.fromExtension(normalized);
    if (video != VideoContainer.unknown) {
      return DetectedFormat(
        kind: MediaKind.video,
        videoContainer: video,
        confidence: DetectionConfidence.tentative,
      );
    }
    return DetectedFormat.unknown;
  }
}
