import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/media/media_item.dart';
import '../../services/ads/ad_service.dart';
import '../../services/conversion/conversion_coordinator.dart';
import '../theme/app_theme.dart';
import '../utils/import_files.dart';
import '../utils/ui_actions.dart';
import '../widgets/ad_slot.dart';
import '../widgets/common.dart';
import 'conversion_history_screen.dart';
import 'conversion_queue_screen.dart';
import 'convert_flow.dart';
import 'convert_source_picker.dart';

/// The Convert tab: pick a source (gallery or files) and enter the matching studio.
class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key});

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  bool _picking = false;

  Future<void> _fromGallery() async {
    setState(() => _picking = true);
    try {
      final items = await Navigator.of(context).push<List<MediaItem>>(
        MaterialPageRoute<List<MediaItem>>(
          builder: (context) => const ConvertSourcePicker(),
        ),
      );
      if (items == null || items.isEmpty) {
        return;
      }
      if (mounted) {
        await startConversionFlow(context, items);
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _fromFiles() async {
    setState(() => _picking = true);
    try {
      final items = await pickMediaFiles();
      if (items.isEmpty) {
        if (mounted) {
          showMessage(
            context,
            'No convertible files were chosen.',
            error: true,
          );
        }
        return;
      }
      if (mounted) {
        await startConversionFlow(context, items);
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<ConversionCoordinator>();
    final stats = coordinator.stats;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[
            const SectionHeader(
              title: 'Convert',
              subtitle: 'Photos and videos · batches · on this device',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  AppCard(
                    onTap: _picking ? null : _fromGallery,
                    child: Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: context.colors.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: AppRadius.mediumAll,
                          ),
                          child: Icon(
                            Icons.photo_library_outlined,
                            color: context.colors.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'From my gallery',
                                style: context.text.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pick photos and videos already on this phone',
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    onTap: _picking ? null : _fromFiles,
                    child: Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: context.colors.secondary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: AppRadius.mediumAll,
                          ),
                          child: Icon(
                            Icons.folder_open_outlined,
                            color: context.colors.secondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Pick files',
                                style: context.text.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'HEIC, HEIF, JPG, PNG, WebP, GIF, MP4, MOV, '
                                'MKV, WebM, AVI…',
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader(
              title: 'Your queue',
              subtitle: 'Batches run here, one file at a time',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AppCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const ConversionQueueScreen(),
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    KeyValueRow(
                      label: 'Waiting / running',
                      value: '${stats.queued + stats.active} of ${stats.total}',
                    ),
                    KeyValueRow(label: 'Finished', value: '${stats.completed}'),
                    KeyValueRow(
                      label: 'Failed',
                      value: '${stats.failed}',
                      valueColor: stats.failed > 0
                          ? context.colors.error
                          : null,
                    ),
                    if (stats.total > 0) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: AppRadius.pillAll,
                        child: LinearProgressIndicator(
                          value: stats.overallProgress,
                          minHeight: 6,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                const ConversionHistoryScreen(),
                          ),
                        ),
                        child: const Text('History'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: InfoBanner(
                icon: Icons.lock_outline,
                message:
                    'Everything is processed on this device. Your media is never '
                    'uploaded.',
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AdBannerSlot(placement: AdPlacement.homeBanner),
            ),
          ],
        ),
      ),
    );
  }
}
