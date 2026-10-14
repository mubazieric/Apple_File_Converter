import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../services/storage/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/common.dart';

/// Storage dashboard and cleanup.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  StorageReport? _report;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final report = await context.read<StorageService>().report();
      if (mounted) {
        setState(() => _report = report);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clean() async {
    setState(() => _busy = true);
    try {
      final freed = await context.read<StorageService>().cleanWorkFiles();
      if (!mounted) {
        return;
      }
      showMessage(
        context,
        freed > 0
            ? 'Freed ${ByteFormat.binary(freed)}.'
            : 'Nothing to clean up.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Device storage', style: context.text.titleSmall),
                      const SizedBox(height: AppSpacing.md),
                      if (report.hasDeviceInfo) ...<Widget>[
                        ClipRRect(
                          borderRadius: AppRadius.pillAll,
                          child: LinearProgressIndicator(
                            value: report.deviceUsedFraction,
                            minHeight: 10,
                            backgroundColor:
                                context.colors.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        KeyValueRow(
                          label: 'Used',
                          value: ByteFormat.binary(report.deviceUsedBytes),
                        ),
                        KeyValueRow(
                          label: 'Free',
                          value: ByteFormat.binary(report.deviceFreeBytes),
                        ),
                        KeyValueRow(
                          label: 'Total',
                          value: ByteFormat.binary(report.deviceTotalBytes),
                        ),
                      ] else
                        const InfoBanner(
                          message:
                              'This device does not report free space to the app. '
                              'Your system storage settings remain the source of truth.',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Managed by this app',
                        style: context.text.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      KeyValueRow(
                        label: 'Exports folder',
                        value:
                            '${ByteFormat.binary(report.exportBytes)} · '
                            '${report.exportFileCount} file(s)',
                      ),
                      KeyValueRow(
                        label: 'Temporary files',
                        value:
                            '${ByteFormat.binary(report.workBytes)} · '
                            '${report.workFileCount} file(s)',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const InfoBanner(
                  message:
                      'Cleaning temporary files only removes intermediate files the app '
                      'created while converting. Your originals and finished exports are '
                      'never touched.',
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _busy ? null : _clean,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Clean temporary files'),
                ),
              ],
            ),
    );
  }
}
