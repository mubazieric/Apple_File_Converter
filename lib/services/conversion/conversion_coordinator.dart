import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/history_store.dart';
import '../../data/queue_store.dart';
import '../../domain/conversion/conversion_error.dart';
import '../../domain/conversion/conversion_request.dart';
import '../../domain/history/conversion_record.dart';
import '../../domain/queue/conversion_job.dart';
import '../../domain/queue/conversion_queue.dart';
import '../../domain/queue/job_status.dart';
import '../../domain/settings/app_settings.dart';
import '../export/output_exporter.dart';
import 'conversion_engine.dart';
import 'image_conversion_engine.dart';
import 'video_conversion_engine.dart';

/// Drives the conversion queue: starts engines, forwards progress, persists history and hands
/// finished files to the [OutputExporter].
///
/// This is the only object that both owns mutable batch state and performs I/O, so the rest of
/// the app (and the tests) can talk to a single, well-defined surface.
class ConversionCoordinator extends ChangeNotifier {
  ConversionCoordinator({
    required this._imageEngine,
    required this._videoEngine,
    required this._historyStore,
    required this._exportDestination,
    required this._exporter,
    this._customExportDirectory,
    this._queueStore,
    int concurrency = 2,
  }) : _queue = ConversionQueue(maxConcurrentJobs: concurrency.clamp(1, 8));

  final ImageConversionEngine _imageEngine;
  final VideoConversionEngine _videoEngine;
  final HistoryStore _historyStore;
  final OutputExporter _exporter;
  final QueueStore? _queueStore;

  ExportDestination _exportDestination;
  String? _customExportDirectory;

  final ConversionQueue _queue;
  final Map<String, CancellationToken> _tokens = <String, CancellationToken>{};

  final StreamController<ConversionJob> _events =
      StreamController<ConversionJob>.broadcast();

  bool _scheduling = false;
  bool _disposed = false;
  bool _savingQueue = false;
  bool _saveQueueAgain = false;
  int _sequence = 0;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Emits a job each time it reaches a terminal state (for result sheets / snackbars).
  Stream<ConversionJob> get events => _events.stream;

  QueueStats get stats => _queue.stats;
  List<ConversionJob> get jobs => _queue.jobs;
  int get concurrency => _queue.maxConcurrentJobs;
  bool get isIdle => _queue.isIdle;

  ConversionJob? job(String id) => _queue.jobById(id);

  void setConcurrency(int value) {
    final clamped = value.clamp(1, 8);
    if (clamped == _queue.maxConcurrentJobs) {
      return;
    }
    _queue.maxConcurrentJobs = clamped;
    _notify(force: true);
    unawaited(_schedule());
  }

  void updateExportDestination({
    required ExportDestination destination,
    String? customDirectory,
  }) {
    _exportDestination = destination;
    _customExportDirectory = customDirectory;
  }

  /// Adds requests to the queue and starts processing. Returns how many were added.
  int enqueue(Iterable<ConversionRequest> requests) {
    final jobs = <ConversionJob>[];
    for (final request in requests) {
      jobs.add(
        ConversionJob(
          id: 'job_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}',
          request: request,
        ),
      );
    }
    if (jobs.isEmpty) {
      return 0;
    }
    final count = _queue.enqueue(jobs);
    _notify(force: true);
    unawaited(_saveQueue());
    unawaited(_schedule());
    return count;
  }

  bool cancel(String id) {
    final accepted = _queue.cancel(id);
    if (accepted) {
      _tokens[id]?.cancel();
    }
    _notify(force: true);
    unawaited(_saveQueue());
    return accepted;
  }

  int cancelAll() {
    for (final token in _tokens.values) {
      token.cancel();
    }
    final count = _queue.cancelAll();
    _notify(force: true);
    unawaited(_saveQueue());
    return count;
  }

  bool retry(String id) {
    final accepted = _queue.retry(id);
    if (accepted) {
      _notify(force: true);
      unawaited(_saveQueue());
      unawaited(_schedule());
    }
    return accepted;
  }

  int retryAllFailed() {
    final count = _queue.retryAllFailed();
    if (count > 0) {
      _notify(force: true);
      unawaited(_saveQueue());
      unawaited(_schedule());
    }
    return count;
  }

  void clearFinished() {
    _queue.clearFinished();
    _notify(force: true);
    unawaited(_saveQueue());
  }

  /// Marks jobs that were running when the app last closed as failed (never pretends they are
  /// still going). Called once at startup.
  int recoverAfterRestart() {
    final count = _queue.recoverAfterRestart();
    if (count > 0) {
      _notify(force: true);
    }
    return count;
  }

  /// Loads a saved queue (if there is one) and marks jobs that were running when the app closed
  /// as failed, so an interrupted batch is visible and can be retried. Call once at startup.
  ///
  /// Returns how many jobs were restored.
  Future<int> restoreQueue() async {
    final store = _queueStore;
    if (store == null) {
      return 0;
    }
    final snapshot = await store.load();
    if (snapshot.isEmpty) {
      return 0;
    }
    final restored = _queue.restore(snapshot);
    _queue.recoverAfterRestart();
    if (restored == 0) {
      return 0;
    }
    _notify(force: true);
    await _saveQueue();
    unawaited(_schedule());
    return restored;
  }

  Future<void> _saveQueue() async {
    final store = _queueStore;
    if (store == null) {
      return;
    }
    if (_savingQueue) {
      // A save is already in flight: make sure one more runs afterwards with the latest state
      // rather than interleaving two writes to the same file.
      _saveQueueAgain = true;
      return;
    }
    _savingQueue = true;
    try {
      do {
        _saveQueueAgain = false;
        await store.save(_queue.pendingSnapshot());
      } while (_saveQueueAgain);
    } finally {
      _savingQueue = false;
    }
  }

  Future<List<ConversionRecord>> history({int limit = 300}) =>
      _historyStore.load(limit: limit);

  Future<void> clearHistory() async {
    await _historyStore.clear();
    _notify(force: true);
  }

  Future<void> removeHistoryEntry(String id) async {
    await _historyStore.remove(id);
    _notify(force: true);
  }

  Future<void> _schedule() async {
    if (_scheduling || _disposed) {
      return;
    }
    _scheduling = true;
    try {
      while (!_disposed) {
        final next = _queue.nextRunnable();
        if (next == null) {
          break;
        }
        if (!_queue.start(next.id)) {
          break;
        }
        _notify(force: true);
        unawaited(_saveQueue());
        unawaited(_run(next.id));
        // Yield so the event loop can start the engine before we pick the next job.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _scheduling = false;
    }
  }

  Future<void> _run(String jobId) async {
    final job = _queue.jobById(jobId);
    if (job == null) {
      return;
    }
    final token = CancellationToken();
    _tokens[jobId] = token;

    void onProgress(double progress, {String? message}) {
      if (_queue.updateProgress(jobId, progress, message: message)) {
        _notify();
      }
    }

    try {
      _queue.advanceTo(jobId, JobStatus.processing);
      _notify(force: true);

      final request = job.request;
      final ConversionOutcome outcome;
      if (request is ImageConversionRequest) {
        outcome = await _imageEngine.convert(
          request,
          onProgress: onProgress,
          token: token,
        );
      } else if (request is VideoConversionRequest) {
        outcome = await _videoEngine.convert(
          request,
          onProgress: onProgress,
          token: token,
        );
      } else {
        outcome = const ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.unsupportedOperation,
            message: 'This item cannot be converted.',
            isRecoverable: false,
          ),
        );
      }

      switch (outcome) {
        case final ConversionSuccess success:
          await _finishSuccess(job, success, onProgress);
        case final ConversionFailure failure:
          if (failure.error.code == ConversionErrorCode.cancelled) {
            _queue.cancel(jobId);
          } else {
            _queue.fail(jobId, failure.error);
          }
          await _persist(job);
      }
    } catch (error) {
      _queue.fail(
        jobId,
        ConversionError(
          code: ConversionErrorCode.internal,
          message: 'Something went wrong during conversion.',
          detail: error.runtimeType.toString(),
        ),
      );
      await _persist(job);
    } finally {
      _tokens.remove(jobId);
      _notify(force: true);
      _events.add(job);
      unawaited(_saveQueue());
      unawaited(_schedule());
    }
  }

  Future<void> _finishSuccess(
    ConversionJob job,
    ConversionSuccess success,
    void Function(double, {String? message}) onProgress,
  ) async {
    var finalPath = success.outputPath;
    var savedToPhotos = false;
    String? exportMessage;

    if (finalPath.isNotEmpty) {
      onProgress(0.95, message: 'Saving');
      final exported = await _exporter.export(
        filePath: finalPath,
        kind: job.request.source.kind,
        destination: _exportDestination,
        customDirectory: _customExportDirectory,
      );
      finalPath = exported.path;
      savedToPhotos = exported.savedToPhotos;
      exportMessage = exported.photoLibraryError;
    }

    _queue.complete(
      job.id,
      ConversionSuccess(
        outputPath: finalPath,
        outputBytes: success.outputBytes,
        sourceBytes: success.sourceBytes,
        width: success.width,
        height: success.height,
        duration: success.duration,
        videoCodec: success.videoCodec,
        audioCodec: success.audioCodec,
        wasRemux: success.wasRemux,
      ),
    );
    if (exportMessage != null) {
      job.message = exportMessage;
    }

    await _persist(job, speciallySucceeded: true, savedToPhotos: savedToPhotos);
  }

  Future<void> _persist(
    ConversionJob job, {
    bool speciallySucceeded = false,
    bool savedToPhotos = false,
  }) async {
    try {
      final success = speciallySucceeded && job.status == JobStatus.completed;
      final record = ConversionRecord(
        id: job.id,
        displayName: job.displayName,
        kind: job.request.source.kind,
        outputExtension: job.request.outputExtension,
        finishedAt: job.finishedAt ?? DateTime.now(),
        sourcePath: job.request.source.path,
        outputPath: job.outputPath,
        sourceBytes: job.sourceBytes ?? job.request.source.sizeBytes,
        outputBytes: job.outputBytes,
        wasRemux: job.wasRemux,
        success: success,
        errorMessage: job.error?.message ?? (success ? null : job.message),
        exportedToGallery: savedToPhotos,
      );
      await _historyStore.add(record);
    } catch (_) {
      // History is a convenience; never fail a successful conversion because of it.
    }
  }

  void _notify({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastNotify).inMilliseconds < 80) {
      return;
    }
    _lastNotify = now;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    unawaited(_events.close());
    super.dispose();
  }
}
