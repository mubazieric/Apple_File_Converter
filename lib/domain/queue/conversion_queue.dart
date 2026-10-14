import '../conversion/conversion_error.dart';
import '../conversion/conversion_request.dart';
import 'conversion_job.dart';
import 'job_status.dart';

/// Aggregate counts for the progress UI.
class QueueStats {
  const QueueStats({
    required this.total,
    required this.queued,
    required this.active,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.skipped,
    required this.overallProgress,
  });

  final int total;
  final int queued;
  final int active;
  final int completed;
  final int failed;
  final int cancelled;
  final int skipped;

  /// 0.0–1.0 across the whole batch.
  final double overallProgress;

  int get finished => completed + failed + cancelled + skipped;
  bool get isIdle => total == 0;
  bool get isRunning => active > 0;
  bool get isComplete => total > 0 && finished == total;
  bool get hasFailures => failed > 0;
}

/// In-memory conversion queue with an explicit, tested state machine.
///
/// The queue is pure domain logic: it owns no timers and performs no I/O. The application
/// layer drives it (`startNext`, progress updates) and persists snapshots.
class ConversionQueue {
  ConversionQueue({this.maxConcurrentJobs = 2})
    : assert(maxConcurrentJobs >= 1 && maxConcurrentJobs <= 8);

  /// Bounded concurrency — important for low-memory devices.
  int maxConcurrentJobs;

  final List<ConversionJob> _jobs = <ConversionJob>[];

  List<ConversionJob> get jobs => List.unmodifiable(_jobs);

  List<ConversionJob> get activeJobs =>
      _jobs.where((j) => j.status.isActive).toList(growable: false);

  int get activeCount => _jobs.where((j) => j.status.isActive).length;

  bool get isIdle =>
      activeCount == 0 && !_jobs.any((j) => j.status == JobStatus.queued);

  ConversionJob? jobById(String id) {
    for (final job in _jobs) {
      if (job.id == id) {
        return job;
      }
    }
    return null;
  }

  /// Adds jobs at the end of the queue. Returns the number enqueued.
  int enqueue(Iterable<ConversionJob> jobs) {
    var count = 0;
    for (final job in jobs) {
      _jobs.add(job);
      count++;
    }
    return count;
  }

  /// Picks the next job that may start, respecting [maxConcurrentJobs].
  ///
  /// Returns null when the queue is at capacity or nothing is queued.
  ConversionJob? nextRunnable() {
    if (activeCount >= maxConcurrentJobs) {
      return null;
    }
    for (final job in _jobs) {
      if (job.status == JobStatus.queued) {
        return job;
      }
    }
    return null;
  }

  /// Marks a queued job as started. Returns false for an invalid transition.
  bool start(String id) {
    final job = jobById(id);
    if (job == null || job.status != JobStatus.queued) {
      return false;
    }
    if (activeCount >= maxConcurrentJobs) {
      return false;
    }
    job
      ..status = JobStatus.preparing
      ..attempt = job.attempt + 1
      ..startedAt = DateTime.now()
      ..finishedAt = null
      ..error = null
      ..progress = 0;
    return true;
  }

  /// Valid transition: preparing → processing → validating.
  bool advanceTo(String id, JobStatus status) {
    final job = jobById(id);
    if (job == null || !_canTransition(job.status, status)) {
      return false;
    }
    job.status = status;
    if (status == JobStatus.processing && job.progress == 0) {
      job.progress = 0.01;
    }
    return true;
  }

  bool updateProgress(
    String id,
    double progress, {
    String? message,
    int? outputBytes,
  }) {
    final job = jobById(id);
    if (job == null || job.status.isTerminal) {
      return false;
    }
    job.progress = progress.clamp(0, 1);
    if (message != null) {
      job.message = message;
    }
    if (outputBytes != null) {
      job.outputBytes = outputBytes;
    }
    return true;
  }

  bool complete(String id, ConversionSuccess outcome) {
    final job = jobById(id);
    if (job == null || job.status.isTerminal) {
      return false;
    }
    job
      ..status = JobStatus.completed
      ..progress = 1
      ..outputPath = outcome.outputPath
      ..outputBytes = outcome.outputBytes
      ..sourceBytes = outcome.sourceBytes
      ..wasRemux = outcome.wasRemux
      ..finishedAt = DateTime.now()
      ..error = null;
    return true;
  }

  bool fail(String id, ConversionError error) {
    final job = jobById(id);
    if (job == null || job.status.isTerminal) {
      return false;
    }
    job
      ..status = JobStatus.failed
      ..error = error
      ..finishedAt = DateTime.now();
    return true;
  }

  bool skip(String id, {String? reason}) {
    final job = jobById(id);
    if (job == null || job.status.isTerminal) {
      return false;
    }
    job
      ..status = JobStatus.skipped
      ..message = reason
      ..finishedAt = DateTime.now();
    return true;
  }

  /// Cancels a job. A job that is actively encoding is marked cancelled; the caller is
  /// responsible for actually stopping the encoder.
  bool cancel(String id) {
    final job = jobById(id);
    if (job == null || job.status.isTerminal) {
      return false;
    }
    job
      ..status = JobStatus.cancelled
      ..error = ConversionError.cancelled
      ..finishedAt = DateTime.now();
    return true;
  }

  /// Cancels everything not yet finished. Returns how many jobs were affected.
  int cancelAll() {
    var count = 0;
    for (final job in _jobs) {
      if (!job.status.isTerminal) {
        cancel(job.id);
        count++;
      }
    }
    return count;
  }

  /// Puts a failed/cancelled job back into the queue.
  ///
  /// This is a **restart**, never a resume: image and video encoders here cannot continue a
  /// partially written output, so the job begins again from the start.
  bool retry(String id) {
    final job = jobById(id);
    if (job == null || !job.canRetry) {
      return false;
    }
    job
      ..status = JobStatus.queued
      ..progress = 0
      ..error = null
      ..message = 'Waiting to retry'
      ..startedAt = null
      ..finishedAt = null
      ..outputPath = null
      ..outputBytes = null;
    return true;
  }

  int retryAllFailed() {
    var count = 0;
    for (final job in _jobs.where((j) => j.canRetry).toList(growable: false)) {
      if (retry(job.id)) {
        count++;
      }
    }
    return count;
  }

  /// Removes finished jobs from the list.
  int clearFinished() {
    final before = _jobs.length;
    _jobs.removeWhere((j) => j.status.isTerminal);
    return before - _jobs.length;
  }

  void clearAll() => _jobs.clear();

  /// Called on app start: any job that was mid-flight when the process died is marked failed
  /// so the user sees an honest state rather than a job that appears to be running forever.
  int recoverAfterRestart() {
    var count = 0;
    for (final job in _jobs) {
      if (job.status.isActive) {
        job
          ..status = JobStatus.failed
          ..error = const ConversionError(
            code: ConversionErrorCode.internal,
            message: 'Interrupted when the app closed. Retry to convert again.',
            detail: 'recovered-after-restart',
          )
          ..message = 'Interrupted';
        count++;
      }
    }
    return count;
  }

  /// Converts the queue into a persistable snapshot (paths, spec and status only — no media
  /// bytes).
  List<Map<String, Object?>> toSnapshot() => _snapshotOf(_jobs);

  /// A snapshot of only the jobs that are not finished. These are the jobs worth restoring
  /// after a restart; completed/cancelled work already lives in the conversion history.
  List<Map<String, Object?>> pendingSnapshot() =>
      _snapshotOf(_jobs.where((job) => !job.status.isTerminal));

  static List<Map<String, Object?>> _snapshotOf(Iterable<ConversionJob> jobs) =>
      jobs
          .map(
            (job) => <String, Object?>{
              'id': job.id,
              'request': job.request.toJson(),
              'status': job.status.name,
              'progress': job.progress,
              'attempt': job.attempt,
              'queuedAt': job.queuedAt.millisecondsSinceEpoch,
            },
          )
          .toList(growable: false);

  /// Rebuilds the queue from a previously saved [snapshot].
  ///
  /// Jobs that were mid-flight when the process died keep their active status here so that
  /// [recoverAfterRestart] can mark them failed — they are never shown as "still running".
  /// Entries that cannot be decoded are skipped rather than discarding the whole batch.
  int restore(List<Map<String, Object?>> snapshot) {
    var restored = 0;
    for (final map in snapshot) {
      final requestJson = map['request'];
      if (requestJson is! Map) {
        continue;
      }
      try {
        final request = ConversionRequest.fromJson(
          requestJson.cast<String, Object?>(),
        );
        _jobs.add(
          ConversionJob(
            id:
                map['id'] as String? ??
                'restored_${restored}_${DateTime.now().microsecondsSinceEpoch}',
            request: request,
            status: _statusFromName(map['status'] as String?),
            progress: (map['progress'] as num?)?.toDouble() ?? 0,
            attempt: (map['attempt'] as num?)?.toInt() ?? 0,
            queuedAt: _dateTimeFromMillis(map['queuedAt']),
          ),
        );
        restored++;
      } catch (_) {
        // Skip an entry we cannot understand; keep the rest of the batch.
      }
    }
    return restored;
  }

  static JobStatus _statusFromName(String? name) => JobStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => JobStatus.queued,
  );

  static DateTime _dateTimeFromMillis(Object? value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : DateTime.now();

  QueueStats get stats {
    var queued = 0;
    var active = 0;
    var completed = 0;
    var failed = 0;
    var cancelled = 0;
    var skipped = 0;
    var progressSum = 0.0;
    for (final job in _jobs) {
      switch (job.status) {
        case JobStatus.queued:
          queued++;
        case JobStatus.preparing:
        case JobStatus.processing:
        case JobStatus.validating:
          active++;
          progressSum += job.progress;
        case JobStatus.completed:
          completed++;
          progressSum += 1;
        case JobStatus.failed:
          failed++;
        case JobStatus.cancelled:
          cancelled++;
        case JobStatus.skipped:
          skipped++;
      }
    }
    final total = _jobs.length;
    return QueueStats(
      total: total,
      queued: queued,
      active: active,
      completed: completed,
      failed: failed,
      cancelled: cancelled,
      skipped: skipped,
      overallProgress: total == 0
          ? 0
          : (progressSum / total).clamp(0, 1).toDouble(),
    );
  }

  static bool _canTransition(JobStatus from, JobStatus to) {
    if (to.isTerminal) {
      return true;
    }
    return switch (from) {
      JobStatus.queued => to == JobStatus.preparing,
      JobStatus.preparing =>
        to == JobStatus.processing || to == JobStatus.validating,
      JobStatus.processing => to == JobStatus.validating,
      JobStatus.validating => false,
      _ => false,
    };
  }
}
