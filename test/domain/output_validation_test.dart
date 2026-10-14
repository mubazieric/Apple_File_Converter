import 'package:apple_file_converter/domain/conversion/conversion_error.dart';
import 'package:apple_file_converter/domain/conversion/output_validation.dart';
import 'package:apple_file_converter/domain/format/format_detector.dart';
import 'package:apple_file_converter/domain/media/image_format.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:apple_file_converter/domain/media/video_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// The output validator is the guard that stops the app reporting a conversion as successful
/// when the produced file is not actually a valid file of the requested kind. These tests pin
/// that behaviour down: extension renaming alone must never count as success.
void main() {
  OutputProbe imageProbe({
    ImageFormat format = ImageFormat.jpeg,
    int bytes = 4096,
    int? width = 100,
    int? height = 100,
  }) {
    return OutputProbe(
      exists: true,
      bytes: bytes,
      detected: DetectedFormat(kind: MediaKind.image, imageFormat: format),
      width: width,
      height: height,
    );
  }

  OutputProbe videoProbe({
    VideoContainer container = VideoContainer.mp4,
    int bytes = 100000,
    int? width = 1920,
    int? height = 1080,
    Duration? duration,
    bool videoStream = true,
    bool audioStream = true,
  }) {
    return OutputProbe(
      exists: true,
      bytes: bytes,
      detected: DetectedFormat(
        kind: MediaKind.video,
        videoContainer: container,
      ),
      width: width,
      height: height,
      duration: duration,
      hasVideoStream: videoStream,
      hasAudioStream: audioStream,
    );
  }

  group('OutputValidator missing and empty outputs', () {
    test('a missing output fails and is marked unrecoverable', () {
      final result = OutputValidator.validate(
        const OutputProbe(exists: false, bytes: 0),
        const OutputExpectation(imageFormat: ImageFormat.jpeg),
      );
      expect(result.isValid, isFalse);
      expect(result.firstProblem!.code, ConversionErrorCode.outputMissing);
      expect(result.firstProblem!.isRecoverable, isFalse);
    });

    test('a file below the minimum size is treated as empty', () {
      final result = OutputValidator.validate(
        imageProbe(bytes: 10),
        const OutputExpectation(imageFormat: ImageFormat.jpeg),
      );
      expect(result.firstProblem!.code, ConversionErrorCode.outputEmpty);
    });

    test('a probe error is surfaced as a validation failure', () {
      final result = OutputValidator.validate(
        const OutputProbe(
          exists: true,
          bytes: 4096,
          probeError: 'ffprobe returned nothing',
        ),
        const OutputExpectation(imageFormat: ImageFormat.jpeg),
      );
      expect(result.firstProblem!.code, ConversionErrorCode.outputWrongFormat);
      expect(result.firstProblem!.detail, 'ffprobe returned nothing');
    });
  });

  group('OutputValidator format checks', () {
    test('a correct JPEG passes', () {
      final result = OutputValidator.validate(
        imageProbe(),
        const OutputExpectation(imageFormat: ImageFormat.jpeg, width: 100),
      );
      expect(result.isValid, isTrue, reason: result.problems.toString());
    });

    test('a PNG masquerading as a JPEG is rejected', () {
      final result = OutputValidator.validate(
        imageProbe(format: ImageFormat.png),
        const OutputExpectation(imageFormat: ImageFormat.jpeg),
      );
      expect(result.firstProblem!.code, ConversionErrorCode.outputWrongFormat);
    });

    test('an image request that produced a video is rejected', () {
      final result = OutputValidator.validate(
        videoProbe(),
        const OutputExpectation(imageFormat: ImageFormat.png),
      );
      expect(result.firstProblem!.code, ConversionErrorCode.outputWrongFormat);
      expect(result.firstProblem!.message, contains('not a valid image'));
    });

    test('HEIC and HEIF are treated as the same family', () {
      for (final (expected, actual) in <(ImageFormat, ImageFormat)>[
        (ImageFormat.heic, ImageFormat.heif),
        (ImageFormat.heif, ImageFormat.heic),
      ]) {
        final result = OutputValidator.validate(
          imageProbe(format: actual),
          OutputExpectation(imageFormat: expected),
        );
        expect(result.isValid, isTrue, reason: '$expected vs $actual');
      }
    });

    test('no other image format is aliased', () {
      final result = OutputValidator.validate(
        imageProbe(format: ImageFormat.webp),
        const OutputExpectation(imageFormat: ImageFormat.jpeg),
      );
      expect(result.isValid, isFalse);
    });
  });

  group('OutputValidator container checks', () {
    test('MP4 output verified as MOV is accepted (ISO base media family)', () {
      final result = OutputValidator.validate(
        videoProbe(container: VideoContainer.mov),
        const OutputExpectation(container: VideoContainer.mp4),
      );
      expect(result.isValid, isTrue, reason: result.problems.toString());
    });

    test('MKV where MP4 was requested is rejected', () {
      final result = OutputValidator.validate(
        videoProbe(container: VideoContainer.mkv),
        const OutputExpectation(container: VideoContainer.mp4),
      );
      expect(result.firstProblem!.code, ConversionErrorCode.outputWrongFormat);
    });

    test('a video request that produced an image is rejected', () {
      final result = OutputValidator.validate(
        imageProbe(),
        const OutputExpectation(container: VideoContainer.mp4),
      );
      expect(result.firstProblem!.message, contains('not a valid video'));
    });
  });

  group('OutputValidator dimension, duration and stream checks', () {
    test('dimensions within tolerance pass and outside fail', () {
      const expectation = OutputExpectation(
        imageFormat: ImageFormat.jpeg,
        width: 1000,
        height: 500,
      );
      expect(
        OutputValidator.validate(
          imageProbe(width: 1001, height: 501),
          expectation,
        ).isValid,
        isTrue,
      );
      final failed = OutputValidator.validate(
        imageProbe(width: 1200, height: 500),
        expectation,
      );
      expect(
        failed.firstProblem!.code,
        ConversionErrorCode.outputWrongDimensions,
      );
    });

    test('duration within tolerance passes and outside fails', () {
      const expectation = OutputExpectation(
        container: VideoContainer.mp4,
        duration: Duration(seconds: 10),
      );
      expect(
        OutputValidator.validate(
          videoProbe(duration: const Duration(milliseconds: 10500)),
          expectation,
        ).isValid,
        isTrue,
      );
      final failed = OutputValidator.validate(
        videoProbe(duration: const Duration(seconds: 30)),
        expectation,
      );
      expect(
        failed.firstProblem!.code,
        ConversionErrorCode.outputDurationMismatch,
      );
    });

    test('a missing video or audio stream is reported', () {
      const expectation = OutputExpectation(
        container: VideoContainer.mp4,
        requiresVideoStream: true,
        requiresAudioStream: true,
      );
      final noVideo = OutputValidator.validate(
        videoProbe(videoStream: false),
        expectation,
      );
      expect(
        noVideo.firstProblem!.code,
        ConversionErrorCode.outputMissingStreams,
      );

      final noAudio = OutputValidator.validate(
        videoProbe(audioStream: false),
        expectation,
      );
      expect(
        noAudio.firstProblem!.code,
        ConversionErrorCode.outputMissingStreams,
      );
    });

    test('several problems are all reported', () {
      final result = OutputValidator.validate(
        videoProbe(
          container: VideoContainer.mkv,
          width: 640,
          height: 480,
          videoStream: false,
          audioStream: false,
        ),
        const OutputExpectation(
          container: VideoContainer.mp4,
          width: 1920,
          height: 1080,
          requiresVideoStream: true,
          requiresAudioStream: true,
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.problems.length, greaterThanOrEqualTo(4));
    });
  });
}
