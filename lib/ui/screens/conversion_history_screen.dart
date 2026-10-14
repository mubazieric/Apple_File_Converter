import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../domain/history/conversion_record.dart';
import '../../services/conversion/conversion_coordinator.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/common.dart';

/// The full conversion history, newest first.
class ConversionHistoryScreen extends StatefulWidget {
  const ConversionHistoryScreen({super.key});

  @override
  State<ConversionHistoryScreen> createState() =>
      _ConversionHistoryScreenState();
}

class _ConversionHistoryScreenState extends State<ConversionHistoryScreen> {
  List<ConversionRecord> _records = const <ConversionRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await context.read<ConversionCoordinator>().history();
      if (mounted) {
        setState(() {
          _records = records;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear conversion history?'),
        content: const Text(
          'This removes the list of past conversions. Your converted files are '
          'not deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<ConversionCoordinator>().clearHistory();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversion history'),
        actions: <Widget>[
          if (_records.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              onPressed: _confirmClear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'No conversions yet',
              message: 'Finished conversions will be listed here.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _records.length,
              itemBuilder: (context, index) =>
                  _HistoryTile(record: _records[index], onChanged: _load),
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record, required this.onChanged});

  final ConversionRecord record;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final timestamp = DateFormat.yMMMd().add_Hm().format(record.finishedAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  record.success
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: record.success
                      ? AppColors.success
                      : context.colors.error,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    record.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                ),
                if (record.exportedToGallery)
                  Tooltip(
                    message: 'A copy was saved to Photos',
                    child: Icon(
                      Icons.photo_library_outlined,
                      size: 18,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            KeyValueRow(
              label: record.success ? 'Output' : 'Error',
              value: record.success
                  ? record.outputExtension.toUpperCase()
                  : record.errorMessage ?? 'Failed',
              valueColor: record.success ? null : context.colors.error,
            ),
            if (record.success)
              KeyValueRow(
                label: 'Size',
                value:
                    '${ByteFormat.binary(record.outputBytes)}'
                    '${record.bytesSaved != null ? '  (${ByteFormat.difference(record.bytesSaved)})' : ''}',
              ),
            KeyValueRow(label: 'When', value: timestamp),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                if (record.success && record.outputPath != null)
                  TextButton.icon(
                    onPressed: () => openPath(context, record.outputPath!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open'),
                  ),
                if (record.success && record.outputPath != null)
                  TextButton.icon(
                    onPressed: () =>
                        sharePaths(context, <String>[record.outputPath!]),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove from history',
                  onPressed: () async {
                    await context
                        .read<ConversionCoordinator>()
                        .removeHistoryEntry(record.id);
                    await onChanged();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
