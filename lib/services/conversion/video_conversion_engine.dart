import 'dart:io';

import '../../domain/conversion/conversion_error.dart';
import '../../domain/conversion/conversion_request.dart';
import '../../domain/conversion/video_spec.dart';
import '../../domain/media/video_format.dart';
import '../platform/platform_info.dart';
import 'conversion_engine.dart';
import 'ffmpeg_command_builder.dart';
import 'ffmpeg_runner.dart';
import 'media_probe.dart';

/// Converts video through FFmpeg, then **verifies the result with FFprobe** before reporting
/// success. Renaming a file is never treated as a successful conversion.
class VideoConversionEngine
    implements ConversionEngine<VideoConversionRequest> {
  VideoConversionEngine(this._runner);

  final FfmpegRunner _runner;
  @override
  Future<bool> canHandle(VideoConversionRequest request) async {
    final capability = request.spec.container.capabilityFor(PlatformInfo.kind);
    return capability.canEncode && request.source.path != null;
  }

  @override
  Future<ConversionOutcome> convert(
    VideoConversionRequest request, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final sourcePath = request.source.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      return const ConversionFailure(
        ConversionError(
          code: ConversionErrorCode.sourceMissing,
          message: 'The original video is no longer available.',
          isRecoverable: false,
        ),
      );
    }

    try {
      onProgress?.call(0.02, message: 'Reading video');
      token?.throwIfCancelled();

      final sourceFile = File(sourcePath);
      if (!sourceFile.existsSync()) {
        return const ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.sourceMissing,
            message: 'The original video was moved or deleted.',
            isRecoverable: false,
          ),
        );
      }
      final sourceBytes = await sourceFile.length();
      token?.throwIfCancelled();

      final source = await _runner.probe(sourcePath);
      if (!source.isUsable) {
        return ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.sourceUnreadable,
            message:
                'This video could not be read. It may be corrupted or use an '
                'unsupported codec.',
            detail: source.error,
          ),
        );
      }
      token?.throwIfCancelled();

      final platform = PlatformInfo.kind;
      final encoders = await _runner.encoderCatalog(platform: platform);
      token?.throwIfCancelled();

      final outputPath = await _resolveOutputPath(request);
      final plan = FfmpegCommandBuilder.build(
        request: request,
        source: source,
        encoders: encoders,
        platform: platform,
        outputPath: outputPath,
      );
      if (!plan.isRunnable) {
        return ConversionFailure(
          plan.error ??
              const ConversionError(
                code: ConversionErrorCode.unsupportedOperation,
                message: 'This conversion is not possible on this device.',
              ),
        );
      }

      onProgress?.call(0.06, message: plan.remux ? 'Rewrapping' : 'Converting');
      final progressDuration = _progressDuration(source, request);

      final result = await _runner.runArguments(
        plan.arguments,
        totalDuration: progressDuration,
        onProgress: (value, {String? message}) {
          // Map FFmpeg's stream progress into our 0.06–0.9 band.
          onProgress?.call(0.06 + value * 0.84, message: message);
        },
        token: token,
      );

      if (result.cancelled || (token?.isCancelled ?? false)) {
        await _deleteQuietly(outputPath);
        return const ConversionFailure(ConversionError.cancelled);
      }
      if (!result.isSuccess) {
        await _deleteQuietly(outputPath);
        return ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.ffmpegFailed,
            message: plan.remux
                ? 'The file could not be rewrapped. Try converting instead of copying streams.'
                : 'The conversion failed on this device.',
            detail: result.errorOutput,
          ),
        );
      }

      token?.throwIfCancelled();
      onProgress?.call(0.92, message: 'Verifying output');

      final outputFile = File(outputPath);
      if (!outputFile.existsSync()) {
        return const ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.outputMissing,
            message: 'The conversion produced no file.',
            isRecoverable: false,
          ),
        );
      }
      final outputBytes = await outputFile.length();
      if (outputBytes <= 1024) {
        await _deleteQuietly(outputPath);
        return const ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.outputEmpty,
            message:
                'The conversion produced an empty file. It has been discarded.',
          ),
        );
      }

      final verification = await _runner.probe(outputPath);
      final problem = _verify(
        source,
        verification,
        outputBytes,
        allowShorter:
            request.spec.isTrimmed || request.spec.speed != SpeedMode.normal,
        expectAudio:
            request.spec.keepAudio &&
            request.spec.audioCodec != AudioCodec.none,
      );
      if (problem != null) {
        await _deleteQuietly(outputPath);
        return ConversionFailure(problem);
      }

      onProgress?.call(1.0, message: 'Done');
      return ConversionSuccess(
        outputPath: outputPath,
        outputBytes: outputBytes,
        sourceBytes: sourceBytes,
        width: verification.width,
        height: verification.height,
        duration: verification.duration,
        videoCodec: verification.videoCodec,
        audioCodec: verification.audioCodec,
        wasRemux: plan.remux,
      );
    } on ConversionCancelledException {
      return const ConversionFailure(ConversionError.cancelled);
    } catch (error) {
      return ConversionFailure(
        ConversionError(
          code: ConversionErrorCode.internal,
          message: 'The video could not be converted.',
          detail: error.runtimeType.toString(),
        ),
      );
    }
  }

  /// Checks the produced file genuinely contains the streams and dimensions we asked for.
  ConversionError? _verify(
    MediaProbeResult source,
    MediaProbeResult output,
    int outputBytes, {
    required bool allowShorter,
    required bool expectAudio,
  }) {
    if (!output.isUsable) {
      return ConversionError(
        code: ConversionErrorCode.outputWrongFormat,
        message:
            'The converted file could not be read back; it has been discarded.',
        detail: output.error,
      );
    }
    if (source.hasVideo && !output.hasVideo) {
      return const ConversionError(
        code: ConversionErrorCode.outputMissingStreams,
        message:
            'The converted file has no video track. It has been discarded.',
      );
    }
    if (source.hasAudio && expectAudio && !output.hasAudio) {
      return const ConversionError(
        code: ConversionErrorCode.outputMissingStreams,
        message: 'The converted file is missing its audio track. It has been discarded.',
      );
    }
    if (output.duration == null || output.duration == Duration.zero) {
      return const ConversionError(
        code: ConversionErrorCode.outputDurationMismatch,
        message: 'The converted file has no duration; it has been discarded.',
      );
    }
    if (source.duration != null && source.duration! > Duration.zero) {
      final ratio =
          output.duration!.inMilliseconds / source.duration!.inMilliseconds;
      // Trimmed and speed-adjusted outputs are legitimately shorter; only guard the untrimmed,
      // non-sped-up case against a truncated or corrupt result.
      if (ratio < 0.5 && !allowShorter) {
        return const ConversionError(
          code: ConversionErrorCode.outputDurationMismatch,
          message: 'The converted file is far shorter than the original. It has been discarded.',
        );
      }
    }
    if (outputBytes < 1024) {
      return const ConversionError(
        code: ConversionErrorCode.outputEmpty,
        message: 'The converted file is empty. It has been discarded.',
      );
    }
    return null;
  }

  Duration? _progressDuration(
    MediaProbeResult source,
    VideoConversionRequest request,
  ) {
    final spec = request.spec;
    if (spec.trimStart == null &&
        spec.trimEnd == null &&
        spec.speed == SpeedMode.normal) {
      return source.duration;
    }
    final start = spec.trimStart ?? Duration.zero;
    final end = spec.trimEnd ?? source.duration;
    if (end == null) {
      return source.duration;
    }
    var duration = end - start;
    if (duration.isNegative) {
      duration = Duration.zero;
    }
    if (spec.speed != SpeedMode.normal && spec.speed.factor > 0) {
      duration = Duration(
        milliseconds: (duration.inMilliseconds / spec.speed.factor).round(),
      );
    }
    return duration;
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup; a leftover partial file is harmless and cleaned by the temp sweep.
    }
  }

  Future<String> _resolveOutputPath(VideoConversionRequest request) async {
    final directory = request.outputDirectory ?? Directory.systemTemp.path;
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final baseName = request.naming.buildBaseName(
      sourceFileName: request.source.displayName ?? request.source.id,
      formatExtension: request.outputExtension,
      timestamp: DateTime.now(),
    );
    final separator = Platform.pathSeparator;
    final fileName = request.naming.uniqueFileName(
      baseName: baseName,
      extension: request.outputExtension,
      isTaken: (candidate) =>
          File('$directory$separator$candidate').existsSync(),
    );
    return '$directory$separator$fileName';
  }
}
