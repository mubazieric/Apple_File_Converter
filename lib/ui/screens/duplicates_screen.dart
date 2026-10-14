import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../services/storage/duplicate_detection.dart';
import '../../services/storage/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/common.dart';

/// Finds exact duplicate files in the app's export folder and lets the user clear them.
class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  List<DuplicateGroup> _groups = const <DuplicateGroup>[];
  final Set<String> _marked = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _toggle(String path, bool value) {
    setState(() {
      if (value) {
        _marked.add(path);
      } else {
        _marked.remove(path);
      }
    });
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    final storage = context.read<StorageService>();
    final directory = await storage.exportDirectory();
    final groups = await DuplicateDetector.scan(directory);
    if (mounted) {
      setState(() {
        _groups = groups;
        _loading = false;
        _marked
          ..clear()
          ..addAll(_defaultMarks());
      });
    }
  }

  List<String> _defaultMarks() {
    final marked = <String>[];
    for (final group in _groups) {
      // Keep the first file by name; mark the rest for deletion.
      for (final file in group.files.skip(1)) {
        marked.add(file.path);
      }
    }
    return marked;
  }

  Future<void> _deleteMarked() async {
    final toDelete = _marked.toList();
    if (toDelete.isEmpty) {
      showMessage(context, 'Select at least one duplicate to delete.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${toDelete.length} duplicate(s)?'),
        content: const Text(
          'Only the marked copies are removed. One copy of each file is kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    var deleted = 0;
    for (final path in toDelete) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
          deleted++;
        }
      } catch (_) {
        // Skip files that fail; report the count that succeeded.
      }
    }
    if (mounted) {
      showMessage(context, 'Deleted $deleted duplicate(s).');
    }
    await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final reclaimable = _groups.fold<int>(
      0,
      (sum, group) => sum + group.reclaimableBytes,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Find duplicates')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
          ? const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'No duplicates found',
              message:
                  'We compared files in the app\'s export folder by content. '
                  'Nothing is identical there right now.',
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: InfoBanner(
                    icon: Icons.info_outline,
                    message:
                        '${_groups.length} group(s) of identical files · '
                        '${ByteFormat.binary(reclaimable)} could be reclaimed. '
                        'Scanning covers the app\'s export folder only.',
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    itemCount: _groups.length,
                    itemBuilder: (context, index) => _GroupCard(
                      group: _groups[index],
                      marked: _marked,
                      onToggle: _toggle,
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: FilledButton.icon(
                      onPressed: _marked.isEmpty ? null : _deleteMarked,
                      icon: const Icon(Icons.delete_outline),
                      label: Text('Delete ${_marked.length} marked'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.marked,
    required this.onToggle,
  });

  final DuplicateGroup group;
  final Set<String> marked;
  final void Function(String path, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.content_copy,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${group.files.length} identical files · '
                    '${ByteFormat.binary(group.files.first.sizeBytes)} each',
                    style: context.text.labelMedium,
                  ),
                ),
                Text(
                  ByteFormat.binary(group.reclaimableBytes),
                  style: context.text.labelMedium?.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final file in group.files)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: marked.contains(file.path),
                onChanged: (value) => onToggle(file.path, value ?? false),
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
