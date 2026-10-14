import 'package:apple_file_converter/domain/conversion/video_spec.dart';
import 'package:apple_file_converter/domain/media/capability.dart';
import 'package:apple_file_converter/domain/media/video_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoConversionSpec.resolve', () {
    test('original keeps source dimensions, rounded to even numbers', () {
      const spec = VideoConversionSpec(resolution: ResolutionPreset.original);
      expect(spec.resolve(1921, 1081), (1922, 1082));
    });

    test('1080p downscales landscape footage and preserves aspect', () {
      const spec = VideoConversionSpec(resolution: ResolutionPreset.p1080);
      expect(spec.resolve(3840, 2160), (1920, 1080));
    });

    test('does not upscale smaller footage', () {
      const spec = VideoConversionSpec(resolution: ResolutionPreset.p1080);
      expect(spec.resolve(1280, 720), (1280, 720));
    });

    test('handles portrait footage using the short edge', () {
      const spec = VideoConversionSpec(resolution: ResolutionPreset.p720);
      expect(spec.resolve(1080, 1920), (720, 1280));
    });

    test('custom dimensions are made even and never zero', () {
      const spec = VideoConversionSpec(
        resolution: ResolutionPreset.custom,
        customWidth: 101,
        customHeight: 51,
      );
      expect(spec.resolve(4000, 3000), (102, 52));
    });
  });

  group('VideoConversionSpec bitrate estimation', () {
    test('explicit bitrate wins over the quality table', () {
      const spec = VideoConversionSpec(videoBitrateKbps: 1234);
      expect(spec.estimateVideoBitrateKbps(), 1234);
    });

    test('higher quality tiers produce larger estimates', () {
      const smaller = VideoConversionSpec(
        resolution: ResolutionPreset.p1080,
        quality: VideoQuality.smaller,
      );
      const high = VideoConversionSpec(
        resolution: ResolutionPreset.p1080,
        quality: VideoQuality.high,
      );
      expect(
        smaller.estimateVideoBitrateKbps(),
        lessThan(high.estimateVideoBitrateKbps()),
      );
    });

    test('audio bitrate is zero when audio is disabled', () {
      const spec = VideoConversionSpec(keepAudio: false);
      expect(spec.estimateAudioBitrateKbps(), 0);
    });

    test('estimated size grows with duration', () {
      const spec = VideoConversionSpec(resolution: ResolutionPreset.p720);
      final short = spec.estimateOutputBytes(const Duration(seconds: 1));
      final long = spec.estimateOutputBytes(const Duration(seconds: 10));
      expect(long, greaterThan(short));
    });
  });

  group('VideoConversionSpec.needsReencode', () {
    test('a pure container change does not need re-encoding', () {
      const spec = VideoConversionSpec(
        container: VideoContainer.mp4,
        remuxOnly: true,
      );
      expect(spec.needsReencode, isFalse);
    });

    test('trimming or speed changes force a re-encode', () {
      expect(
        const VideoConversionSpec(
          remuxOnly: true,
          trimStart: Duration(seconds: 1),
        ).needsReencode,
        isTrue,
      );
      expect(
        const VideoConversionSpec(
          remuxOnly: true,
          speed: SpeedMode.x2,
        ).needsReencode,
        isTrue,
      );
    });
  });

  group('VideoContainer', () {
    test('WMV and FLV are explicitly not encodable', () {
      expect(
        VideoContainer.wmv.capabilityFor(PlatformKind.android).canEncode,
        isFalse,
      );
      expect(
        VideoContainer.flv.capabilityFor(PlatformKind.ios).canEncode,
        isFalse,
      );
    });

    test('MP4/MOV/M4V are encodable on both mobile platforms', () {
      for (final container in <VideoContainer>[
        VideoContainer.mp4,
        VideoContainer.mov,
        VideoContainer.m4v,
      ]) {
        expect(container.capabilityFor(PlatformKind.android).canEncode, isTrue);
        expect(container.capabilityFor(PlatformKind.ios).canEncode, isTrue);
      }
    });
  });
}
