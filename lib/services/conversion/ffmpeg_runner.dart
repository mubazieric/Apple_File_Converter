import 'dart:async';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/media_information.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_full/statistics.dart';
import 'package:ffmpeg_kit_flutter_new_full/stream_information.dart';

import '../../domain/media/capability.dart';
import '../../domain/media/video_format.dart';
import 'conversion_engine.dart';
import 'media_probe.dart';

/// The result of a single FFmpeg execution.
class FfmpegRunResult {
  const FfmpegRunResult({
    required this.returnCode,
    this.cancelled = false,
    this.errorOutput,
    this.sessionId,
  });

  final int returnCode;
  final bool cancelled;

  /// A short, redacted tail of FFmpeg's stderr, safe to show in a log.
  final String? errorOutput;
  final int? sessionId;

  bool get isSuccess => !cancelled && returnCode == 0;
}

/// Abstraction over the FFmpeg surface.
///
/// The video engine depends on this interface rather than the plugin directly so that its
/// decision logic can be tested with a fake runner, and so no test ever needs the native
/// binary.
abstract interface class FfmpegRunner {
  /// Runs FFmpeg with an explicit argument vector (never a shell string — this avoids quoting
  /// bugs with spaces and non-ASCII characters in user file names).
  ///
  /// [totalDuration] enables real percentage progress from FFmpeg's statistics callbacks.
  Future<FfmpegRunResult> runArguments(
    List<String> arguments, {
    Duration? totalDuration,
    ProgressCallback? onProgress,
    CancellationToken? token,
  });

  /// Probes a media file. Returns [MediaProbeResult.empty] with an [MediaProbeResult.error] on
  /// failure rather than throwing.
  Future<MediaProbeResult> probe(String path);

  /// The encoders actually available in this build/device.
  Future<EncoderCatalog> encoderCatalog({required PlatformKind platform});
}

/// [FfmpegRunner] backed by `ffmpeg_kit_flutter_new_full`.
///
/// The plugin uses separate native sessions per call, so a cancelled batch does not disturb
/// unrelated work.
class FfmpegKitRunner implements FfmpegRunner {
  FfmpegKitRunner();

  EncoderCatalog? _cachedCatalog;

  @override
  Future<FfmpegRunResult> runArguments(
    List<String> arguments, {
    Duration? totalDuration,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final completer = Completer<FfmpegRunResult>();
    final errorLines = <String>[];
    var sessionId = 0;

    void completeWith(int code, {bool cancelled = false, String? error}) {
      if (completer.isCompleted) {
        return;
      }
      completer.complete(
        FfmpegRunResult(
          returnCode: code,
          cancelled: cancelled,
          errorOutput: error,
          sessionId: sessionId,
        ),
      );
    }

    final session = await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (session) async {
        if (completer.isCompleted) {
          return;
        }
        final returnCode = await session.getReturnCode();
        final value = returnCode?.getValue() ?? -1;
        final cancelled =
            ReturnCode.isCancel(returnCode) || (token?.isCancelled ?? false);
        if (cancelled) {
          completeWith(value, cancelled: true);
          return;
        }
        if (!ReturnCode.isSuccess(returnCode)) {
          completeWith(value, error: _summariseError(errorLines));
          return;
        }
        onProgress?.call(1.0, message: 'Finalising');
        completeWith(0);
      },
      (log) {
        final message = log.getMessage();
        errorLines.add(message);
        // Keep the buffer bounded; only the tail matters for diagnostics.
        if (errorLines.length > 60) {
          errorLines.removeRange(0, errorLines.length - 60);
        }
      },
      (Statistics statistics) {
        if (onProgress == null ||
            totalDuration == null ||
            totalDuration.inMilliseconds <= 0) {
          return;
        }
        final elapsed = statistics.getTime();
        if (elapsed <= 0) {
          return;
        }
        final fraction = (elapsed / totalDuration.inMilliseconds).clamp(
          0.0,
          0.99,
        );
        onProgress(fraction, message: 'Converting');
      },
    );

    sessionId = session.getSessionId() ?? 0;

    // Register cooperative cancellation with the native session.
    if (token != null) {
      unawaited(_cancelWhenRequested(token, session.getSessionId()));
    }

    return completer.future;
  }

  static Future<void> _cancelWhenRequested(
    CancellationToken token,
    int? sessionId,
  ) async {
    while (!token.isCancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await FFmpegKit.cancel(sessionId);
  }

  static String? _summariseError(List<String> lines) {
    if (lines.isEmpty) {
      return null;
    }
    final filtered = lines
        .map((l) => l.trim())
        .where(
          (l) =>
              l.isNotEmpty && !l.startsWith('frame=') && !l.startsWith('size='),
        )
        .toList();
    if (filtered.isEmpty) {
      return null;
    }
    final tail = filtered.length > 3
        ? filtered.sublist(filtered.length - 3)
        : filtered;
    return tail.join(' | ');
  }

  @override
  Future<MediaProbeResult> probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final information = session.getMediaInformation();
      if (information == null) {
        return const MediaProbeResult(error: 'probeReturnedNothing');
      }
      return _mapInformation(information);
    } catch (error) {
      return MediaProbeResult(error: 'probeFailed:${error.runtimeType}');
    }
  }

  MediaProbeResult _mapInformation(MediaInformation information) {
    final streams = information.getStreams();
    StreamInformation? video;
    StreamInformation? audio;
    for (final stream in streams) {
      final type = stream.getType();
      if (type == 'video' && video == null) {
        video = stream;
      } else if (type == 'audio' && audio == null) {
        audio = stream;
      }
    }

    final durationSeconds = double.tryParse(information.getDuration() ?? '');
    final bitrate = int.tryParse(information.getBitrate() ?? '');

    return MediaProbeResult(
      container: _containerFromFormat(information.getFormat()),
      duration: durationSeconds == null
          ? null
          : Duration(milliseconds: (durationSeconds * 1000).round()),
      width: video?.getWidth(),
      height: video?.getHeight(),
      frameRate: _parseRational(
        video?.getAverageFrameRate() ?? video?.getRealFrameRate(),
      ),
      videoCodec: video?.getCodec(),
      audioCodec: audio?.getCodec(),
      hasVideo: video != null,
      hasAudio: audio != null,
      bitrateKbps: bitrate == null ? null : (bitrate / 1000).round(),
      rotationDegrees: _rotationOf(video),
      audioChannels:
          int.tryParse(audio?.getChannelLayout() ?? '') ??
          _channelsFromLayout(audio),
      audioSampleRate: int.tryParse(audio?.getSampleRate() ?? ''),
      pixelFormat: video?.getStringProperty('pix_fmt'),
    );
  }

  static int? _channelsFromLayout(StreamInformation? stream) {
    final layout = stream?.getChannelLayout();
    if (layout == null) {
      return null;
    }
    return switch (layout) {
      'mono' => 1,
      'stereo' => 2,
      _ => null,
    };
  }

  static int _rotationOf(StreamInformation? stream) {
    if (stream == null) {
      return 0;
    }
    final tags = stream.getTags();
    final fromTags = int.tryParse('${tags?['rotate'] ?? ''}');
    if (fromTags != null) {
      return ((fromTags % 360) + 360) % 360;
    }
    final sideData = stream.getAllProperties()?['side_data_list'];
    if (sideData is List) {
      for (final entry in sideData) {
        if (entry is Map) {
          final rotation = entry['rotation'];
          if (rotation is num) {
            return (((-rotation.toInt()) % 360) + 360) % 360;
          }
        }
      }
    }
    return 0;
  }

  static double? _parseRational(String? value) {
    if (value == null) {
      return null;
    }
    if (value.contains('/')) {
      final parts = value.split('/');
      final numerator = double.tryParse(parts.first);
      final denominator = parts.length > 1 ? double.tryParse(parts[1]) : null;
      if (numerator != null && denominator != null && denominator != 0) {
        return numerator / denominator;
      }
      return null;
    }
    return double.tryParse(value);
  }

  static VideoContainer _containerFromFormat(String? format) {
    final value = (format ?? '').toLowerCase();
    if (value.isEmpty) {
      return VideoContainer.unknown;
    }
    if (value.contains('mp4') ||
        value.contains('isom') ||
        value.contains('m4a')) {
      return VideoContainer.mp4;
    }
    if (value.contains('mov') || value.contains('qt')) {
      return VideoContainer.mov;
    }
    if (value.contains('matroska') || value.contains('webm')) {
      return value.contains('webm') ? VideoContainer.webm : VideoContainer.mkv;
    }
    if (value.contains('avi')) {
      return VideoContainer.avi;
    }
    if (value.contains('3gp') || value.contains('3g2')) {
      return VideoContainer.threegp;
    }
    if (value.contains('mpegts') || value.contains('mpeg-ts')) {
      return VideoContainer.ts;
    }
    if (value.contains('mpeg')) {
      return VideoContainer.mpeg;
    }
    if (value.contains('asf') || value.contains('wmv')) {
      return VideoContainer.wmv;
    }
    if (value.contains('flv')) {
      return VideoContainer.flv;
    }
    if (value.contains('ogg')) {
      return VideoContainer.ogv;
    }
    return VideoContainer.unknown;
  }

  @override
  Future<EncoderCatalog> encoderCatalog({
    required PlatformKind platform,
  }) async {
    final cached = _cachedCatalog;
    if (cached != null) {
      return cached;
    }
    final fallback = EncoderCatalog.defaultFor(
      isApple: platform == PlatformKind.ios,
    );
    try {
      final session = await FFmpegKit.executeWithArguments(<String>[
        '-hide_banner',
        '-encoders',
      ]);
      final output = await session.getAllLogsAsString();
      final parsed = EncoderCatalog.parseEncoderList(output ?? '');
      if (parsed.all.length > 10) {
        // Merge in the muxer knowledge that `-encoders` cannot report.
        final catalog = EncoderCatalog.fromNames(<String>{
          ...parsed.all,
          ...fallback.all.where((n) => n.startsWith('mux:')),
        });
        _cachedCatalog = catalog;
        return catalog;
      }
    } catch (_) {
      // Fall through to documented defaults.
    }
    _cachedCatalog = fallback;
    return fallback;
  }
}
