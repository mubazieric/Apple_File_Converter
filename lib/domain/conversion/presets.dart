import '../media/image_format.dart';
import '../media/video_format.dart';
import 'image_spec.dart';
import 'video_spec.dart';

/// Ready-made video presets.
///
/// These map to **real** encoder parameters. They are described in terms of *typical* target
/// services, but we deliberately do not promise that a third-party app or service will accept
/// the result — that depends on the service's own limits, which change without notice.
enum VideoPreset {
  maximumCompatibility(
    id: 'max_compat',
    label: 'Maximum compatibility',
    description:
        'MP4 · H.264 · AAC · original resolution. Plays almost anywhere.',
    icon: 'devices',
  ),
  highQuality(
    id: 'high_quality',
    label: 'High quality',
    description:
        'MP4 · H.264 · AAC · high bitrate, keeps the original resolution.',
    icon: 'hd',
  ),
  smallerFile(
    id: 'smaller',
    label: 'Smaller file',
    description: 'MP4 · H.264 · 720p. A good size/quality balance.',
    icon: 'compress',
  ),
  messaging(
    id: 'messaging',
    label: 'Messaging',
    description:
        'MP4 · H.264 · 720p, modest bitrate for chat apps and WhatsApp.',
    icon: 'chat',
  ),
  socialMedia(
    id: 'social',
    label: 'Social media',
    description: 'MP4 · H.264 · 1080p. Good for feeds and stories.',
    icon: 'share',
  ),
  email(
    id: 'email',
    label: 'Email friendly',
    description: 'MP4 · H.264 · 480p, low bitrate to keep attachments small.',
    icon: 'mail',
  ),
  archive(
    id: 'archive',
    label: 'Archive quality',
    description:
        'MP4 · HEVC where supported · maximum bitrate, original resolution.',
    icon: 'archive',
  ),
  audioOnly(
    id: 'audio_only',
    label: 'Audio only (M4A)',
    description: 'Strips video and keeps the audio track.',
    icon: 'music',
  ),
  custom(
    id: 'custom',
    label: 'Custom',
    description: 'Your own settings.',
    icon: 'tune',
  );

  const VideoPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String id;
  final String label;
  final String description;
  final String icon;

  bool get isAudioOnly => this == VideoPreset.audioOnly;

  /// Builds a concrete specification. Deterministic and pure, so it is unit-tested.
  VideoConversionSpec toSpec() {
    switch (this) {
      case VideoPreset.maximumCompatibility:
        return const VideoConversionSpec(
          container: VideoContainer.mp4,
          videoCodec: VideoCodec.h264,
          audioCodec: AudioCodec.aac,
          resolution: ResolutionPreset.original,
          frameRate: 30,
          quality: VideoQuality.high,
          audioBitrateKbps: 128,
        );
      case VideoPreset.highQuality:
        return const VideoConversionSpec(
          container: VideoContainer.mp4,
          videoCodec: VideoCodec.h264,
          audioCodec: AudioCodec.aac,
          resolution: ResolutionPreset.original,
          quality: VideoQuality.high,
          audioBitrateKbps: 192,
        );
      case VideoPreset.smallerFile:
        return const VideoConversionSpec(
          container: VideoContainer.mp4,
          videoCodec: VideoCodec.h264,
          audioCodec: AudioCodec.aac,
          resolution: ResolutionPreset.p720,
          frameRate: 30,
          quality: VideoQuality.smaller,
          audioBitrateKbps: 128,
        );
      case VideoPreset.messaging:
        return const VideoConversionSpec(
          container: VideoContainer.mp4,
          videoCodec: VideoCodec.h264,
          audioCodec: AudioCodec.aac,
          resolution: ResolutionPreset.p720,
          frameRate: 30,
          quality: VideoQuality.balanced,
          audioBitrateKbps: 96,
        );
      case VideoPreset.socialMedia:
        return const VideoConversionSpec(
          container: VideoContainer.mp4,
          videoCodec: VideoCodec.h264,
          audioCodec: AudioCodec.aac,
          resolution: ResolutionPreset.p1080,
          frameRate: 30,
          quality: VideoQuality.high,
          audioBitrateKbps: 192,
        );
      case VideoPreset.email:
        return const VideoConversionSpec(
          container: VideoContainer.mp4,
          videoCodec: VideoCodec.h264,
          audioCodec: AudioCodec.aac,
          resolution: ResolutionPreset.p480,
          frameRate: 24,
          quality: VideoQuality.smaller,
          audioBitrateKbps: 64,
        );
      case VideoPreset.archive:
        return const VideoConversionSpec(
          container: VideoContainer.mp4,
          videoCodec: VideoCodec.hevc,
          audioCodec: AudioCodec.aac,
          resolution: ResolutionPreset.original,
          quality: VideoQuality.maximum,
          audioBitrateKbps: 256,
        );
      case VideoPreset.audioOnly:
        return const VideoConversionSpec(
          container: VideoContainer.m4v,
          videoCodec: null,
          audioCodec: AudioCodec.aac,
          keepAudio: true,
          audioBitrateKbps: 192,
        );
      case VideoPreset.custom:
        return const VideoConversionSpec();
    }
  }

  static VideoPreset fromId(String id) =>
      values.firstWhere((p) => p.id == id, orElse: () => VideoPreset.custom);
}

/// Ready-made image presets.
enum ImagePreset {
  jpegDefault(
    id: 'jpeg_default',
    label: 'Convert to JPEG',
    description:
        'JPEG · 90% quality. The recommended one-tap conversion for photos.',
  ),
  pngLossless(
    id: 'png_lossless',
    label: 'PNG (lossless)',
    description: 'PNG · lossless, keeps transparency. Larger files.',
  ),
  webEfficient(
    id: 'web_efficient',
    label: 'Web (smaller)',
    description: 'WebP · 80% quality · longest edge 1600 px. Small, modern, web-friendly.',
  ),
  shareOptimised(
    id: 'share',
    label: 'Share optimised',
    description: 'JPEG · 85% quality · longest edge 2048 px. Good for messaging and email.',
  ),
  thumbnail(
    id: 'thumbnail',
    label: 'Thumbnail',
    description: 'JPEG · 85% quality · longest edge 512 px.',
  ),
  sizeReduced(
    id: 'size_reduced',
    label: 'Reduce size 50%',
    description: 'JPEG · 85% quality · 50% of the original dimensions.',
  ),
  custom(id: 'custom', label: 'Custom', description: 'Your own settings.');

  const ImagePreset({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  ImageConversionSpec toSpec() {
    switch (this) {
      case ImagePreset.jpegDefault:
        return const ImageConversionSpec(
          outputFormat: ImageFormat.jpeg,
          quality: 90,
        );
      case ImagePreset.pngLossless:
        return const ImageConversionSpec(outputFormat: ImageFormat.png);
      case ImagePreset.webEfficient:
        return const ImageConversionSpec(
          outputFormat: ImageFormat.webp,
          quality: 80,
          resize: ResizeSpec.longestEdge(1600),
        );
      case ImagePreset.shareOptimised:
        return const ImageConversionSpec(
          outputFormat: ImageFormat.jpeg,
          quality: 85,
          resize: ResizeSpec.longestEdge(2048),
        );
      case ImagePreset.thumbnail:
        return const ImageConversionSpec(
          outputFormat: ImageFormat.jpeg,
          quality: 85,
          resize: ResizeSpec.longestEdge(512),
        );
      case ImagePreset.sizeReduced:
        return const ImageConversionSpec(
          outputFormat: ImageFormat.jpeg,
          quality: 85,
          resize: ResizeSpec.percentage(50),
        );
      case ImagePreset.custom:
        return const ImageConversionSpec();
    }
  }

  static ImagePreset fromId(String id) =>
      values.firstWhere((p) => p.id == id, orElse: () => ImagePreset.custom);
}
