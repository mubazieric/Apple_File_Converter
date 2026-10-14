import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/conversion/metadata_policy.dart';
import '../../domain/conversion/presets.dart';
import '../../domain/conversion/video_spec.dart';
import '../../domain/media/image_format.dart';
import '../../domain/media/video_format.dart';
import '../../domain/settings/app_settings.dart';
import '../../services/ads/ad_service.dart';
import '../../services/platform/platform_info.dart';
import '../../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'storage_screen.dart';

/// All application preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AdConsentSnapshot _consent = AdConsentSnapshot.unavailable;
  late final TextEditingController _namingController = TextEditingController(
    text: context.read<SettingsController>().settings.namingTemplate,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConsent());
  }

  @override
  void dispose() {
    _namingController.dispose();
    super.dispose();
  }

  Future<void> _loadConsent() async {
    final snapshot = await context.read<AdService>().consentSnapshot();
    if (mounted) {
      setState(() => _consent = snapshot);
    }
  }

  Future<void> _chooseCustomFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null || path.isEmpty || !mounted) {
      return;
    }
    await context.read<SettingsController>().setExportDestination(
      ExportDestination.customFolder,
      customPath: path,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();
    final settings = settingsController.settings;
    final ads = context.read<AdService>();
    final targets = ImageFormat.encodableTargets(PlatformInfo.kind);
    final containers = VideoContainer.encodableTargets(PlatformInfo.kind);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[
            const SectionHeader(
              title: 'Settings',
              subtitle: 'Defaults apply to new conversions',
            ),
            _Group(
              title: 'Appearance',
              children: <Widget>[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  title: const Text('Theme'),
                  subtitle: const Text('Follow the system, or pick one'),
                  trailing: SegmentedButton<ThemePreference>(
                    segments: const <ButtonSegment<ThemePreference>>[
                      ButtonSegment<ThemePreference>(
                        value: ThemePreference.system,
                        label: Text('Auto'),
                        icon: Icon(Icons.brightness_auto),
                      ),
                      ButtonSegment<ThemePreference>(
                        value: ThemePreference.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode),
                      ),
                      ButtonSegment<ThemePreference>(
                        value: ThemePreference.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode),
                      ),
                    ],
                    selected: <ThemePreference>{settings.theme},
                    onSelectionChanged: (selection) =>
                        settingsController.setTheme(selection.first),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  title: const Text('Gallery layout'),
                  trailing: SegmentedButton<GalleryLayout>(
                    segments: const <ButtonSegment<GalleryLayout>>[
                      ButtonSegment<GalleryLayout>(
                        value: GalleryLayout.grid,
                        label: Text('Grid'),
                        icon: Icon(Icons.grid_view),
                      ),
                      ButtonSegment<GalleryLayout>(
                        value: GalleryLayout.list,
                        label: Text('List'),
                        icon: Icon(Icons.view_list),
                      ),
                    ],
                    selected: <GalleryLayout>{settings.galleryLayout},
                    onSelectionChanged: (selection) =>
                        settingsController.setGalleryLayout(selection.first),
                  ),
                ),
                SliderRow(
                  label: 'Grid columns',
                  value: settings.galleryGridColumns.toDouble(),
                  min: 2,
                  max: 6,
                  divisions: 4,
                  valueLabel: (value) => '${value.round()}',
                  onChanged: (value) =>
                      settingsController.setGalleryGridColumns(value.round()),
                ),
              ],
            ),
            _Group(
              title: 'Photo conversions',
              children: <Widget>[
                if (targets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final format in targets)
                          ChoiceChip(
                            label: Text(format.label),
                            selected: settings.defaultImageFormat == format,
                            onSelected: (_) => settingsController
                                .setDefaultImageFormat(format),
                          ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: InfoBanner(
                      message:
                          'No image output formats are available on this '
                          'platform.',
                    ),
                  ),
                SliderRow(
                  label: 'Default photo quality',
                  value: settings.defaultImageQuality.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 18,
                  valueLabel: (value) => '${value.round()}',
                  onChanged: (value) =>
                      settingsController.setDefaultImageQuality(value.round()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: ChoiceChips<ImagePreset>(
                    values: ImagePreset.values
                        .where((preset) => preset != ImagePreset.custom)
                        .toList(growable: false),
                    selected: settings.defaultImagePreset,
                    labelOf: (preset) => preset.label,
                    onSelected: settingsController.setDefaultImagePreset,
                  ),
                ),
              ],
            ),
            _Group(
              title: 'Video conversions',
              children: <Widget>[
                if (containers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final container in containers)
                          ChoiceChip(
                            label: Text(container.label),
                            selected:
                                settings.defaultVideoContainer == container,
                            onSelected: (_) => settingsController
                                .setDefaultVideoContainer(container),
                          ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: InfoBanner(
                      message:
                          'No video output containers are available on this '
                          'platform.',
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: ChoiceChips<VideoPreset>(
                    values: VideoPreset.values
                        .where((preset) => preset != VideoPreset.custom)
                        .toList(growable: false),
                    selected: settings.defaultVideoPreset,
                    labelOf: (preset) => preset.label,
                    onSelected: settingsController.setDefaultVideoPreset,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: ChoiceChips<VideoQuality>(
                    values: VideoQuality.values,
                    selected: settings.defaultVideoQuality,
                    labelOf: (quality) => switch (quality) {
                      VideoQuality.smaller => 'Smaller',
                      VideoQuality.balanced => 'Balanced',
                      VideoQuality.high => 'High',
                      VideoQuality.maximum => 'Maximum',
                    },
                    onSelected: settingsController.setDefaultVideoQuality,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: ChoiceChips<ResolutionPreset>(
                    values: ResolutionPreset.values,
                    selected: settings.defaultResolution,
                    labelOf: (resolution) => resolution.label,
                    onSelected: settingsController.setDefaultResolution,
                  ),
                ),
              ],
            ),
            _Group(
              title: 'Metadata & naming',
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    children: <Widget>[
                      for (final policy in MetadataPolicy.values)
                        ChoiceChip(
                          label: Text(_metadataLabel(policy)),
                          selected: settings.metadataPolicy == policy,
                          onSelected: (_) =>
                              settingsController.setMetadataPolicy(policy),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: TextField(
                    controller: _namingController,
                    decoration: const InputDecoration(
                      labelText: 'Output file name template',
                      helperText: 'Placeholders: {name} {date} {time} {format}',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: settingsController.setNamingTemplate,
                  ),
                ),
              ],
            ),
            _Group(
              title: 'Where results are saved',
              children: <Widget>[
                RadioGroup<ExportDestination>(
                  groupValue: settings.exportDestination,
                  onChanged: (value) async {
                    if (value == null) {
                      return;
                    }
                    if (value == ExportDestination.customFolder) {
                      await _chooseCustomFolder();
                    } else {
                      await settingsController.setExportDestination(value);
                    }
                  },
                  child: Column(
                    children: <Widget>[
                      const RadioListTile<ExportDestination>(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        title: Text('Photo library'),
                        subtitle: Text(
                          'Photos / MediaStore — a copy is also kept in the app '
                          'exports folder for sharing and opening.',
                        ),
                        value: ExportDestination.gallery,
                      ),
                      const RadioListTile<ExportDestination>(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        title: Text('App exports folder'),
                        value: ExportDestination.appFolder,
                      ),
                      RadioListTile<ExportDestination>(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        title: const Text('A folder I choose'),
                        subtitle: settings.customExportPath == null
                            ? null
                            : Text(settings.customExportPath!),
                        value: ExportDestination.customFolder,
                      ),
                      if (settings.exportDestination ==
                          ExportDestination.customFolder)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.lg,
                          ),
                          child: OutlinedButton.icon(
                            onPressed: _chooseCustomFolder,
                            icon: const Icon(Icons.folder_open_outlined),
                            label: const Text('Choose folder'),
                          ),
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: InfoBanner(
                    message:
                        'Converting to “Photo library” needs permission to '
                        'add photos/videos, which is requested when you first '
                        'save there.',
                  ),
                ),
              ],
            ),
            _Group(
              title: 'Batch processing',
              children: <Widget>[
                SliderRow(
                  label: 'Parallel conversions',
                  value:
                      (settings.batchConcurrency ??
                              settingsController.suggestedConcurrency)
                          .toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  valueLabel: settings.batchConcurrency == null
                      ? (_) => 'Auto'
                      : (value) => '${value.round()}',
                  onChanged: (value) =>
                      settingsController.setBatchConcurrency(value.round()),
                ),
                SwitchRow(
                  title: 'Confirm before deleting',
                  subtitle: 'Ask before removing items from the gallery',
                  value: settings.confirmBeforeDelete,
                  onChanged: settingsController.setConfirmBeforeDelete,
                ),
              ],
            ),
            _Group(
              title: 'Storage',
              children: <Widget>[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('Storage dashboard'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const StorageScreen(),
                    ),
                  ),
                ),
              ],
            ),
            _Group(
              title: 'Advertising',
              children: <Widget>[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  leading: const Icon(Icons.ads_click_outlined),
                  title: const Text('Ad privacy'),
                  subtitle: Text(
                    ads.isEnabled
                        ? '${ads.providerName} · consent: ${_consentLabel(_consent.status)}'
                        : 'Ads are not active in this build.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: ads.isEnabled
                      ? () async {
                          await ads.requestConsentUpdate();
                          await ads.showConsentFormIfRequired();
                          await _loadConsent();
                          if (mounted) {
                            await settingsController.markAdsConsentDecided();
                          }
                        }
                      : null,
                ),
              ],
            ),
            _Group(
              title: 'About',
              children: <Widget>[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About Apple File Converter'),
                  subtitle: const Text(
                    'Version, credits and open-source licences',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const AboutScreen(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Open-source licences'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Apple File Converter',
                  ),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  leading: Icon(Icons.language_outlined),
                  title: Text('Language'),
                  subtitle: Text(
                    'English (default) — the app is localisation-ready',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _metadataLabel(MetadataPolicy policy) => switch (policy) {
    MetadataPolicy.preserve => 'Keep all',
    MetadataPolicy.stripLocation => 'Remove location',
    MetadataPolicy.stripAll => 'Remove all',
  };

  static String _consentLabel(ConsentStatusLevel status) => switch (status) {
    ConsentStatusLevel.unknown => 'not gathered yet',
    ConsentStatusLevel.notRequired => 'not required in your region',
    ConsentStatusLevel.required => 'decision requested',
    ConsentStatusLevel.obtained => 'decision recorded',
  };
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                title,
                style: context.text.titleSmall?.copyWith(
                  color: context.colors.primary,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
