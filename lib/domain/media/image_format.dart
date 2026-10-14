import 'capability.dart';

/// The image formats the product knows about.
///
/// The capability matrix (which of view/decode/encode actually work) is resolved per platform
/// by [capabilityFor]. **Never** advertise a capability that is not implemented — the
/// conversion engines consult this same matrix, and the widget tests assert the UI never
/// offers an unsupported conversion.
enum ImageFormat {
  jpeg(
    id: 'jpeg',
    label: 'JPEG',
    extensions: <String>['jpg', 'jpeg'],
    mimeType: 'image/jpeg',
    hasAlpha: false,
    isLossy: true,
    losslessCapable: false,
    defaultQuality: 90,
  ),
  png(
    id: 'png',
    label: 'PNG',
    extensions: <String>['png'],
    mimeType: 'image/png',
    hasAlpha: true,
    isLossy: false,
    losslessCapable: true,
    defaultQuality: 100,
  ),
  webp(
    id: 'webp',
    label: 'WebP',
    extensions: <String>['webp'],
    mimeType: 'image/webp',
    hasAlpha: true,
    isLossy: true,
    losslessCapable: true,
    defaultQuality: 85,
  ),
  gif(
    id: 'gif',
    label: 'GIF',
    extensions: <String>['gif'],
    mimeType: 'image/gif',
    hasAlpha: true,
    isLossy: false,
    losslessCapable: true,
    defaultQuality: 100,
  ),
  bmp(
    id: 'bmp',
    label: 'BMP',
    extensions: <String>['bmp'],
    mimeType: 'image/bmp',
    hasAlpha: true,
    isLossy: false,
    losslessCapable: true,
    defaultQuality: 100,
  ),
  tiff(
    id: 'tiff',
    label: 'TIFF',
    extensions: <String>['tif', 'tiff'],
    mimeType: 'image/tiff',
    hasAlpha: true,
    isLossy: false,
    losslessCapable: true,
    defaultQuality: 100,
  ),
  ico(
    id: 'ico',
    label: 'ICO',
    extensions: <String>['ico'],
    mimeType: 'image/x-icon',
    hasAlpha: true,
    isLossy: false,
    losslessCapable: true,
    defaultQuality: 100,
  ),
  wbmp(
    id: 'wbmp',
    label: 'WBMP',
    extensions: <String>['wbmp'],
    mimeType: 'image/vnd.wap.wbmp',
    hasAlpha: false,
    isLossy: false,
    losslessCapable: true,
    defaultQuality: 100,
  ),
  heic(
    id: 'heic',
    label: 'HEIC',
    extensions: <String>['heic'],
    mimeType: 'image/heic',
    hasAlpha: false,
    isLossy: true,
    losslessCapable: false,
    defaultQuality: 90,
  ),
  heif(
    id: 'heif',
    label: 'HEIF',
    extensions: <String>['heif'],
    mimeType: 'image/heif',
    hasAlpha: true,
    isLossy: true,
    losslessCapable: false,
    defaultQuality: 90,
  ),
  avif(
    id: 'avif',
    label: 'AVIF',
    extensions: <String>['avif'],
    mimeType: 'image/avif',
    hasAlpha: true,
    isLossy: true,
    losslessCapable: true,
    defaultQuality: 85,
  ),
  svg(
    id: 'svg',
    label: 'SVG',
    extensions: <String>['svg'],
    mimeType: 'image/svg+xml',
    hasAlpha: true,
    isLossy: false,
    losslessCapable: true,
    defaultQuality: 100,
  ),
  jp2(
    id: 'jp2',
    label: 'JPEG 2000',
    extensions: <String>['jp2', 'j2k', 'jpx'],
    mimeType: 'image/jp2',
    hasAlpha: true,
    isLossy: true,
    losslessCapable: true,
    defaultQuality: 90,
  ),
  dng(
    id: 'dng',
    label: 'DNG / RAW',
    extensions: <String>[
      'dng',
      'cr2',
      'cr3',
      'nef',
      'arw',
      'raf',
      'orf',
      'rw2',
    ],
    mimeType: 'image/x-adobe-dng',
    hasAlpha: false,
    isLossy: false,
    losslessCapable: true,
    defaultQuality: 95,
  ),
  unknown(
    id: 'unknown',
    label: 'Unknown',
    extensions: <String>[],
    mimeType: 'application/octet-stream',
    hasAlpha: false,
    isLossy: true,
    losslessCapable: false,
    defaultQuality: 90,
  );

  const ImageFormat({
    required this.id,
    required this.label,
    required this.extensions,
    required this.mimeType,
    required this.hasAlpha,
    required this.isLossy,
    required this.losslessCapable,
    required this.defaultQuality,
  });

  final String id;
  final String label;
  final List<String> extensions;
  final String mimeType;
  final bool hasAlpha;
  final bool isLossy;
  final bool losslessCapable;

  /// Sensible default quality (1–100) used when encoding to this format.
  final int defaultQuality;

  /// The canonical file extension written for this format.
  String get primaryExtension => extensions.isEmpty ? 'bin' : extensions.first;

  /// Formats the user can choose as conversion *targets* on the given platform.
  static List<ImageFormat> encodableTargets(PlatformKind platform) => values
      .where((f) => f.capabilityFor(platform).canEncode)
      .toList(growable: false);

  /// Capability resolution. Everything routed through the pure-Dart `image` package behaves
  /// identically on both mobile platforms; the exceptions are documented inline.
  FormatCapability capabilityFor(PlatformKind platform) {
    switch (this) {
      case ImageFormat.jpeg:
        return const FormatCapability(
          canView: true,
          canDecode: true,
          canEncode: true,
          hasAlpha: false,
          isLossy: true,
        );

      case ImageFormat.png:
      case ImageFormat.bmp:
      case ImageFormat.tiff:
      case ImageFormat.ico:
        return const FormatCapability(
          canView: true,
          canDecode: true,
          canEncode: true,
          hasAlpha: true,
          isLossy: false,
        );

      case ImageFormat.wbmp:
        // The pure-Dart codec set has no WBMP decoder/encoder, and no native path is
        // implemented. We do not advertise it rather than pretend it works.
        return const FormatCapability(
          canView: false,
          canDecode: false,
          canEncode: false,
          note: 'WBMP is not supported by the shipped engine (deferred).',
        );

      case ImageFormat.gif:
        return const FormatCapability(
          canView: true,
          canDecode: true,
          canEncode: true,
          supportsAnimation: true,
          hasAlpha: true,
          isLossy: false,
        );

      case ImageFormat.webp:
        // Decoded and encoded by the pure-Dart `image` package on both platforms, so WebP
        // output behaves identically on Android and iOS.
        return const FormatCapability(
          canView: true,
          canDecode: true,
          canEncode: true,
          hasAlpha: true,
          isLossy: true,
        );

      case ImageFormat.heic:
      case ImageFormat.heif:
        // Native decode only. Android ImageDecoder from API 28; iOS ImageIO (all supported
        // iOS). Encoding is deliberately NOT offered: Apple's encoder is not exposed to
        // third-party apps in a supported way, and we refuse to fake it.
        final decodable =
            platform == PlatformKind.android || platform == PlatformKind.ios;
        return FormatCapability(
          canView: decodable,
          canDecode: decodable,
          canEncode: false,
          supportsAnimation: this == ImageFormat.heif,
          hasAlpha: this == ImageFormat.heif,
          isLossy: true,
          note: decodable
              ? 'Decoded by the device. Conversion output must be JPEG, PNG or WebP.'
              : 'Not decodable on this platform.',
        );

      case ImageFormat.avif:
        final decodable =
            platform == PlatformKind.ios || platform == PlatformKind.android;
        return FormatCapability(
          canView: decodable,
          canDecode: decodable,
          canEncode: false,
          hasAlpha: true,
          isLossy: true,
          note: decodable
              ? 'Decode depends on the OS image stack (Android 12+/iOS 16+).'
              : 'Not decodable on this platform.',
        );

      case ImageFormat.svg:
        // Rasterisation is intentionally deferred; we do not claim SVG support.
        return const FormatCapability(
          canView: false,
          canDecode: false,
          canEncode: false,
          note: 'SVG is not supported yet (deferred).',
        );

      case ImageFormat.jp2:
        return const FormatCapability(
          canView: false,
          canDecode: false,
          canEncode: false,
          note: 'JPEG 2000 is not supported by the shipped engine.',
        );

      case ImageFormat.dng:
        final decodable = platform == PlatformKind.ios;
        return FormatCapability(
          canView: decodable,
          canDecode: decodable,
          canEncode: false,
          isLossy: false,
          note: decodable
              ? 'RAW decode via the iOS image stack only when the device supports it.'
              : 'RAW/DNG decode is not available on this platform.',
        );

      case ImageFormat.unknown:
        return FormatCapability.unsupported;
    }
  }

  static ImageFormat fromExtension(String ext) {
    final normalized = ext.toLowerCase().replaceFirst('.', '');
    for (final format in values) {
      if (format.extensions.contains(normalized)) {
        return format;
      }
    }
    return ImageFormat.unknown;
  }

  static ImageFormat fromId(String id) => values.firstWhere(
    (f) => f.id == id.toLowerCase(),
    orElse: () => ImageFormat.unknown,
  );

  static ImageFormat fromMimeType(String mime) {
    final normalized = mime.toLowerCase();
    for (final format in values) {
      if (format.mimeType == normalized) {
        return format;
      }
    }
    return ImageFormat.unknown;
  }
}
