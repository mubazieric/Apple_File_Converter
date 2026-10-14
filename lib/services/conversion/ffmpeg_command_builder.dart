import '../../domain/conversion/conversion_error.dart';
import '../../domain/conversion/conversion_request.dart';
import '../../domain/conversion/image_spec.dart' show Rotation;
import '../../domain/conversion/video_spec.dart';
import '../../domain/media/capability.dart';
import '../../domain/media/video_format.dart';
import 'media_probe.dart';

/// A fully-resolved FFmpeg invocation.
class FfmpegPlan {
  const FfmpegPlan({
    required this.arguments,
    this.videoEncoder,
    this.audioEncoder,
    this.remux = false,
    this.warnings = const <String>[],
    this.error,
  });

  final List<String> arguments;
  final String? videoEncoder;
  final String? audioEncoder;

  /// True when streams are copied rather than re-encoded.
  final bool remux;

  /// Non-fatal notes to surface in the UI (e.g. "audio removed because the container cannot
  /// carry it").
  final List<String> warnings;

  /// Set when no valid command can be produced.
  final ConversionError? error;

  bool get isRunnable => error == null && arguments.isNotEmpty;

  /// The full command string, for logging (paths are redacted by the logger).
  String get debugCommand => 'ffmpeg ${arguments.join(' ')}';
}

/// Builds FFmpeg argument lists from a [VideoConversionRequest].
///
/// This class is deliberately pure: no I/O, no plugins, no platform imports beyond the
/// [PlatformKind] enum. That makes the full encoder/muxer decision logic unit-testable, which
/// is how we guarantee we never claim a conversion the engine cannot actually perform.
abstract final class FfmpegCommandBuilder {
  /// Containers that can carry a given video codec.
  static bool containerSupportsVideo(
    VideoContainer container,
    VideoCodec codec,
  ) {
    if (codec == VideoCodec.unknown) {
      return false;
    }
    return switch (container) {
      VideoContainer.mp4 ||
      VideoContainer.mov ||
      VideoContainer.m4v ||
      VideoContainer.threegp => const <VideoCodec>{
        VideoCodec.h264,
        VideoCodec.hevc,
        VideoCodec.mpeg4,
      }.contains(codec),
      VideoContainer.mkv => codec != VideoCodec.unknown,
      VideoContainer.webm => const <VideoCodec>{
        VideoCodec.vp8,
        VideoCodec.vp9,
        VideoCodec.av1,
      }.contains(codec),
      VideoContainer.avi => const <VideoCodec>{
        VideoCodec.mpeg4,
        VideoCodec.h264,
      }.contains(codec),
      VideoContainer.mpeg => codec == VideoCodec.mpeg4,
      VideoContainer.ts => const <VideoCodec>{
        VideoCodec.h264,
        VideoCodec.hevc,
        VideoCodec.mpeg4,
      }.contains(codec),
      VideoContainer.ogv =>
        false, // Theora only; we do not expose Theora targets.
      VideoContainer.wmv ||
      VideoContainer.flv ||
      VideoContainer.unknown => false,
    };
  }

  static bool containerSupportsAudio(
    VideoContainer container,
    AudioCodec codec,
  ) {
    if (codec == AudioCodec.none) {
      return true;
    }
    return switch (container) {
      VideoContainer.mp4 ||
      VideoContainer.mov ||
      VideoContainer.m4v ||
      VideoContainer.threegp => const <AudioCodec>{
        AudioCodec.aac,
        AudioCodec.mp3,
        AudioCodec.pcm,
      }.contains(codec),
      VideoContainer.mkv => true,
      VideoContainer.webm => const <AudioCodec>{
        AudioCodec.opus,
        AudioCodec.vorbis,
      }.contains(codec),
      VideoContainer.avi => const <AudioCodec>{
        AudioCodec.mp3,
        AudioCodec.pcm,
        AudioCodec.aac,
      }.contains(codec),
      VideoContainer.mpeg => const <AudioCodec>{AudioCodec.mp3}.contains(codec),
      VideoContainer.ts => const <AudioCodec>{
        AudioCodec.aac,
        AudioCodec.mp3,
      }.contains(codec),
      VideoContainer.ogv => const <AudioCodec>{
        AudioCodec.vorbis,
        AudioCodec.opus,
      }.contains(codec),
      VideoContainer.wmv ||
      VideoContainer.flv ||
      VideoContainer.unknown => false,
    };
  }

  /// The codec to use when the user did not choose one, given the container.
  static VideoCodec defaultVideoCodecFor(VideoContainer container) =>
      switch (container) {
        VideoContainer.mov => VideoCodec.hevc,
        VideoContainer.webm => VideoCodec.vp9,
        VideoContainer.avi || VideoContainer.mpeg => VideoCodec.mpeg4,
        _ => VideoCodec.h264,
      };

  static AudioCodec defaultAudioCodecFor(VideoContainer container) =>
      switch (container) {
        VideoContainer.webm || VideoContainer.ogv => AudioCodec.opus,
        _ => AudioCodec.aac,
      };

  /// Resolves the concrete encoder name for a video codec, or null when impossible.
  ///
  /// [policy] only affects whether a software fallback is allowed; hardware is always preferred
  /// when present, because it is dramatically faster and more power-efficient.
  static String? resolveVideoEncoder(
    VideoCodec codec,
    PlatformKind platform,
    EncoderCatalog encoders,
    HardwareAcceleration policy,
  ) {
    final hardware = codec.hardwareName(platform);
    final candidates = <String?>[
      hardware,
      if (policy != HardwareAcceleration.require) _softwareFallback(codec),
    ];

    for (final candidate in candidates) {
      if (candidate != null && encoders.has(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static String? _softwareFallback(VideoCodec codec) => switch (codec) {
    VideoCodec.hevc => 'libkvazaar',
    VideoCodec.vp8 => 'libvpx',
    VideoCodec.vp9 => 'libvpx-vp9',
    VideoCodec.mpeg4 => 'mpeg4',
    VideoCodec.prores => 'prores_ks',
    // No software H.264 or AV1 encoder exists in the shipped LGPL build.
    VideoCodec.h264 || VideoCodec.av1 || VideoCodec.unknown => null,
  };

  /// Builds the argument list. Returns a plan whose [FfmpegPlan.error] is set when the
  /// requested conversion cannot be performed on this device.
  static FfmpegPlan build({
    required VideoConversionRequest request,
    required MediaProbeResult source,
    required EncoderCatalog encoders,
    required PlatformKind platform,
    String? outputPath,
  }) {
    final spec = request.spec;
    final container = spec.container;
    final warnings = <String>[];

    final containerCapability = container.capabilityFor(platform);
    if (!containerCapability.canEncode) {
      return FfmpegPlan(
        arguments: const <String>[],
        error: ConversionError(
          code: ConversionErrorCode.unsupportedOutput,
          message: '${container.label} output is not supported.',
          detail: container.id,
          isRecoverable: false,
        ),
      );
    }

    final inputPath = request.source.path;
    if (inputPath == null || inputPath.isEmpty) {
      return const FfmpegPlan(
        arguments: <String>[],
        error: ConversionError(
          code: ConversionErrorCode.sourceMissing,
          message: 'The source file is not available on this device.',
          isRecoverable: false,
        ),
      );
    }

    // ------------------------------------------------------------------ audio/video intent
    final wantsVideo = source.hasVideo && !_isAudioOnlyContainer(container);

    final videoCodec =
        spec.videoCodec ??
        (wantsVideo ? defaultVideoCodecFor(container) : VideoCodec.unknown);
    final audioCodecRequested =
        spec.audioCodec ?? defaultAudioCodecFor(container);

    // ------------------------------------------------------------------ remux decision
    final bool remux = spec.remuxOnly;
    String? videoEncoder;
    String? audioEncoder;

    if (remux && wantsVideo) {
      if (!containerSupportsVideo(
        container,
        MediaProbeResult.codecFromFfprobeName(source.videoCodec),
      )) {
        return FfmpegPlan(
          arguments: const <String>[],
          error: ConversionError(
            code: ConversionErrorCode.unsupportedInput,
            message:
                'The source video codec cannot be stored in ${container.label}. '
                'Turn off "copy streams" to re-encode instead.',
            detail: 'source=${source.videoCodec}',
            isRecoverable: false,
          ),
        );
      }
    }

    if (!remux && wantsVideo) {
      videoEncoder = resolveVideoEncoder(
        videoCodec,
        platform,
        encoders,
        spec.hardware,
      );
      if (videoEncoder == null) {
        return FfmpegPlan(
          arguments: const <String>[],
          error: ConversionError(
            code: ConversionErrorCode.encoderUnavailable,
            message:
                'This device has no ${videoCodec.label} encoder available.',
            detail:
                'codec=${videoCodec.id} hw=${videoCodec.hardwareName(platform)}',
            isRecoverable: true,
          ),
          warnings: warnings,
        );
      }
      if (!containerSupportsVideo(container, videoCodec)) {
        return FfmpegPlan(
          arguments: const <String>[],
          error: ConversionError(
            code: ConversionErrorCode.unsupportedOutput,
            message: '${container.label} cannot carry ${videoCodec.label}.',
            detail: 'container=${container.id} codec=${videoCodec.id}',
            isRecoverable: false,
          ),
        );
      }
    }

    // ------------------------------------------------------------------ audio
    final keepAudio =
        spec.keepAudio &&
        source.hasAudio &&
        audioCodecRequested != AudioCodec.none;
    if (spec.keepAudio &&
        source.hasAudio &&
        !containerSupportsAudio(container, audioCodecRequested)) {
      warnings.add(
        '${container.label} cannot carry ${audioCodecRequested.label}; using AAC.',
      );
    }
    if (!remux && keepAudio) {
      audioEncoder =
          _resolveAudioEncoder(audioCodecRequested, encoders) ??
          _resolveAudioEncoder(AudioCodec.aac, encoders);
      if (audioEncoder == null) {
        warnings.add(
          'No audio encoder was available; the output will be silent.',
        );
      }
    }

    // ------------------------------------------------------------------ dimensions & filters
    final resolvedVideoCodec = remux
        ? MediaProbeResult.codecFromFfprobeName(source.videoCodec)
        : videoCodec;
    final (outW, outH) = (source.width != null && source.height != null)
        ? spec.resolve(source.width!, source.height!)
        : (0, 0);

    final filters = <String>[];
    if (wantsVideo && !remux) {
      var needsScale = false;
      if (outW > 0 &&
          outH > 0 &&
          (outW != source.width || outH != source.height)) {
        needsScale = true;
      }
      if (needsScale) {
        filters.add('scale=$outW:$outH:flags=lanczos');
      }
      final rotateDegrees =
          (_rotationToDegrees(spec.rotation) + source.rotationDegrees) % 360;
      switch (rotateDegrees) {
        case 90:
          filters.add('transpose=1');
        case 180:
          filters.add('transpose=1,transpose=1');
        case 270:
          filters.add('transpose=2');
      }
      if (spec.frameRate != null) {
        filters.add('fps=${spec.frameRate}');
      }
      if (spec.speed != SpeedMode.normal) {
        filters.add('setpts=PTS/${spec.speed.factor}');
      }
      // Guarantee even dimensions and a broadly compatible pixel format for H.264/HEVC.
      if (!needsScale && _requiresEvenDimensions(resolvedVideoCodec)) {
        filters.add('scale=trunc(iw/2)*2:trunc(ih/2)*2');
      }
    }

    // ------------------------------------------------------------------ assemble
    final args = <String>['-hide_banner', '-loglevel', 'error', '-y'];

    if (spec.trimStart != null) {
      args.addAll(<String>['-ss', _seconds(spec.trimStart!)]);
    }
    args.addAll(<String>['-i', inputPath]);

    if (spec.trimStart != null || spec.trimEnd != null) {
      final duration = _trimDuration(source, spec);
      if (duration != null) {
        args.addAll(<String>['-t', _seconds(duration)]);
      }
      args.add('-avoid_negative_ts');
      args.add('make_zero');
    }

    if (remux) {
      args.addAll(<String>['-c', 'copy']);
    } else {
      if (!wantsVideo) {
        args.add('-vn');
      } else {
        args.addAll(<String>['-c:v', videoEncoder!]);
        if (filters.isNotEmpty) {
          args.addAll(<String>['-vf', filters.join(',')]);
        }
        if (_requiresEvenDimensions(resolvedVideoCodec)) {
          args.addAll(<String>['-pix_fmt', 'yuv420p']);
        }
        if (_isHardwareEncoder(videoEncoder)) {
          // MediaCodec/VideoToolbox reject explicit CRF; bitrate mode is used instead.
          args.addAll(<String>['-b:v', '${spec.estimateVideoBitrateKbps()}k']);
        } else {
          args.addAll(<String>['-b:v', '${spec.estimateVideoBitrateKbps()}k']);
          args.addAll(<String>[
            '-maxrate',
            '${(spec.estimateVideoBitrateKbps() * 1.5).round()}k',
          ]);
          args.addAll(<String>[
            '-bufsize',
            '${spec.estimateVideoBitrateKbps() * 2}k',
          ]);
        }
        if (spec.frameRate != null &&
            filters.every((f) => !f.startsWith('fps='))) {
          args.addAll(<String>['-r', '${spec.frameRate}']);
        }
      }

      if (!keepAudio) {
        args.add('-an');
      } else if (audioEncoder != null) {
        args.addAll(<String>['-c:a', audioEncoder]);
        args.addAll(<String>['-b:a', '${spec.estimateAudioBitrateKbps()}k']);
        if (spec.speed != SpeedMode.normal) {
          args.addAll(<String>['-filter:a', 'atempo=${spec.speed.factor}']);
        }
      }
    }

    if (spec.keepMetadata == false) {
      args.addAll(<String>['-map_metadata', '-1']);
    }

    if (const <VideoContainer>{
      VideoContainer.mp4,
      VideoContainer.mov,
      VideoContainer.m4v,
    }.contains(container)) {
      args.addAll(<String>['-movflags', '+faststart']);
    }

    final resolvedOutputPath = outputPath ?? _outputPath(request);
    args.add(resolvedOutputPath);

    return FfmpegPlan(
      arguments: args,
      videoEncoder: remux ? 'copy' : videoEncoder,
      audioEncoder: remux ? 'copy' : audioEncoder,
      remux: remux,
      warnings: warnings,
    );
  }

  static bool _isAudioOnlyContainer(VideoContainer c) =>
      c == VideoContainer.m4v;

  static bool _isHardwareEncoder(String? encoder) =>
      encoder != null &&
      (encoder.contains('mediacodec') || encoder.contains('videotoolbox'));

  static bool _requiresEvenDimensions(VideoCodec codec) =>
      codec == VideoCodec.h264 ||
      codec == VideoCodec.hevc ||
      codec == VideoCodec.mpeg4;

  static String? _resolveAudioEncoder(
    AudioCodec codec,
    EncoderCatalog encoders,
  ) {
    final name = codec.ffmpegName;
    if (name.isEmpty) {
      return null;
    }
    return encoders.has(name) ? name : null;
  }

  static int _rotationToDegrees(Rotation rotation) => rotation.degrees;

  static Duration? _trimDuration(
    MediaProbeResult source,
    VideoConversionSpec spec,
  ) {
    final start = spec.trimStart ?? Duration.zero;
    final end = spec.trimEnd ?? source.duration;
    if (end == null) {
      return null;
    }
    final duration = end - start;
    if (duration.isNegative || duration == Duration.zero) {
      return null;
    }
    return duration;
  }

  static String _seconds(Duration d) =>
      (d.inMilliseconds / 1000.0).toStringAsFixed(3);

  /// Final output path: `<dir>/<naming policy>.<ext>`.
  ///
  /// The concrete directory and collision resolution are the caller's job (it owns the file
  /// system); this only produces the intended path for the plan.
  static String _outputPath(VideoConversionRequest request) {
    final dir = request.outputDirectory ?? '.';
    final base = request.naming.buildBaseName(
      sourceFileName: request.source.displayName ?? request.source.id,
      formatExtension: request.outputExtension,
      timestamp: DateTime.now(),
    );
    final separator = dir.endsWith('/') || dir.endsWith(r'\') ? '' : '/';
    return '$dir$separator$base.${request.outputExtension}';
  }
}
