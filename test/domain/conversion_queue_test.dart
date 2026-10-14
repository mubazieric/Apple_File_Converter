import 'package:apple_file_converter/domain/conversion/conversion_error.dart';
import 'package:apple_file_converter/domain/conversion/conversion_request.dart';
import 'package:apple_file_converter/domain/conversion/image_spec.dart';
import 'package:apple_file_converter/domain/media/media_item.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:apple_file_converter/domain/queue/conversion_job.dart';
import 'package:apple_file_converter/domain/queue/conversion_queue.dart';
import 'package:apple_file_converter/domain/queue/job_status.dart';
import 'package:flutter_test/flutter_test.dart';

ConversionJob _job(String id) => ConversionJob(
  id: id,
  request: ImageConversionRequest(
    source: MediaItem(id: 'src-$id', kind: MediaKind.image),
    spec: const ImageConversionSpec(),
  ),
);

ConversionSuccess _success(String path) =>
    ConversionSuccess(outputPath: path, outputBytes: 1000, sourceBytes: 4000);

void main() {
  group('ConversionQueue state machine', () {
    test('enqueue adds jobs and reports stats', () {
      final queue = ConversionQueue()
        ..enqueue(<ConversionJob>[_job('a'), _job('b')]);
      expect(queue.jobs.length, 2);
      expect(queue.stats.total, 2);
      expect(queue.stats.queued, 2);
      // Not idle: there are queued jobs waiting.
      expect(queue.stats.isIdle, isFalse);
    });

    test(
      'start moves a queued job to preparing and increments the attempt',
      () {
        final queue = ConversionQueue()..enqueue(<ConversionJob>[_job('a')]);
        expect(queue.start('a'), isTrue);
        final job = queue.jobById('a')!;
        expect(job.status, JobStatus.preparing);
        expect(job.attempt, 1);
      },
    );

    test('start rejects an unknown job', () {
      final queue = ConversionQueue();
      expect(queue.start('missing'), isFalse);
    });

    test('respects bounded concurrency when picking runnable jobs', () {
      final queue = ConversionQueue(maxConcurrentJobs: 1)
        ..enqueue(<ConversionJob>[_job('a'), _job('b')]);
      expect(queue.start('a'), isTrue);
      expect(queue.nextRunnable(), isNull);
      expect(queue.start('b'), isFalse);
    });

    test('allows only valid forward transitions', () {
      final queue = ConversionQueue()..enqueue(<ConversionJob>[_job('a')]);
      queue.start('a');
      expect(queue.advanceTo('a', JobStatus.validating), isTrue);
      // validating is terminal for transitions; nothing may follow it except terminal states.
      expect(queue.advanceTo('a', JobStatus.processing), isFalse);
    });

    test('complete sets progress to 1 and clears the error', () {
      final queue = ConversionQueue()..enqueue(<ConversionJob>[_job('a')]);
      queue.start('a');
      queue.advanceTo('a', JobStatus.processing);
      expect(queue.complete('a', _success('/out/a.jpg')), isTrue);
      final job = queue.jobById('a')!;
      expect(job.status, JobStatus.completed);
      expect(job.progress, 1);
      expect(job.outputPath, '/out/a.jpg');
      expect(job.bytesSaved, 3000);
    });

    test('fail records an error and can be retried', () {
      final queue = ConversionQueue()..enqueue(<ConversionJob>[_job('a')]);
      queue.start('a');
      expect(
        queue.fail(
          'a',
          const ConversionError(
            code: ConversionErrorCode.decodeFailed,
            message: 'nope',
          ),
        ),
        isTrue,
      );
      expect(queue.jobById('a')!.status, JobStatus.failed);
      expect(queue.jobById('a')!.canRetry, isTrue);
      expect(queue.retry('a'), isTrue);
      expect(queue.jobById('a')!.status, JobStatus.queued);
      expect(queue.jobById('a')!.progress, 0);
    });

    test('retry is rejected for jobs that are not failed or cancelled', () {
      final queue = ConversionQueue()..enqueue(<ConversionJob>[_job('a')]);
      expect(queue.retry('a'), isFalse);
    });

    test('cancelAll marks every unfinished job as cancelled', () {
      final queue = ConversionQueue()
        ..enqueue(<ConversionJob>[_job('a'), _job('b')]);
      expect(queue.cancelAll(), 2);
      expect(queue.stats.cancelled, 2);
      expect(queue.stats.isComplete, isTrue);
    });

    test('recoverAfterRestart fails jobs that were mid-flight', () {
      final queue = ConversionQueue()
        ..enqueue(<ConversionJob>[_job('a'), _job('b')]);
      queue.start('a');
      final recovered = queue.recoverAfterRestart();
      expect(recovered, 1);
      expect(queue.jobById('a')!.status, JobStatus.failed);
      expect(queue.jobById('b')!.status, JobStatus.queued);
    });

    test('stats.overallProgress averages completed and active work', () {
      final queue = ConversionQueue()
        ..enqueue(<ConversionJob>[_job('a'), _job('b')]);
      queue.start('a');
      queue.advanceTo('a', JobStatus.processing);
      queue.updateProgress('a', 0.5);
      expect(queue.stats.overallProgress, closeTo(0.25, 0.001));
    });

    test('clearFinished removes terminal jobs only', () {
      final queue = ConversionQueue()
        ..enqueue(<ConversionJob>[_job('a'), _job('b')]);
      queue.start('a');
      queue.complete('a', _success('/out/a.jpg'));
      expect(queue.clearFinished(), 1);
      expect(queue.jobs.length, 1);
      expect(queue.jobs.single.id, 'b');
    });

    test('snapshot contains no media bytes and preserves identity', () {
      final queue = ConversionQueue()..enqueue(<ConversionJob>[_job('a')]);
      final snapshot = queue.toSnapshot();
      expect(snapshot.single['id'], 'a');
      expect(snapshot.single['status'], 'queued');
      expect(snapshot.single.containsKey('bytes'), isFalse);
    });
  });
}
