import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../domain/queue/conversion_job.dart';
import '../../domain/queue/job_status.dart';
import '../../services/conversion/conversion_coordinator.dart';
import '../../services/export/zip_exporter.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/common.dart';

/// Live view of the batch queue: overall progress, per-job status, cancel and retry.
class ConversionQueueScreen extends StatelessWidget {
  const ConversionQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<ConversionCoordinator>();
    final stats = coordinator.stats;
    final jobs = coordinator.jobs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch queue'),
        actions: <Widget>[
          if (stats.failed > 0)
            IconButton(
              tooltip: 'Retry all failed',
              onPressed: () {
                final count = coordinator.retryAllFailed();
                showMessage(context, 'Retrying $count job(s).');
              },
              icon: const Icon(Icons.refresh),
            ),
          if (stats.completed > 0)
            IconButton(
              tooltip: 'Share all as ZIP',
              onPressed: () => _shareAllAsZip(context),
              icon: const Icon(Icons.archive_outlined),
            ),
          if (stats.finished > 0)
            IconButton(
              tooltip: 'Clear finished',
              onPressed: coordinator.clearFinished,
              icon: const Icon(Icons.cleaning_services_outlined),
            ),
        ],
      ),
      body: stats.total == 0
          ? const EmptyState(
              icon: Icons.queue,
              title: 'The queue is empty',
              message:
                  'Start a conversion from the Convert tab, the gallery or Tools '
                  'and it will appear here.',
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                AppCard(
                  child: Column(
                    children: <Widget>[
                      KeyValueRow(label: 'Total', value: '${stats.total}'),
                      KeyValueRow(
                        label: 'Done',
                        value:
                            '${stats.completed} · ${stats.failed} failed · '
                            '${stats.cancelled} cancelled',
                        valueColor: stats.failed > 0
                            ? context.colors.error
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: AppRadius.pillAll,
                        child: LinearProgressIndicator(
                          value: stats.overallProgress,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${(stats.overallProgress * 100).round()}%',
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      if (stats.isRunning) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              final count = coordinator.cancelAll();
                              showMessage(
                                context,
                                count == 0
                                    ? 'Nothing left to cancel.'
                                    : 'Cancelled $count job(s).',
                              );
                            },
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('Cancel all'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final job in jobs) _JobTile(job: job),
              ],
            ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});

  final ConversionJob job;

  @override
  Widget build(BuildContext context) {
    final coordinator = context.read<ConversionCoordinator>();
    final status = job.status;
    final icon = switch (status) {
      JobStatus.completed => (Icons.check_circle_outline, AppColors.success),
      JobStatus.failed => (Icons.error_outline, context.colors.error),
      JobStatus.cancelled => (
        Icons.cancel_outlined,
        context.colors.onSurfaceVariant,
      ),
      JobStatus.skipped => (
        Icons.skip_next_outlined,
        context.colors.onSurfaceVariant,
      ),
      _ => (Icons.hourglass_top, context.colors.primary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon.$1, color: icon.$2),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    job.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                ),
                if (status.isActive)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    status.label,
                    style: context.text.labelMedium?.copyWith(color: icon.$2),
                  ),
              ],
            ),
            if (status.isActive) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: AppRadius.pillAll,
                child: LinearProgressIndicator(
                  value: job.progress.clamp(0.0, 1.0),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${(job.progress * 100).round()}% · attempt ${job.attempt}',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
            if (status == JobStatus.failed && job.error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                job.error!.message,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ],
            if (status == JobStatus.completed) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              KeyValueRow(
                label: 'Output',
                value:
                    '${ByteFormat.binary(job.outputBytes)}'
                    '${job.bytesSaved != null ? ' (${ByteFormat.difference(job.bytesSaved)})' : ''}',
              ),
              Row(
                children: <Widget>[
                  if (job.outputPath != null) ...<Widget>[
                    TextButton.icon(
                      onPressed: () => openPath(context, job.outputPath!),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open'),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          sharePaths(context, <String>[job.outputPath!]),
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Share'),
                    ),
                  ],
                ],
              ),
            ],
            if (status == JobStatus.failed || status == JobStatus.cancelled)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => coordinator.retry(job.id),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ),
            if (status.isActive)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => coordinator.cancel(job.id),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Cancel'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Zips every completed output in the queue and hands the archive to the system share sheet.
///
/// Only genuinely finished files with a local path are included; the archive is written beside
/// the first output so it lands in the same destination the user chose.
Future<void> _shareAllAsZip(BuildContext context) async {
  final coordinator = context.read<ConversionCoordinator>();
  final zipExporter = context.read<ZipExporter>();

  final paths = coordinator.jobs
      .where(
        (job) =>
            job.status == JobStatus.completed &&
            (job.outputPath?.isNotEmpty ?? false),
      )
      .map((job) => job.outputPath!)
      .toList(growable: false);

  if (paths.isEmpty) {
    showMessage(
      context,
      'There are no finished files to archive.',
      error: true,
    );
    return;
  }

  final now = DateTime.now();
  final stamp =
      '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)} '
      '${_twoDigits(now.hour)}${_twoDigits(now.minute)}';
  final outputPath = p.join(
    p.dirname(paths.first),
    'Apple File Converter $stamp.zip',
  );

  showMessage(context, 'Creating ZIP archive…');
  final result = await zipExporter.zipFiles(paths, outputPath: outputPath);
  if (!context.mounted) {
    return;
  }
  if (!result.isSuccess) {
    showMessage(
      context,
      result.error ?? 'The ZIP could not be created.',
      error: true,
    );
    return;
  }
  await sharePaths(context, <String>[
    result.outputPath!,
  ], subject: 'Converted files');
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
