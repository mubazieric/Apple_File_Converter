import 'package:apple_file_converter/domain/conversion/conversion_error.dart';
import 'package:apple_file_converter/domain/conversion/conversion_request.dart';
import 'package:apple_file_converter/domain/conversion/image_spec.dart'
    show Rotation;
import 'package:apple_file_converter/domain/conversion/video_spec.dart';
import 'package:apple_file_converter/domain/media/capability.dart';
import 'package:apple_file_converter/domain/media/media_item.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:apple_file_converter/domain/media/video_format.dart';
import 'package:apple_file_converter/services/conversion/ffmpeg_command_builder.dart';
import 'package:apple_file_converter/services/conversion/media_probe.dart';
import 'package:flutter_test/flutter_test.dart';

VideoConversionRequest _request({
  VideoConversionSpec? spec,
  String? outputDirectory = '/out',
}) => VideoConversionRequest(
  source: const MediaItem(
    id: 'v1',
    kind: MediaKind.video,
    displayName: 'clip.mov',
    path: '/tmp/in/clip.mov',
  ),
  spec: spec ?? const VideoConversionSpec(),
  outputDirectory: outputDirectory,
);

MediaProbeResult _probe({
  String videoCodec = 'h264',
  bool hasAudio = true,
  String? audioCodec = 'aac',
  int width = 1920,
  int height = 1080,
  int rotation = 0,
}) => MediaProbeResult(
  container: VideoContainer.mov,
  duration: const Duration(seconds: 10),
  width: width,
  height: height,
  frameRate: 30,
  videoCodec: videoCodec,
  audioCodec: hasAudio ? audioCodec : null,
  hasVideo: true,
  hasAudio: hasAudio,
  rotationDegrees: rotation,
);

bool _containsPair(List<String> args, String flag, String value) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == flag && args[i + 1] == value) {
      return true;
    }
  }
  return false;
}

void main() {
  group('FfmpegCommandBuilder encoder selection', () {
    test('prefers the hardware H.264 encoder on iOS', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(container: VideoContainer.mp4),
        ),
        source: _probe(),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
      );
      expect(plan.isRunnable, isTrue);
      expect(plan.videoEncoder, 'h264_videotoolbox');
      expect(
        _containsPair(plan.arguments, '-c:v', 'h264_videotoolbox'),
        isTrue,
      );
    });

    test('fails honestly when no H.264 encoder exists', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(container: VideoContainer.mp4),
        ),
        source: _probe(),
        encoders: EncoderCatalog.fromNames(<String>{'aac'}),
        platform: PlatformKind.android,
      );
      expect(plan.isRunnable, isFalse);
      expect(plan.error!.code, ConversionErrorCode.encoderUnavailable);
    });

    test('falls back to the shipped software HEVC encoder (kvazaar)', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(container: VideoContainer.mov),
        ),
        source: _probe(),
        encoders: EncoderCatalog.fromNames(<String>{'libkvazaar', 'aac'}),
        platform: PlatformKind.ios,
      );
      expect(plan.videoEncoder, 'libkvazaar');
    });

    test('uses VP9 + Opus for WebM', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(container: VideoContainer.webm),
        ),
        source: _probe(videoCodec: 'vp9'),
        encoders: EncoderCatalog.fromNames(<String>{
          'libvpx-vp9',
          'libopus',
          'mux:webm',
        }),
        platform: PlatformKind.ios,
      );
      expect(plan.videoEncoder, 'libvpx-vp9');
      expect(plan.audioEncoder, 'libopus');
    });
  });

  group('FfmpegCommandBuilder remux vs transcode', () {
    test('a remux copies streams and never re-encodes', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(
            container: VideoContainer.mp4,
            remuxOnly: true,
          ),
        ),
        source: _probe(),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
      );
      expect(plan.remux, isTrue);
      expect(_containsPair(plan.arguments, '-c', 'copy'), isTrue);
      expect(plan.arguments.contains('-c:v'), isFalse);
    });

    test('refuses a remux the target container cannot carry', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(
            container: VideoContainer.mp4,
            remuxOnly: true,
          ),
        ),
        source: _probe(videoCodec: 'vp9'),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
      );
      expect(plan.isRunnable, isFalse);
      expect(plan.error!.code, ConversionErrorCode.unsupportedInput);
    });
  });

  group('FfmpegCommandBuilder filters and flags', () {
    test('adds a Lanczos scale filter for a resolution change', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(
            container: VideoContainer.mp4,
            resolution: ResolutionPreset.p720,
          ),
        ),
        source: _probe(),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
      );
      expect(plan.arguments.contains('scale=1280:720:flags=lanczos'), isTrue);
    });

    test('adds a transpose filter for rotation', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(
            container: VideoContainer.mp4,
            rotation: Rotation.clockwise90,
          ),
        ),
        source: _probe(),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
      );
      final filterIndex = plan.arguments.indexOf('-vf');
      expect(filterIndex, isNonNegative);
      expect(plan.arguments[filterIndex + 1], contains('transpose=1'));
    });

    test('drops metadata when the user asks for it', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(
            container: VideoContainer.mp4,
            keepMetadata: false,
          ),
        ),
        source: _probe(),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
      );
      expect(_containsPair(plan.arguments, '-map_metadata', '-1'), isTrue);
    });

    test('removes audio when audio is disabled', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(
            container: VideoContainer.mp4,
            keepAudio: false,
          ),
        ),
        source: _probe(),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
      );
      expect(plan.arguments.contains('-an'), isTrue);
    });

    test('uses the caller-provided output path as the final argument', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(container: VideoContainer.mp4),
        ),
        source: _probe(),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
        outputPath: '/custom/out.mp4',
      );
      expect(plan.arguments.last, '/custom/out.mp4');
    });

    test('faststart is applied to MP4 outputs', () {
      final plan = FfmpegCommandBuilder.build(
        request: _request(
          spec: const VideoConversionSpec(container: VideoContainer.mp4),
        ),
        source: _probe(),
        encoders: EncoderCatalog.defaultFor(isApple: true),
        platform: PlatformKind.ios,
      );
      expect(_containsPair(plan.arguments, '-movflags', '+faststart'), isTrue);
    });
  });
}
