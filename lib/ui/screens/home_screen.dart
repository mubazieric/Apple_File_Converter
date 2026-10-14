import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../domain/history/conversion_record.dart';
import '../../services/ads/ad_service.dart';
import '../../services/conversion/conversion_coordinator.dart';
import '../../services/storage/storage_service.dart';
import '../../state/gallery_controller.dart';
import '../../state/shell_controller.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/ad_slot.dart';
import '../widgets/common.dart';
import 'conversion_history_screen.dart';
import 'storage_screen.dart';

/// Landing tab: brand header, quick actions, recent activity and a storage summary.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ConversionRecord> _recent = const <ConversionRecord>[];
  StorageReport? _storage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final coordinator = context.read<ConversionCoordinator>();
    final storage = context.read<StorageService>();
    try {
      final recent = await coordinator.history(limit: 3);
      if (mounted) {
        setState(() => _recent = recent);
      }
    } catch (_) {
      // History is best-effort.
    }
    try {
      final report = await storage.report();
      if (mounted) {
        setState(() => _storage = report);
      }
    } catch (_) {
      // Storage info is best-effort.
    }
  }

  void _openTab(AppTab tab) => context.read<ShellController>().select(tab);

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (context) => screen));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final gallery = context.watch<GalleryController>();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[
            const _Hero(),
            const SectionHeader(
              title: 'Quick actions',
              subtitle: 'Everything runs on this device',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.5,
                children: <Widget>[
                  _ActionTile(
                    icon: Icons.image_outlined,
                    title: 'Convert photos',
                    subtitle: 'HEIC, JPEG, PNG, WebP…',
                    onTap: () => _openTab(AppTab.convert),
                  ),
                  _ActionTile(
                    icon: Icons.movie_outlined,
                    title: 'Convert videos',
                    subtitle: 'MP4, MOV, MKV, WebM…',
                    onTap: () => _openTab(AppTab.convert),
                  ),
                  _ActionTile(
                    icon: Icons.photo_library_outlined,
                    title: 'Browse gallery',
                    subtitle: gallery.canBrowse
                        ? '${gallery.allItems.length} loaded'
                        : 'Grant access to begin',
                    onTap: () => _openTab(AppTab.gallery),
                  ),
                  _ActionTile(
                    icon: Icons.build_outlined,
                    title: 'Tools',
                    subtitle: 'Compress, trim, watermark…',
                    onTap: () => _openTab(AppTab.tools),
                  ),
                ],
              ),
            ),
            SectionHeader(
              title: 'Recent conversions',
              trailing: TextButton(
                onPressed: () => _push(const ConversionHistoryScreen()),
                child: const Text('See all'),
              ),
            ),
            _RecentSection(records: _recent),
            SectionHeader(
              title: 'Storage',
              trailing: TextButton(
                onPressed: () => _push(const StorageScreen()),
                child: const Text('Manage'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _StorageSummary(report: _storage),
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

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: AppRadius.largeAll,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary,
            Color.lerp(scheme.primary, AppColors.violet, 0.75) ??
                scheme.primary,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.change_circle_outlined, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Apple File Converter',
                style: context.text.titleLarge?.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Convert, compress and prepare your photos and videos — privately, '
            'on your device.',
            style: context.text.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Developed by Iwat Digital',
            style: context.text.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Icon(icon, color: context.colors.primary),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: context.text.titleSmall),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.records});

  final List<ConversionRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: AppCard(
          child: Row(
            children: <Widget>[
              Icon(Icons.history, color: context.colors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'No conversions yet. Pick something from the Convert tab to '
                  'get started.',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final record in records)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: record.outputPath == null
                  ? null
                  : () => openPath(context, record.outputPath!),
              child: Row(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          record.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          record.success
                              ? '${record.outputExtension.toUpperCase()} · '
                                    '${ByteFormat.binary(record.outputBytes)}'
                              : record.errorMessage ?? 'Failed',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: record.success
                                ? context.colors.onSurfaceVariant
                                : context.colors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.report});

  final StorageReport? report;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    if (report == null) {
      return const ShimmerBox(height: 84, radius: AppRadius.largeAll);
    }
    return AppCard(
      child: Column(
        children: <Widget>[
          if (report.hasDeviceInfo)
            KeyValueRow(
              label: 'Device free space',
              value: ByteFormat.binary(report.deviceFreeBytes),
            ),
          KeyValueRow(
            label: 'App exports',
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
    );
  }
}
