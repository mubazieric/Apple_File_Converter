import '../conversion/conversion_error.dart';
import '../conversion/conversion_request.dart';
import 'job_status.dart';

/// A single unit of work in the conversion queue.
///
/// Deliberately mutable for status/progress so the queue can drive it cheaply, but it carries
/// only what the UI needs. Never store the source media bytes here.
class ConversionJob {
  ConversionJob({
    required this.id,
    required this.request,
    this.status = JobStatus.queued,
    this.progress = 0,
    this.attempt = 0,
    this.error,
    this.outputPath,
    this.outputBytes,
    this.sourceBytes,
    this.message,
    DateTime? queuedAt,
    this.startedAt,
    this.finishedAt,
    this.wasRemux = false,
  }) : queuedAt = queuedAt ?? DateTime.now();

  final String id;
  final ConversionRequest request;

  JobStatus status;

  /// 0.0–1.0. Only meaningful while [JobStatus.isActive].
  double progress;

  /// How many times this job has been attempted (starts at 1 when first run).
  int attempt;

  ConversionError? error;
  String? outputPath;
  int? outputBytes;
  int? sourceBytes;
  String? message;
  bool wasRemux;

  final DateTime queuedAt;
  DateTime? startedAt;
  DateTime? finishedAt;

  bool get isImage => request is ImageConversionRequest;

  String get displayName => request.source.displayName ?? request.source.id;

  /// Bytes saved (positive means the output is smaller).
  int? get bytesSaved {
    final src = sourceBytes ?? request.source.sizeBytes;
    final out = outputBytes;
    if (src == null || out == null) {
      return null;
    }
    return src - out;
  }

  Duration? get elapsed {
    final start = startedAt;
    if (start == null) {
      return null;
    }
    return (finishedAt ?? DateTime.now()).difference(start);
  }

  bool get canRetry =>
      status == JobStatus.failed || status == JobStatus.cancelled;

  @override
  String toString() =>
      'ConversionJob($id, ${status.name}, ${(progress * 100).toStringAsFixed(0)}%)';
}
