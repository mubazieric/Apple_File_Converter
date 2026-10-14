import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/conversion/conversion_coordinator.dart';
import '../../state/shell_controller.dart';
import '../theme/app_theme.dart';
import 'conversion_queue_screen.dart';
import 'convert_screen.dart';
import 'gallery_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart';

/// The persistent scaffold: five tabs plus a slim conversion progress bar that stays visible
/// while a batch runs, wherever the user is.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    return Scaffold(
      body: IndexedStack(
        index: shell.index,
        children: const <Widget>[
          HomeScreen(),
          GalleryScreen(),
          ConvertScreen(),
          ToolsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _ConversionMiniBar(),
          NavigationBar(
            selectedIndex: shell.index,
            onDestinationSelected: shell.selectIndex,
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: 'Gallery',
              ),
              NavigationDestination(
                icon: Icon(Icons.swap_horiz_outlined),
                selectedIcon: Icon(Icons.swap_horiz),
                label: 'Convert',
              ),
              NavigationDestination(
                icon: Icon(Icons.build_outlined),
                selectedIcon: Icon(Icons.build),
                label: 'Tools',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversionMiniBar extends StatelessWidget {
  const _ConversionMiniBar();

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<ConversionCoordinator>();
    final stats = coordinator.stats;
    if (!stats.isRunning && !stats.hasFailures) {
      return const SizedBox.shrink();
    }

    final scheme = context.colors;
    final label = stats.isRunning
        ? 'Converting ${stats.finished + 1} of ${stats.total}'
        : '${stats.failed} conversion${stats.failed == 1 ? '' : 's'} failed';

    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const ConversionQueueScreen(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    stats.isRunning ? Icons.sync : Icons.error_outline,
                    size: 18,
                    color: stats.isRunning ? scheme.primary : scheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(label, style: context.text.bodySmall)),
                  Text(
                    '${(stats.overallProgress * 100).round()}%',
                    style: context.text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: AppRadius.pillAll,
                child: LinearProgressIndicator(
                  value: stats.total == 0 ? 0 : stats.overallProgress,
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
