import 'capability.dart';

/// Video container (file format) taxonomy.
enum VideoContainer {
  mp4(
    id: 'mp4',
    label: 'MP4',
    extensions: <String>['mp4'],
    mimeType: 'video/mp4',
    isPriority: true,
    note: 'Preferred output. Maximises compatibility with Android, Windows and the web.',
  ),
  mov(
    id: 'mov',
    label: 'MOV',
    extensions: <String>['mov'],
    mimeType: 'video/quicktime',
    isPriority: true,
    note: 'Apple QuickTime container; commonly HEVC/H.264 from iPhone.',
  ),
  m4v(
    id: 'm4v',
    label: 'M4V',
    extensions: <String>['m4v'],
    mimeType: 'video/x-m4v',
    isPriority: true,
    note: 'Apple video variant of MP4.',
  ),
  mkv(
    id: 'mkv',
    label: 'MKV',
    extensions: <String>['mkv'],
    mimeType: 'video/x-matroska',
    isPriority: true,
    note: 'Matroska; flexible container, playback support varies by device.',
  ),
  webm(
    id: 'webm',
    label: 'WebM',
    extensions: <String>['webm'],
    mimeType: 'video/webm',
    isPriority: true,
    note: 'VP8/VP9/AV1 + Opus/Vorbis; best for the web.',
  ),
  avi(
    id: 'avi',
    label: 'AVI',
    extensions: <String>['avi'],
    mimeType: 'video/x-msvideo',
    isPriority: true,
    note: 'Legacy container; widely decodable, less ideal for modern codecs.',
  ),
  threegp(
    id: '3gp',
    label: '3GP',
    extensions: <String>['3gp', '3g2'],
    mimeType: 'video/3gpp',
    isPriority: true,
    note: 'Legacy mobile container.',
  ),
  mpeg(
    id: 'mpeg',
    label: 'MPEG/MPG',
    extensions: <String>['mpg', 'mpeg', 'm2v'],
    mimeType: 'video/mpeg',
    isPriority: false,
    note: 'Legacy MPEG-PS/ES.',
  ),
  ts(
    id: 'ts',
    label: 'MPEG-TS',
    extensions: <String>['ts', 'mts', 'm2ts'],
    mimeType: 'video/mp2t',
    isPriority: false,
    note: 'Transport stream, e.g. from camcorders.',
  ),
  wmv(
    id: 'wmv',
    label: 'WMV',
    extensions: <String>['wmv', 'asf'],
    mimeType: 'video/x-ms-wmv',
    isPriority: false,
    note: 'Windows Media; decode support varies.',
  ),
  flv(
    id: 'flv',
    label: 'FLV',
    extensions: <String>['flv'],
    mimeType: 'video/x-flv',
    isPriority: false,
    note: 'Legacy Flash container.',
  ),
  ogv(
    id: 'ogv',
    label: 'OGV',
    extensions: <String>['ogv', 'ogg'],
    mimeType: 'video/ogg',
    isPriority: false,
    note: 'Ogg/Theora.',
  ),
  unknown(
    id: 'unknown',
    label: 'Unknown',
    extensions: <String>[],
    mimeType: 'application/octet-stream',
    isPriority: false,
    note: 'Unrecognised container.',
  );

  const VideoContainer({
    required this.id,
    required this.label,
    required this.extensions,
    required this.mimeType,
    required this.isPriority,
    required this.note,
  });

  final String id;
  final String label;
  final List<String> extensions;
  final String mimeType;

  /// Part of the priority set the product commits to.
  final bool isPriority;
  final String note;

  String get primaryExtension => extensions.isEmpty ? 'bin' : extensions.first;

  /// Containers we are willing to write. MKV/WEBM/AVI/3GP/MPEG/TS/FLV/OGV are written only
  /// where the muxer and chosen codecs are compatible; the engine verifies with FFprobe.
  FormatCapability capabilityFor(PlatformKind platform) {
    switch (this) {
      case VideoContainer.mp4:
      case VideoContainer.mov:
      case VideoContainer.m4v:
        return const FormatCapability(
          canView: true,
          canDecode: true,
          canEncode: true,
          isLossy: true,
        );
      case VideoContainer.mkv:
      case VideoContainer.webm:
      case VideoContainer.avi:
      case VideoContainer.threegp:
      case VideoContainer.mpeg:
      case VideoContainer.ts:
      case VideoContainer.ogv:
        return const FormatCapability(
          canView: true,
          canDecode: true,
          canEncode: true,
          isLossy: true,
          note: 'Output support depends on the selected codecs.',
        );
      case VideoContainer.wmv:
        return const FormatCapability(
          canView: true,
          canDecode: true,
          canEncode: false,
          isLossy: true,
          note: 'Decode only: no WMV muxer is shipped.',
        );
      case VideoContainer.flv:
        return const FormatCapability(
          canView: true,
          canDecode: true,
          canEncode: false,
          isLossy: true,
          note: 'Decode only: FLV output is not offered.',
        );
      case VideoContainer.unknown:
        return FormatCapability.unsupported;
    }
  }

  static VideoContainer fromExtension(String ext) {
    final normalized = ext.toLowerCase().replaceFirst('.', '');
    for (final container in values) {
      if (container.extensions.contains(normalized)) {
        return container;
      }
    }
    return VideoContainer.unknown;
  }

  static VideoContainer fromId(String id) => values.firstWhere(
    (c) => c.id == id.toLowerCase(),
    orElse: () => VideoContainer.unknown,
  );

  /// The containers offered in the UI as conversion targets.
  static List<VideoContainer> encodableTargets(PlatformKind platform) => values
      .where((c) => c.capabilityFor(platform).canEncode)
      .toList(growable: false);
}

/// Video codecs we can attempt.
///
/// Encoding relies primarily on **hardware** encoders (MediaCodec / VideoToolbox), which is
/// what keeps the app LGPL-distributable. Software encoders are only listed where the bundled
/// LGPL FFmpeg build actually provides them.
enum VideoCodec {
  h264(
    id: 'h264',
    label: 'H.264 / AVC',
    ffmpegName: 'libx264',
    hwNameAndroid: 'h264_mediacodec',
    hwNameIos: 'h264_videotoolbox',
    hardwarePreferred: true,
  ),
  hevc(
    id: 'hevc',
    label: 'H.265 / HEVC',
    ffmpegName: 'libx265',
    hwNameAndroid: 'hevc_mediacodec',
    hwNameIos: 'hevc_videotoolbox',
    hardwarePreferred: true,
  ),
  vp8(
    id: 'vp8',
    label: 'VP8',
    ffmpegName: 'libvpx',
    hwNameAndroid: null,
    hwNameIos: null,
    hardwarePreferred: false,
  ),
  vp9(
    id: 'vp9',
    label: 'VP9',
    ffmpegName: 'libvpx-vp9',
    hwNameAndroid: 'vp9_mediacodec',
    hwNameIos: 'vp9_videotoolbox',
    hardwarePreferred: true,
  ),
  av1(
    id: 'av1',
    label: 'AV1',
    ffmpegName: 'libaom-av1',
    hwNameAndroid: 'av1_mediacodec',
    hwNameIos: 'av1_videotoolbox',
    hardwarePreferred: true,
  ),
  mpeg4(
    id: 'mpeg4',
    label: 'MPEG-4 Part 2',
    ffmpegName: 'mpeg4',
    hwNameAndroid: null,
    hwNameIos: null,
    hardwarePreferred: false,
  ),
  prores(
    id: 'prores',
    label: 'Apple ProRes',
    ffmpegName: 'prores',
    hwNameAndroid: null,
    hwNameIos: 'prores_videotoolbox',
    hardwarePreferred: true,
  ),
  unknown(
    id: 'unknown',
    label: 'Unknown',
    ffmpegName: '',
    hwNameAndroid: null,
    hwNameIos: null,
    hardwarePreferred: false,
  );

  const VideoCodec({
    required this.id,
    required this.label,
    required this.ffmpegName,
    required this.hwNameAndroid,
    required this.hwNameIos,
    required this.hardwarePreferred,
  });

  final String id;
  final String label;

  /// Software encoder name inside FFmpeg (may be unavailable in the LGPL build).
  final String ffmpegName;
  final String? hwNameAndroid;
  final String? hwNameIos;
  final bool hardwarePreferred;

  String? hardwareName(PlatformKind platform) => switch (platform) {
    PlatformKind.android => hwNameAndroid,
    PlatformKind.ios => hwNameIos,
    _ => null,
  };

  static VideoCodec fromId(String id) => values.firstWhere(
    (c) => c.id == id.toLowerCase(),
    orElse: () => VideoCodec.unknown,
  );
}

/// Audio codecs for the video pipeline.
enum AudioCodec {
  aac(id: 'aac', label: 'AAC', ffmpegName: 'aac'),
  mp3(id: 'mp3', label: 'MP3', ffmpegName: 'libmp3lame'),
  opus(id: 'opus', label: 'Opus', ffmpegName: 'libopus'),
  vorbis(id: 'vorbis', label: 'Vorbis', ffmpegName: 'libvorbis'),
  pcm(id: 'pcm', label: 'PCM', ffmpegName: 'pcm_s16le'),
  none(id: 'none', label: 'No audio', ffmpegName: '');

  const AudioCodec({
    required this.id,
    required this.label,
    required this.ffmpegName,
  });

  final String id;
  final String label;
  final String ffmpegName;

  static AudioCodec fromId(String id) => values.firstWhere(
    (c) => c.id == id.toLowerCase(),
    orElse: () => AudioCodec.aac,
  );
}
