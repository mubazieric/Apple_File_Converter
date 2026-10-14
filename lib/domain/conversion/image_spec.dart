import 'dart:math' as math;

import '../media/image_format.dart';

/// How a resize is expressed.
enum ResizeMode {
  /// Keep the original pixel dimensions.
  none,

  /// Explicit pixel width/height.
  absolute,

  /// Scale relative to the original dimensions.
  percentage,

  /// Fit the longest edge to a target, preserving aspect ratio.
  longestEdge,
}

/// An exact-output specification for image resizing.
class ResizeSpec {
  const ResizeSpec._({
    required this.mode,
    this.width,
    this.height,
    this.percentage,
    this.longestEdge,
    this.lockAspectRatio = true,
    this.allowUpscale = false,
  });

  const ResizeSpec.none() : this._(mode: ResizeMode.none);

  const ResizeSpec.absolute({
    required int width,
    required int height,
    bool lockAspectRatio = true,
    bool allowUpscale = false,
  }) : this._(
         mode: ResizeMode.absolute,
         width: width,
         height: height,
         lockAspectRatio: lockAspectRatio,
         allowUpscale: allowUpscale,
       );

  const ResizeSpec.percentage(double value)
    : this._(mode: ResizeMode.percentage, percentage: value);

  const ResizeSpec.longestEdge(int value, {bool allowUpscale = false})
    : this._(
        mode: ResizeMode.longestEdge,
        longestEdge: value,
        allowUpscale: allowUpscale,
      );

  /// Common dimension presets offered in the UI (width, height, label).
  static const List<(int, int, String)> dimensionPresets = <(int, int, String)>[
    (4096, 4096, '4K square'),
    (3840, 2160, '4K UHD'),
    (2560, 1440, '1440p'),
    (1920, 1080, 'Full HD 1080p'),
    (1280, 720, 'HD 720p'),
    (1080, 1080, 'Instagram square'),
    (1080, 1920, 'Story 9:16'),
    (1200, 630, 'Social 1.91:1'),
    (800, 800, 'Product square'),
    (640, 480, 'VGA'),
    (512, 512, 'Icon 512'),
    (256, 256, 'Thumbnail 256'),
  ];

  final ResizeMode mode;
  final int? width;
  final int? height;
  final double? percentage;
  final int? longestEdge;
  final bool lockAspectRatio;
  final bool allowUpscale;

  bool get isNone => mode == ResizeMode.none;

  /// Resolves the final output dimensions for a source of [srcWidth] × [srcHeight].
  ///
  /// Guarantees: never returns a zero or negative dimension; never upscales unless
  /// [allowUpscale]; preserves aspect ratio when [lockAspectRatio] (and for percentage /
  /// longest-edge modes always).
  (int, int) resolve(int srcWidth, int srcHeight) {
    if (srcWidth <= 0 || srcHeight <= 0) {
      return (math.max(srcWidth, 1), math.max(srcHeight, 1));
    }
    switch (mode) {
      case ResizeMode.none:
        return (srcWidth, srcHeight);

      case ResizeMode.absolute:
        var w = width ?? srcWidth;
        var h = height ?? srcHeight;
        if (lockAspectRatio) {
          final aspect = srcWidth / srcHeight;
          // Trust width as the driver when aspect is locked; derive height.
          h = (w / aspect).round();
        }
        if (!allowUpscale && (w > srcWidth || h > srcHeight)) {
          final scale = math.min(srcWidth / w, srcHeight / h);
          w = math.max(1, (w * scale).round());
          h = math.max(1, (h * scale).round());
        }
        return (math.max(w, 1), math.max(h, 1));

      case ResizeMode.percentage:
        final factor = (percentage ?? 100) / 100.0;
        final w = (srcWidth * factor).round();
        final h = (srcHeight * factor).round();
        if (!allowUpscale && factor > 1) {
          return (srcWidth, srcHeight);
        }
        return (math.max(w, 1), math.max(h, 1));

      case ResizeMode.longestEdge:
        final target = longestEdge ?? math.max(srcWidth, srcHeight);
        final longest = math.max(srcWidth, srcHeight);
        if (!allowUpscale && target >= longest) {
          return (srcWidth, srcHeight);
        }
        final scale = target / longest;
        return (
          math.max(1, (srcWidth * scale).round()),
          math.max(1, (srcHeight * scale).round()),
        );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'width': width,
    'height': height,
    'percentage': percentage,
    'longestEdge': longestEdge,
    'lockAspectRatio': lockAspectRatio,
    'allowUpscale': allowUpscale,
  };

  static ResizeSpec fromJson(Map<String, Object?> json) {
    final mode = ResizeMode.values.firstWhere(
      (m) => m.name == json['mode'],
      orElse: () => ResizeMode.none,
    );
    return ResizeSpec._(
      mode: mode,
      width: json['width'] as int?,
      height: json['height'] as int?,
      percentage: (json['percentage'] as num?)?.toDouble(),
      longestEdge: json['longestEdge'] as int?,
      lockAspectRatio: json['lockAspectRatio'] as bool? ?? true,
      allowUpscale: json['allowUpscale'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'ResizeSpec(${mode.name})';

  @override
  bool operator ==(Object other) =>
      other is ResizeSpec &&
      other.mode == mode &&
      other.width == width &&
      other.height == height &&
      other.percentage == percentage &&
      other.longestEdge == longestEdge &&
      other.lockAspectRatio == lockAspectRatio &&
      other.allowUpscale == allowUpscale;

  @override
  int get hashCode => Object.hash(
    mode,
    width,
    height,
    percentage,
    longestEdge,
    lockAspectRatio,
    allowUpscale,
  );
}

/// Quarter-turn rotation applied during conversion.
enum Rotation {
  none(0),
  clockwise90(90),
  degrees180(180),
  clockwise270(270);

  const Rotation(this.degrees);

  final int degrees;

  bool get swapsAxes => degrees == 90 || degrees == 270;
}

enum FlipAxis { none, horizontal, vertical, both }

/// Where a text watermark is drawn.
enum WatermarkPosition { topLeft, topRight, bottomLeft, bottomRight, center }

class WatermarkSpec {
  const WatermarkSpec({
    required this.text,
    this.position = WatermarkPosition.bottomRight,
    this.opacity = 0.6,
    this.fontSizeFraction = 0.045,
    this.colorValue = 0xFFFFFFFF,
    this.paddingFraction = 0.03,
  }) : assert(opacity >= 0 && opacity <= 1, 'opacity must be 0..1');

  final String text;
  final WatermarkPosition position;
  final double opacity;

  /// Font size as a fraction of the image's shorter edge (resolution independent).
  final double fontSizeFraction;
  final int colorValue;
  final double paddingFraction;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'position': position.name,
    'opacity': opacity,
    'fontSizeFraction': fontSizeFraction,
    'colorValue': colorValue,
    'paddingFraction': paddingFraction,
  };

  static WatermarkSpec fromJson(Map<String, Object?> json) => WatermarkSpec(
    text: json['text'] as String? ?? '',
    position: WatermarkPosition.values.firstWhere(
      (value) => value.name == json['position'],
      orElse: () => WatermarkPosition.bottomRight,
    ),
    opacity: (json['opacity'] as num?)?.toDouble() ?? 0.6,
    fontSizeFraction: (json['fontSizeFraction'] as num?)?.toDouble() ?? 0.045,
    colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFFFFFFF,
    paddingFraction: (json['paddingFraction'] as num?)?.toDouble() ?? 0.03,
  );
}

/// The complete, immutable description of an image conversion.
class ImageConversionSpec {
  const ImageConversionSpec({
    this.outputFormat = ImageFormat.jpeg,
    this.quality,
    this.pngCompressionLevel = 6,
    this.resize = const ResizeSpec.none(),
    this.rotation = Rotation.none,
    this.flip = FlipAxis.none,
    this.keepMetadata = true,
    this.stripLocation = false,
    this.watermark,
    this.keepAnimation = true,
    this.lossless = false,
  });

  final ImageFormat outputFormat;

  /// 1–100, or null to use the format default.
  final int? quality;

  /// PNG zlib level 0–9 (higher = smaller, slower). Ignored for other formats.
  final int pngCompressionLevel;

  final ResizeSpec resize;
  final Rotation rotation;
  final FlipAxis flip;

  /// Preserve EXIF/ICC/orientation where the format allows.
  final bool keepMetadata;

  /// Remove GPS/location from preserved metadata (privacy default recommendation).
  final bool stripLocation;

  final WatermarkSpec? watermark;

  /// Preserve animation for animated inputs (GIF/animated WebP).
  final bool keepAnimation;

  /// Request lossless encoding where the target format supports it (e.g. WebP).
  final bool lossless;

  int get effectiveQuality =>
      (quality ?? outputFormat.defaultQuality).clamp(1, 100);

  /// True when converting to a format without alpha will discard transparency.
  bool losesAlpha(ImageFormat source) =>
      source.hasAlpha && !outputFormat.hasAlpha;

  ImageConversionSpec copyWith({
    ImageFormat? outputFormat,
    int? quality,
    int? pngCompressionLevel,
    ResizeSpec? resize,
    Rotation? rotation,
    FlipAxis? flip,
    bool? keepMetadata,
    bool? stripLocation,
    WatermarkSpec? watermark,
    bool? keepAnimation,
    bool? lossless,
    bool clearWatermark = false,
  }) {
    return ImageConversionSpec(
      outputFormat: outputFormat ?? this.outputFormat,
      quality: quality ?? this.quality,
      pngCompressionLevel: pngCompressionLevel ?? this.pngCompressionLevel,
      resize: resize ?? this.resize,
      rotation: rotation ?? this.rotation,
      flip: flip ?? this.flip,
      keepMetadata: keepMetadata ?? this.keepMetadata,
      stripLocation: stripLocation ?? this.stripLocation,
      watermark: clearWatermark ? null : (watermark ?? this.watermark),
      keepAnimation: keepAnimation ?? this.keepAnimation,
      lossless: lossless ?? this.lossless,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'outputFormat': outputFormat.id,
    'quality': quality,
    'pngCompressionLevel': pngCompressionLevel,
    'resize': resize.toJson(),
    'rotation': rotation.name,
    'flip': flip.name,
    'keepMetadata': keepMetadata,
    'stripLocation': stripLocation,
    'watermark': watermark?.toJson(),
    'keepAnimation': keepAnimation,
    'lossless': lossless,
  };

  static ImageConversionSpec fromJson(Map<String, Object?> json) {
    final resize = json['resize'];
    final watermark = json['watermark'];
    return ImageConversionSpec(
      outputFormat: ImageFormat.fromId(json['outputFormat'] as String? ?? ''),
      quality: (json['quality'] as num?)?.toInt(),
      pngCompressionLevel: (json['pngCompressionLevel'] as num?)?.toInt() ?? 6,
      resize: resize is Map
          ? ResizeSpec.fromJson(resize.cast<String, Object?>())
          : const ResizeSpec.none(),
      rotation: Rotation.values.firstWhere(
        (value) => value.name == json['rotation'],
        orElse: () => Rotation.none,
      ),
      flip: FlipAxis.values.firstWhere(
        (value) => value.name == json['flip'],
        orElse: () => FlipAxis.none,
      ),
      keepMetadata: json['keepMetadata'] as bool? ?? true,
      stripLocation: json['stripLocation'] as bool? ?? false,
      watermark: watermark is Map
          ? WatermarkSpec.fromJson(watermark.cast<String, Object?>())
          : null,
      keepAnimation: json['keepAnimation'] as bool? ?? true,
      lossless: json['lossless'] as bool? ?? false,
    );
  }
}
