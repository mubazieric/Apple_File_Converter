/// Which platforms a capability statement applies to.
enum PlatformKind {
  android,
  ios,
  desktop,
  unknown;

  bool get isMobile => this == PlatformKind.android || this == PlatformKind.ios;
}

/// The four independent capabilities the product promises for a format.
///
/// These are intentionally separate because a format can be viewable but not decodable by our
/// engine, or decodable but not encodable. The UI must only advertise what actually works.
class FormatCapability {
  const FormatCapability({
    required this.canView,
    required this.canDecode,
    required this.canEncode,
    this.supportsAnimation = false,
    this.hasAlpha = false,
    this.isLossy = true,
    this.note,
  });

  /// Can be displayed in the in-app preview (thumbnail and/or full screen).
  final bool canView;

  /// Can be read/decoded by our processing engine into pixels.
  final bool canDecode;

  /// Can be produced as an output format by our processing engine.
  final bool canEncode;

  /// Supports multiple frames (GIF, animated WebP, …).
  final bool supportsAnimation;

  /// Supports an alpha channel.
  final bool hasAlpha;

  /// True when encoding is inherently lossy (so we must not claim "lossless").
  final bool isLossy;

  /// Human-readable caveat shown in the format matrix / UI, e.g. platform dependence.
  final String? note;

  /// A fully supported round-trip format.
  bool get isRoundTrip => canDecode && canEncode;

  /// Not advertised anywhere as usable.
  static const FormatCapability unsupported = FormatCapability(
    canView: false,
    canDecode: false,
    canEncode: false,
  );

  FormatCapability copyWith({
    bool? canView,
    bool? canDecode,
    bool? canEncode,
    String? note,
  }) {
    return FormatCapability(
      canView: canView ?? this.canView,
      canDecode: canDecode ?? this.canDecode,
      canEncode: canEncode ?? this.canEncode,
      supportsAnimation: supportsAnimation,
      hasAlpha: hasAlpha,
      isLossy: isLossy,
      note: note ?? this.note,
    );
  }

  @override
  String toString() =>
      'FormatCapability(view: $canView, decode: $canDecode, encode: $canEncode, '
      'animated: $supportsAnimation, alpha: $hasAlpha, lossy: $isLossy)';

  @override
  bool operator ==(Object other) =>
      other is FormatCapability &&
      other.canView == canView &&
      other.canDecode == canDecode &&
      other.canEncode == canEncode &&
      other.supportsAnimation == supportsAnimation &&
      other.hasAlpha == hasAlpha &&
      other.isLossy == isLossy &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
    canView,
    canDecode,
    canEncode,
    supportsAnimation,
    hasAlpha,
    isLossy,
    note,
  );
}
