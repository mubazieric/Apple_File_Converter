import '../format/format_detector.dart';
import '../media/image_format.dart';
import '../media/media_kind.dart';
import '../media/video_format.dart';
import 'conversion_error.dart';

/// What a probe of the produced file actually found.
class OutputProbe {
  const OutputProbe({
    required this.exists,
    required this.bytes,
    this.detected = DetectedFormat.unknown,
    this.width,
    this.height,
    this.duration,
    this.hasVideoStream = false,
    this.hasAudioStream = false,
    this.videoCodec,
    this.audioCodec,
    this.probeError,
  });

  final bool exists;
  final int bytes;
  final DetectedFormat detected;
  final int? width;
  final int? height;
  final Duration? duration;
  final bool hasVideoStream;
  final bool hasAudioStream;
  final String? videoCodec;
  final String? audioCodec;

  /// Set when the prober itself failed; treated as a validation failure.
  final String? probeError;
}

/// What the produced file must satisfy.
class OutputExpectation {
  const OutputExpectation({
    this.imageFormat,
    this.container,
    this.width,
    this.height,
    this.dimensionTolerance = 2,
    this.duration,
    this.durationTolerance = const Duration(seconds: 1),
    this.requiresVideoStream = false,
    this.requiresAudioStream = false,
    this.minimumBytes = 128,
  });

  final ImageFormat? imageFormat;
  final VideoContainer? container;

  /// Expected output dimensions; null means "do not check".
  final int? width;
  final int? height;

  /// Allow a small rounding difference (encoders round to even numbers).
  final int dimensionTolerance;

  final Duration? duration;
  final Duration durationTolerance;

  final bool requiresVideoStream;
  final bool requiresAudioStream;
  final int minimumBytes;
}

class ValidationResult {
  const ValidationResult(this.problems);

  final List<ConversionError> problems;

  bool get isValid => problems.isEmpty;

  ConversionError? get firstProblem => problems.isEmpty ? null : problems.first;
}

/// The mandatory output validation step.
///
/// A conversion is only reported as successful when the produced file is a *valid* file of the
/// requested kind — not merely a file that has the right extension.
abstract final class OutputValidator {
  static ValidationResult validate(
    OutputProbe probe,
    OutputExpectation expected,
  ) {
    final problems = <ConversionError>[];

    if (!probe.exists) {
      problems.add(
        const ConversionError(
          code: ConversionErrorCode.outputMissing,
          message: 'The conversion produced no file.',
          isRecoverable: false,
        ),
      );
      return ValidationResult(problems);
    }

    if (probe.bytes < expected.minimumBytes) {
      problems.add(
        ConversionError(
          code: ConversionErrorCode.outputEmpty,
          message: 'The conversion produced an empty or truncated file.',
          detail: 'bytes=${probe.bytes}',
          isRecoverable: false,
        ),
      );
      return ValidationResult(problems);
    }

    if (probe.probeError != null) {
      problems.add(
        ConversionError(
          code: ConversionErrorCode.outputWrongFormat,
          message:
              'The converted file could not be read back for verification.',
          detail: probe.probeError,
        ),
      );
      return ValidationResult(problems);
    }

    // Format / container must match what we asked for.
    final detected = probe.detected;
    if (expected.imageFormat != null) {
      if (detected.kind != MediaKind.image) {
        problems.add(
          const ConversionError(
            code: ConversionErrorCode.outputWrongFormat,
            message: 'The converted file is not a valid image.',
          ),
        );
      } else if (detected.imageFormat != expected.imageFormat &&
          !_imageFormatsCompatible(
            expected.imageFormat!,
            detected.imageFormat,
          )) {
        problems.add(
          ConversionError(
            code: ConversionErrorCode.outputWrongFormat,
            message: 'The converted image is not the requested format.',
            detail:
                'expected=${expected.imageFormat!.id} got=${detected.imageFormat.id}',
          ),
        );
      }
    }

    if (expected.container != null) {
      if (detected.kind != MediaKind.video) {
        problems.add(
          const ConversionError(
            code: ConversionErrorCode.outputWrongFormat,
            message: 'The converted file is not a valid video container.',
          ),
        );
      } else if (!_containersCompatible(
        expected.container!,
        detected.videoContainer,
      )) {
        problems.add(
          ConversionError(
            code: ConversionErrorCode.outputWrongFormat,
            message: 'The converted video is not in the requested container.',
            detail:
                'expected=${expected.container!.id} got=${detected.videoContainer.id}',
          ),
        );
      }
    }

    // Dimensions.
    if (expected.width != null && probe.width != null) {
      if ((probe.width! - expected.width!).abs() >
          expected.dimensionTolerance) {
        problems.add(
          ConversionError(
            code: ConversionErrorCode.outputWrongDimensions,
            message: 'The output has unexpected dimensions.',
            detail: 'expected width ${expected.width}, got ${probe.width}',
          ),
        );
      }
    }
    if (expected.height != null && probe.height != null) {
      if ((probe.height! - expected.height!).abs() >
          expected.dimensionTolerance) {
        problems.add(
          ConversionError(
            code: ConversionErrorCode.outputWrongDimensions,
            message: 'The output has unexpected dimensions.',
            detail: 'expected height ${expected.height}, got ${probe.height}',
          ),
        );
      }
    }

    // Duration.
    if (expected.duration != null && probe.duration != null) {
      final delta = (probe.duration! - expected.duration!).abs();
      if (delta > expected.durationTolerance) {
        problems.add(
          ConversionError(
            code: ConversionErrorCode.outputDurationMismatch,
            message: 'The output has an unexpected duration.',
            detail:
                'expected ${expected.duration!.inMilliseconds}ms, '
                'got ${probe.duration!.inMilliseconds}ms',
          ),
        );
      }
    }

    // Streams.
    if (expected.requiresVideoStream && !probe.hasVideoStream) {
      problems.add(
        const ConversionError(
          code: ConversionErrorCode.outputMissingStreams,
          message: 'The output is missing its video track.',
        ),
      );
    }
    if (expected.requiresAudioStream && !probe.hasAudioStream) {
      problems.add(
        const ConversionError(
          code: ConversionErrorCode.outputMissingStreams,
          message: 'The output is missing its audio track.',
        ),
      );
    }

    return ValidationResult(problems);
  }

  /// MP4/M4V/MOV are all ISO base media files; an muxer may legitimately report a compatible
  /// brand associated with a sibling container, so those are treated as equivalent.
  static bool _containersCompatible(
    VideoContainer expected,
    VideoContainer actual,
  ) {
    if (expected == actual) {
      return true;
    }
    const isoFamily = <VideoContainer>{
      VideoContainer.mp4,
      VideoContainer.mov,
      VideoContainer.m4v,
    };
    return isoFamily.contains(expected) && isoFamily.contains(actual);
  }

  /// JPEG is detected as `jpeg` for both `.jpg` and `.jpeg`; TIFF covers `.tif`. No other
  /// aliasing is accepted — we do not treat PNG as JPEG, etc.
  static bool _imageFormatsCompatible(
    ImageFormat expected,
    ImageFormat actual,
  ) {
    if (expected == actual) {
      return true;
    }
    return (expected == ImageFormat.heic && actual == ImageFormat.heif) ||
        (expected == ImageFormat.heif && actual == ImageFormat.heic);
  }
}
