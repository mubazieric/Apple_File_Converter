import '../../domain/media/video_format.dart';

/// The result of probing a media file (via FFprobe, or the native bridge for images).
class MediaProbeResult {
  const MediaProbeResult({
    this.container = VideoContainer.unknown,
    this.duration,
    this.width,
    this.height,
    this.frameRate,
    this.videoCodec,
    this.audioCodec,
    this.hasVideo = false,
    this.hasAudio = false,
    this.bitrateKbps,
    this.rotationDegrees = 0,
    this.audioChannels,
    this.audioSampleRate,
    this.pixelFormat,
    this.error,
  });

  final VideoContainer container;
  final Duration? duration;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? videoCodec;
  final String? audioCodec;
  final bool hasVideo;
  final bool hasAudio;
  final int? bitrateKbps;
  final int rotationDegrees;
  final int? audioChannels;
  final int? audioSampleRate;
  final String? pixelFormat;
  final String? error;

  bool get isUsable => error == null && (hasVideo || hasAudio);

  static const MediaProbeResult empty = MediaProbeResult();

  /// Maps a codec name reported by FFprobe onto our taxonomy, when we recognise it.
  static VideoCodec codecFromFfprobeName(String? name) {
    final normalized = (name ?? '').toLowerCase();
    return switch (normalized) {
      'h264' || 'avc1' => VideoCodec.h264,
      'hevc' || 'h265' || 'hvc1' || 'hev1' => VideoCodec.hevc,
      'vp8' => VideoCodec.vp8,
      'vp9' => VideoCodec.vp9,
      'av1' || 'av01' => VideoCodec.av1,
      'mpeg4' => VideoCodec.mpeg4,
      'prores' => VideoCodec.prores,
      _ => VideoCodec.unknown,
    };
  }

  @override
  String toString() =>
      'MediaProbeResult(${container.id}, ${width}x$height, ${duration?.inMilliseconds}ms, '
      'v=${videoCodec ?? '-'}, a=${audioCodec ?? '-'}, rot=$rotationDegrees)';
}

/// Which encoders/muxers are actually available at runtime.
///
/// Populated by asking FFmpeg for its encoder list where possible; otherwise the documented
/// defaults for the bundled LGPL build are used. The command builder consults this so it never
/// emits a command that references an encoder the build does not contain.
class EncoderCatalog {
  const EncoderCatalog(this._encoders);

  final Set<String> _encoders;

  bool has(String encoder) => _encoders.contains(encoder);

  Set<String> get all => Set.unmodifiable(_encoders);

  static EncoderCatalog fromNames(Iterable<String> names) => EncoderCatalog(
    names.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet(),
  );

  /// Documented defaults for `ffmpeg_kit_flutter_new_full` (LGPL, FFmpeg 8.1.x).
  ///
  /// Note: there is **no software H.264 encoder** in this build (no x264/openh264), so H.264
  /// output requires a hardware encoder. HEVC has a software fallback (kvazaar).
  static EncoderCatalog defaultFor({required bool isApple}) {
    final common = <String>{
      // Software encoders present in the LGPL build
      'mpeg4',
      'libvpx',
      'libvpx-vp9',
      'libkvazaar',
      'libtheora',
      'ffv1',
      'libwebp',
      // Audio
      'aac',
      'libmp3lame',
      'libopus',
      'libvorbis',
      'pcm_s16le',
      'libtwolame',
      'libopencore_amrnb',
      'libshine',
      'libspeex',
      'libvo_amrwbenc',
      // Muxers relevant to us
      'mux:mp4',
      'mux:mov',
      'mux:matroska',
      'mux:webm',
      'mux:avi',
      'mux:3gp',
      'mux:mpeg',
      'mux:mpegts',
      'mux:ogg',
    };
    if (isApple) {
      return EncoderCatalog(
        common..addAll(<String>{
          'h264_videotoolbox',
          'hevc_videotoolbox',
          'prores_videotoolbox',
          'prores_ks',
          'av1_videotoolbox',
        }),
      );
    }
    return EncoderCatalog(
      common..addAll(<String>{
        'h264_mediacodec',
        'hevc_mediacodec',
        'vp8_mediacodec',
        'vp9_mediacodec',
        'av1_mediacodec',
        'prores_ks',
      }),
    );
  }

  /// Parses the output of `ffmpeg -encoders` into a catalogue.
  static EncoderCatalog parseEncoderList(String output) {
    final names = <String>{};
    final pattern = RegExp(r'^\s*[A-Z.]{6}\s+(\S+)', multiLine: true);
    for (final match in pattern.allMatches(output)) {
      final name = match.group(1);
      if (name != null && name != '=') {
        names.add(name);
      }
    }
    return EncoderCatalog(names);
  }
}
