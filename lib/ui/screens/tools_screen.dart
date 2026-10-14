import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/conversion/metadata_policy.dart';
import '../../domain/conversion/presets.dart';
import '../../domain/conversion/video_spec.dart';
import '../../domain/media/media_item.dart';
import '../../state/conversion_controller.dart';
import '../../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/common.dart';
import 'conversion_history_screen.dart';
import 'convert_source_picker.dart';
import 'duplicates_screen.dart';
import 'image_studio_screen.dart';
import 'storage_screen.dart';
import 'video_studio_screen.dart';

enum _Tool {
  compressPhotos(
    icon: Icons.compress,
    title: 'Compress photos',
    subtitle: 'Smaller files, fewer megapixels',
  ),
  compressVideos(
    icon: Icons.video_settings_outlined,
    title: 'Compress videos',
    subtitle: 'Smaller files with H.264',
  ),
  rotateFlip(
    icon: Icons.rotate_90_degrees_cw_outlined,
    title: 'Rotate & flip',
    subtitle: 'Fix orientation without losing quality',
  ),
  stripMetadata(
    icon: Icons.hide_source_outlined,
    title: 'Remove metadata',
    subtitle: 'Strip EXIF, GPS and dates',
  ),
  watermark(
    icon: Icons.text_fields,
    title: 'Add watermark',
    subtitle: 'Text on every image',
  ),
  thumbnails(
    icon: Icons.grid_view_outlined,
    title: 'Make thumbnails',
    subtitle: 'Small preview copies',
  ),
  trimVideo(
    icon: Icons.content_cut,
    title: 'Trim video',
    subtitle: 'Keep the best part of a clip',
  ),
  speedVideo(
    icon: Icons.speed,
    title: 'Change speed',
    subtitle: '0.5× to 4× playback',
  ),
  removeAudio(
    icon: Icons.volume_off_outlined,
    title: 'Remove audio',
    subtitle: 'Silent video copies',
  ),
  extractAudio(
    icon: Icons.audio_file_outlined,
    title: 'Extract audio',
    subtitle: 'Keep only the soundtrack',
  ),
  duplicates(
    icon: Icons.content_copy,
    title: 'Find duplicates',
    subtitle: 'Scan the app\'s exports folder',
  ),
  storage(
    icon: Icons.storage_outlined,
    title: 'Storage',
    subtitle: 'Dashboard and cleanup',
  ),
  history(
    icon: Icons.history,
    title: 'Conversion history',
    subtitle: 'What was converted and when',
  );

  const _Tool({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

/// The tools tab: real, engine-backed utilities. Images → PDF, GIF creation, frame extraction
/// and video merging are not offered because the engines do not implement them yet (see the
/// format matrix), so no buttons imply they exist.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  Future<void> _run(BuildContext context, _Tool tool) => switch (tool) {
    _Tool.storage => _push(context, const StorageScreen()),
    _Tool.history => _push(context, const ConversionHistoryScreen()),
    _Tool.duplicates => _push(context, const DuplicatesScreen()),
    _ => _runWithMedia(context, tool),
  };

  Future<void> _push(BuildContext context, Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (context) => screen));
  }

  Future<void> _runWithMedia(BuildContext context, _Tool tool) async {
    final items = await Navigator.of(context).push<List<MediaItem>>(
      MaterialPageRoute<List<MediaItem>>(
        builder: (context) => const ConvertSourcePicker(),
      ),
    );
    if (items == null || items.isEmpty || !context.mounted) {
      return;
    }

    final wantsImages = switch (tool) {
      _Tool.compressPhotos ||
      _Tool.rotateFlip ||
      _Tool.stripMetadata ||
      _Tool.watermark ||
      _Tool.thumbnails => true,
      _ => false,
    };
    final selection = items
        .where((item) => wantsImages ? item.kind.isImage : item.kind.isVideo)
        .toList(growable: false);
    if (selection.isEmpty) {
      showMessage(
        context,
        wantsImages
            ? 'Choose at least one photo for this tool.'
            : 'Choose at least one video for this tool.',
        error: true,
      );
      return;
    }

    final conversion = context.read<ConversionController>();
    final settings = context.read<SettingsController>();
    final previousImage = conversion.imageSpec;
    final previousVideo = conversion.videoSpec;
    final previousPolicy = settings.metadataPolicy;

    if (tool == _Tool.stripMetadata) {
      await settings.setMetadataPolicy(MetadataPolicy.stripAll);
    }

    final studio = _studioFor(tool, selection, conversion, previousVideo);

    if (!context.mounted) {
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (context) => studio));

    // Restore the draft state so tools do not silently change the Convert tab defaults.
    if (context.mounted) {
      conversion.updateImageSpec(previousImage);
      conversion.updateVideoSpec(previousVideo);
      if (previousPolicy != settings.metadataPolicy) {
        await settings.setMetadataPolicy(previousPolicy);
      }
    }
  }

  Widget _studioFor(
    _Tool tool,
    List<MediaItem> selection,
    ConversionController conversion,
    VideoConversionSpec previousVideo,
  ) {
    switch (tool) {
      case _Tool.compressPhotos:
        conversion.applyImagePreset(ImagePreset.sizeReduced);
        return ImageStudioScreen(items: selection);
      case _Tool.thumbnails:
        conversion.applyImagePreset(ImagePreset.thumbnail);
        return ImageStudioScreen(items: selection);
      case _Tool.watermark:
      case _Tool.rotateFlip:
      case _Tool.stripMetadata:
        return ImageStudioScreen(items: selection);
      case _Tool.compressVideos:
        conversion.applyVideoPreset(VideoPreset.smallerFile);
        return VideoStudioScreen(items: selection);
      case _Tool.trimVideo:
      case _Tool.speedVideo:
        return VideoStudioScreen(items: selection);
      case _Tool.removeAudio:
        conversion.updateVideoSpec(previousVideo.copyWith(keepAudio: false));
        return VideoStudioScreen(items: selection);
      case _Tool.extractAudio:
        conversion.applyVideoPreset(VideoPreset.audioOnly);
        return VideoStudioScreen(items: selection);
      case _Tool.storage:
      case _Tool.history:
      case _Tool.duplicates:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[
            const SectionHeader(
              title: 'Tools',
              subtitle: 'Batch operations powered by the conversion engine',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.35,
                children: <Widget>[
                  for (final tool in _Tool.values)
                    AppCard(
                      onTap: () => _run(context, tool),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Icon(tool.icon, color: context.colors.primary),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(tool.title, style: context.text.titleSmall),
                              Text(
                                tool.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.info_outline, color: AppColors.violet),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Not offered yet: Images → PDF, GIF creation, frame '
                        'extraction and video merging — the engines do not '
                        'implement them, so no buttons imply they exist. See '
                        'the format matrix for details.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
