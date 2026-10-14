import 'dart:math' as math;

import '../media/video_format.dart';
import 'image_spec.dart' show Rotation;

/// Standard output resolutions.
enum ResolutionPreset {
  original,
  p240,
  p360,
  p480,
  p720,
  p1080,
  p1440,
  p2160,
  custom;

  /// Target short-edge height for the fixed presets, or null for [original]/[custom].
  int? get height => switch (this) {
    ResolutionPreset.p240 => 240,
    ResolutionPreset.p360 => 360,
    ResolutionPreset.p480 => 480,
    ResolutionPreset.p720 => 720,
    ResolutionPreset.p1080 => 1080,
    ResolutionPreset.p1440 => 1440,
    ResolutionPreset.p2160 => 2160,
    _ => null,
  };

  String get label => switch (this) {
    ResolutionPreset.original => 'Original',
    ResolutionPreset.p240 => '240p',
    ResolutionPreset.p360 => '360p',
    ResolutionPreset.p480 => '480p',
    ResolutionPreset.p720 => '720p HD',
    ResolutionPreset.p1080 => '1080p Full HD',
    ResolutionPreset.p1440 => '1440p QHD',
    ResolutionPreset.p2160 => '2160p 4K',
    ResolutionPreset.custom => 'Custom',
  };
}

/// Target quality tier, used to derive bitrates when the user does not set one.
enum VideoQuality { smaller, balanced, high, maximum }

/// Playback-speed adjustment (requires re-encoding).
enum SpeedMode {
  x0_5(0.5, '0.5×'),
  normal(1.0, 'Normal'),
  x1_5(1.5, '1.5×'),
  x2(2.0, '2×'),
  x4(4.0, '4×');

  const SpeedMode(this.factor, this.label);

  final double factor;
  final String label;
}

/// Encoder selection policy.
enum HardwareAcceleration {
  /// Prefer a hardware encoder, fall back to software where available.
  auto,

  /// Require hardware; fail honestly if it is unavailable.
  require,
}

/// The complete, immutable description of a video conversion.
///
/// `remuxOnly` is deliberately separate from codec selection: copying streams is *not* the
/// same as converting codecs, and the UI must not confuse the two.
class VideoConversionSpec {
  const VideoConversionSpec({
    this.container = VideoContainer.mp4,
    this.videoCodec,
    this.audioCodec,
    this.resolution = ResolutionPreset.original,
    this.customWidth,
    this.customHeight,
    this.frameRate,
    this.videoBitrateKbps,
    this.audioBitrateKbps = 128,
    this.keepAudio = true,
    this.remuxOnly = false,
    this.trimStart,
    this.trimEnd,
    this.rotation = Rotation.none,
    this.speed = SpeedMode.normal,
    this.hardware = HardwareAcceleration.auto,
    this.quality = VideoQuality.balanced,
    this.keepMetadata = true,
  });

  final VideoContainer container;

  /// null = auto (hardware H.264 for MP4, hardware HEVC for MOV).
  final VideoCodec? videoCodec;
  final AudioCodec? audioCodec;

  final ResolutionPreset resolution;
  final int? customWidth;
  final int? customHeight;

  /// null = same as source.
  final int? frameRate;

  /// null = derived from resolution + [quality].
  final int? videoBitrateKbps;
  final int audioBitrateKbps;

  final bool keepAudio;

  /// Copy streams without re-encoding (container change only).
  final bool remuxOnly;

  final Duration? trimStart;
  final Duration? trimEnd;
  final Rotation rotation;
  final SpeedMode speed;
  final HardwareAcceleration hardware;
  final VideoQuality quality;
  final bool keepMetadata;

  bool get isTrimmed => trimStart != null || trimEnd != null;

  /// Effective quality tier, lowered for "smaller" presets.
  bool get needsReencode =>
      !remuxOnly ||
      speed != SpeedMode.normal ||
      rotation != Rotation.none ||
      isTrimmed ||
      resolution != ResolutionPreset.original;

  /// Resolves output dimensions (even numbers, never zero) for a source size.
  (int, int) resolve(int srcWidth, int srcHeight) {
    final targetH = resolution.height;
    if (targetH == null) {
      if (resolution == ResolutionPreset.custom) {
        var w = customWidth ?? srcWidth;
        var h = customHeight ?? srcHeight;
        w = _even(w);
        h = _even(h);
        if (srcWidth > 0 && srcHeight > 0) {
          // Preserve aspect ratio using width as the driver if only height was customised.
          if (customWidth == null && customHeight != null) {
            w = _even((srcWidth * (h / srcHeight)).round());
          }
        }
        return (math.max(w, 2), math.max(h, 2));
      }
      return (_even(srcWidth), _even(srcHeight));
    }
    if (srcWidth <= 0 || srcHeight <= 0) {
      return (targetH * 16 ~/ 9, targetH);
    }
    final landscape = srcWidth >= srcHeight;
    // The target height is the target *short* edge: for landscape footage that is the height,
    // for portrait footage it is the width.
    final shortEdge = landscape ? srcHeight : srcWidth;
    if (shortEdge <= targetH) {
      // Never upscale by default; keep original dimensions.
      return (_even(srcWidth), _even(srcHeight));
    }
    final scale = targetH / shortEdge;
    var w = (srcWidth * scale).round();
    var h = (srcHeight * scale).round();
    // Round to even dimensions for codec compatibility.
    w = _even(w);
    h = _even(h);
    return (math.max(w, 2), math.max(h, 2));
  }

  static int _even(int v) {
    final safe = math.max(v, 2);
    return safe.isEven ? safe : safe + 1;
  }

  /// Heuristic video bitrate (kbps) when the user has not set one.
  int estimateVideoBitrateKbps() {
    if (videoBitrateKbps != null && videoBitrateKbps! > 0) {
      return videoBitrateKbps!;
    }
    final h = resolution.height ?? 1080;
    final table = switch (h) {
      <= 240 => <int>[250, 400, 650],
      <= 360 => <int>[450, 750, 1200],
      <= 480 => <int>[750, 1200, 2000],
      <= 720 => <int>[1500, 2500, 4000],
      <= 1080 => <int>[3000, 5000, 8000],
      <= 1440 => <int>[6000, 10000, 16000],
      _ => <int>[12000, 20000, 35000],
    };
    final index = switch (quality) {
      VideoQuality.smaller => 0,
      VideoQuality.balanced => 1,
      VideoQuality.high => 2,
      VideoQuality.maximum => 2,
    };
    var bitrate = table[index];
    if (quality == VideoQuality.maximum) {
      bitrate = (bitrate * 1.4).round();
    }
    // Higher frame rates need more bits.
    final fps = frameRate ?? 30;
    if (fps >= 50) {
      bitrate = (bitrate * 1.5).round();
    } else if (fps >= 40) {
      bitrate = (bitrate * 1.2).round();
    }
    return bitrate;
  }

  int estimateAudioBitrateKbps() =>
      keepAudio ? (audioCodec == AudioCodec.none ? 0 : audioBitrateKbps) : 0;

  /// Estimated output size in bytes for a clip of [duration].
  int estimateOutputBytes(Duration duration, {double overhead = 1.03}) {
    final seconds = duration.inMilliseconds / 1000.0;
    final totalKbps = estimateVideoBitrateKbps() + estimateAudioBitrateKbps();
    final bytes = (totalKbps * 1000 / 8) * seconds * overhead;
    return bytes.round();
  }

  VideoConversionSpec copyWith({
    VideoContainer? container,
    VideoCodec? videoCodec,
    AudioCodec? audioCodec,
    bool clearVideoCodec = false,
    bool clearAudioCodec = false,
    ResolutionPreset? resolution,
    int? customWidth,
    int? customHeight,
    int? frameRate,
    bool clearFrameRate = false,
    int? videoBitrateKbps,
    bool clearVideoBitrate = false,
    int? audioBitrateKbps,
    bool? keepAudio,
    bool? remuxOnly,
    Duration? trimStart,
    bool clearTrimStart = false,
    Duration? trimEnd,
    bool clearTrimEnd = false,
    Rotation? rotation,
    SpeedMode? speed,
    HardwareAcceleration? hardware,
    VideoQuality? quality,
    bool? keepMetadata,
  }) {
    return VideoConversionSpec(
      container: container ?? this.container,
      videoCodec: clearVideoCodec ? null : (videoCodec ?? this.videoCodec),
      audioCodec: clearAudioCodec ? null : (audioCodec ?? this.audioCodec),
      resolution: resolution ?? this.resolution,
      customWidth: customWidth ?? this.customWidth,
      customHeight: customHeight ?? this.customHeight,
      frameRate: clearFrameRate ? null : (frameRate ?? this.frameRate),
      videoBitrateKbps: clearVideoBitrate
          ? null
          : (videoBitrateKbps ?? this.videoBitrateKbps),
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
      keepAudio: keepAudio ?? this.keepAudio,
      remuxOnly: remuxOnly ?? this.remuxOnly,
      trimStart: clearTrimStart ? null : (trimStart ?? this.trimStart),
      trimEnd: clearTrimEnd ? null : (trimEnd ?? this.trimEnd),
      rotation: rotation ?? this.rotation,
      speed: speed ?? this.speed,
      hardware: hardware ?? this.hardware,
      quality: quality ?? this.quality,
      keepMetadata: keepMetadata ?? this.keepMetadata,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'container': container.id,
    'videoCodec': videoCodec?.id,
    'audioCodec': audioCodec?.id,
    'resolution': resolution.name,
    'customWidth': customWidth,
    'customHeight': customHeight,
    'frameRate': frameRate,
    'videoBitrateKbps': videoBitrateKbps,
    'audioBitrateKbps': audioBitrateKbps,
    'keepAudio': keepAudio,
    'remuxOnly': remuxOnly,
    'trimStartMs': trimStart?.inMilliseconds,
    'trimEndMs': trimEnd?.inMilliseconds,
    'rotation': rotation.name,
    'speed': speed.name,
    'hardware': hardware.name,
    'quality': quality.name,
    'keepMetadata': keepMetadata,
  };

  static VideoConversionSpec fromJson(Map<String, Object?> json) =>
      VideoConversionSpec(
        container: VideoContainer.fromId(json['container'] as String? ?? ''),
        videoCodec: _videoCodec(json['videoCodec'] as String?),
        audioCodec: _audioCodec(json['audioCodec'] as String?),
        resolution: ResolutionPreset.values.firstWhere(
          (value) => value.name == json['resolution'],
          orElse: () => ResolutionPreset.original,
        ),
        customWidth: (json['customWidth'] as num?)?.toInt(),
        customHeight: (json['customHeight'] as num?)?.toInt(),
        frameRate: (json['frameRate'] as num?)?.toInt(),
        videoBitrateKbps: (json['videoBitrateKbps'] as num?)?.toInt(),
        audioBitrateKbps: (json['audioBitrateKbps'] as num?)?.toInt() ?? 128,
        keepAudio: json['keepAudio'] as bool? ?? true,
        remuxOnly: json['remuxOnly'] as bool? ?? false,
        trimStart: _duration(json['trimStartMs']),
        trimEnd: _duration(json['trimEndMs']),
        rotation: Rotation.values.firstWhere(
          (value) => value.name == json['rotation'],
          orElse: () => Rotation.none,
        ),
        speed: SpeedMode.values.firstWhere(
          (value) => value.name == json['speed'],
          orElse: () => SpeedMode.normal,
        ),
        hardware: HardwareAcceleration.values.firstWhere(
          (value) => value.name == json['hardware'],
          orElse: () => HardwareAcceleration.auto,
        ),
        quality: VideoQuality.values.firstWhere(
          (value) => value.name == json['quality'],
          orElse: () => VideoQuality.balanced,
        ),
        keepMetadata: json['keepMetadata'] as bool? ?? true,
      );

  static VideoCodec? _videoCodec(String? id) =>
      (id == null || id.isEmpty) ? null : VideoCodec.fromId(id);

  static AudioCodec? _audioCodec(String? id) =>
      (id == null || id.isEmpty) ? null : AudioCodec.fromId(id);

  static Duration? _duration(Object? value) =>
      value is num ? Duration(milliseconds: value.toInt()) : null;
}
