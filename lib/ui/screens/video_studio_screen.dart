import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../domain/conversion/image_spec.dart';
import '../../domain/conversion/metadata_policy.dart';
import '../../domain/conversion/presets.dart';
import '../../domain/conversion/video_spec.dart';
import '../../domain/media/media_item.dart';
import '../../domain/media/video_format.dart';
import '../../services/platform/platform_info.dart';
import '../../state/conversion_controller.dart';
import '../../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/common.dart';
import 'conversion_queue_screen.dart';

/// The video conversion studio: preset, container/codec, resolution, quality, frame rate,
/// audio, trim, rotate, speed and metadata handling.
class VideoStudioScreen extends StatefulWidget {
  const VideoStudioScreen({super.key, required this.items});

  final List<MediaItem> items;

  @override
  State<VideoStudioScreen> createState() => _VideoStudioScreenState();
}

class _VideoStudioScreenState extends State<VideoStudioScreen> {
  late VideoConversionSpec _spec;
  bool _starting = false;
  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customHeightController = TextEditingController();
  final TextEditingController _trimStartController = TextEditingController();
  final TextEditingController _trimEndController = TextEditingController();

  late final List<VideoContainer> _containers = VideoContainer.encodableTargets(
    PlatformInfo.kind,
  );

  @override
  void initState() {
    super.initState();
    _spec = context.read<ConversionController>().videoSpec;
    if (_spec.resolution == ResolutionPreset.custom) {
      _customWidthController.text = (_spec.customWidth ?? 1280).toString();
      _customHeightController.text = (_spec.customHeight ?? 720).toString();
    }
    if (_spec.trimStart != null) {
      _trimStartController.text = _secondsLabel(_spec.trimStart!);
    }
    if (_spec.trimEnd != null) {
      _trimEndController.text = _secondsLabel(_spec.trimEnd!);
    }
  }

  @override
  void dispose() {
    _customWidthController.dispose();
    _customHeightController.dispose();
    _trimStartController.dispose();
    _trimEndController.dispose();
    super.dispose();
  }

  Duration? get _firstDuration => widget.items
      .map((item) => item.duration)
      .firstWhere((duration) => duration != null, orElse: () => null);

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final controller = context.read<ConversionController>();
      final result = await controller.convertVideos(widget.items, spec: _spec);
      if (!mounted) {
        return;
      }
      if (result.nothingToDo) {
        showMessage(
          context,
          'None of the selected files could be read.',
          error: true,
        );
        return;
      }
      final parts = <String>['${result.enqueued} added to the queue'];
      if (result.hasUnavailable) {
        parts.add('${result.unavailable} could not be read');
      }
      showMessage(context, parts.join(' · '));
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const ConversionQueueScreen(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  void _update(VideoConversionSpec next) => setState(() => _spec = next);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final estimated = _firstDuration == null
        ? null
        : _spec.estimateOutputBytes(_firstDuration!);

    return Scaffold(
      appBar: AppBar(title: const Text('Convert videos')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppCard(
              child: Row(
                children: <Widget>[
                  Icon(Icons.movie_outlined, color: context.colors.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${widget.items.length} video(s) selected',
                          style: context.text.titleSmall,
                        ),
                        if (estimated != null)
                          Text(
                            'Estimated output ≈ ${ByteFormat.binary(estimated)}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader(title: 'Preset'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final preset in VideoPreset.values)
                  if (preset != VideoPreset.custom)
                    ChoiceChip(
                      label: Text(preset.label),
                      selected:
                          context.watch<ConversionController>().videoPreset ==
                          preset,
                      onSelected: (_) {
                        context.read<ConversionController>().applyVideoPreset(
                          preset,
                        );
                        _update(preset.toSpec());
                      },
                    ),
              ],
            ),
          ),
          if (context.watch<ConversionController>().videoPreset !=
              VideoPreset.custom)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: Text(
                context.watch<ConversionController>().videoPreset.description,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          const SectionHeader(title: 'Container'),
          ChoiceChips<VideoContainer>(
            values: _containers,
            selected: _spec.container,
            labelOf: (container) => container.label,
            onSelected: (container) =>
                _update(_spec.copyWith(container: container)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SwitchRow(
              title: 'Copy streams instead of re-encoding',
              subtitle:
                  'Fast, lossless container change. Video filters like trimming, '
                  'rotation and speed require re-encoding and are disabled.',
              value: _spec.remuxOnly,
              onChanged: (value) {
                _update(
                  value
                      ? _spec.copyWith(
                          remuxOnly: true,
                          resolution: ResolutionPreset.original,
                          rotation: Rotation.none,
                          speed: SpeedMode.normal,
                          trimStart: null,
                          trimEnd: null,
                        )
                      : _spec.copyWith(remuxOnly: false),
                );
              },
            ),
          ),
          if (!_spec.remuxOnly) ...<Widget>[
            const SectionHeader(title: 'Resolution'),
            ChoiceChips<ResolutionPreset>(
              values: ResolutionPreset.values,
              selected: _spec.resolution,
              labelOf: (resolution) => resolution.label,
              onSelected: (resolution) =>
                  _update(_spec.copyWith(resolution: resolution)),
            ),
            if (_spec.resolution == ResolutionPreset.custom)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _customWidthController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Width',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _applyCustomResolution(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextField(
                        controller: _customHeightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Height',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _applyCustomResolution(),
                      ),
                    ),
                  ],
                ),
              ),
            const SectionHeader(title: 'Quality'),
            ChoiceChips<VideoQuality>(
              values: VideoQuality.values,
              selected: _spec.quality,
              labelOf: (quality) => switch (quality) {
                VideoQuality.smaller => 'Smaller',
                VideoQuality.balanced => 'Balanced',
                VideoQuality.high => 'High',
                VideoQuality.maximum => 'Maximum',
              },
              onSelected: (quality) =>
                  _update(_spec.copyWith(quality: quality)),
            ),
            const SectionHeader(title: 'Frame rate'),
            ChoiceChips<int?>(
              values: const <int?>[null, 24, 25, 30, 50, 60],
              selected: _spec.frameRate,
              labelOf: (fps) => fps == null ? 'Original' : '$fps fps',
              onSelected: (fps) => _update(
                _spec.copyWith(frameRate: fps, clearFrameRate: fps == null),
              ),
            ),
            SliderRow(
              label: 'Video bitrate',
              value:
                  (_spec.videoBitrateKbps ?? _spec.estimateVideoBitrateKbps())
                      .toDouble(),
              min: 200,
              max: 20000,
              divisions: 98,
              valueLabel: (value) => '${value.round()} kbps',
              onChanged: (value) =>
                  _update(_spec.copyWith(videoBitrateKbps: value.round())),
            ),
            const SectionHeader(title: 'Audio'),
            SwitchRow(
              title: 'Keep the audio track',
              value: _spec.keepAudio,
              onChanged: (value) => _update(_spec.copyWith(keepAudio: value)),
            ),
            if (_spec.keepAudio) ...<Widget>[
              ChoiceChips<AudioCodec>(
                values: <AudioCodec>[
                  AudioCodec.aac,
                  AudioCodec.opus,
                  AudioCodec.mp3,
                  AudioCodec.pcm,
                ],
                selected: _spec.audioCodec ?? AudioCodec.aac,
                labelOf: (codec) => codec.label,
                onSelected: (codec) =>
                    _update(_spec.copyWith(audioCodec: codec)),
              ),
              SliderRow(
                label: 'Audio bitrate',
                value: _spec.audioBitrateKbps.toDouble(),
                min: 64,
                max: 320,
                divisions: 32,
                valueLabel: (value) => '${value.round()} kbps',
                onChanged: (value) =>
                    _update(_spec.copyWith(audioBitrateKbps: value.round())),
              ),
            ],
            const SectionHeader(title: 'Trim'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _trimStartController,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        labelText: 'Start (mm:ss or hh:mm:ss)',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _applyTrim(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _trimEndController,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        labelText: 'End (mm:ss or hh:mm:ss)',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _applyTrim(),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader(title: 'Rotate'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final rotation in Rotation.values)
                    ChoiceChip(
                      label: Text('${rotation.degrees}°'),
                      selected: _spec.rotation == rotation,
                      onSelected: (_) =>
                          _update(_spec.copyWith(rotation: rotation)),
                    ),
                ],
              ),
            ),
            const SectionHeader(title: 'Speed'),
            ChoiceChips<SpeedMode>(
              values: SpeedMode.values,
              selected: _spec.speed,
              labelOf: (mode) => mode.label,
              onSelected: (mode) => _update(_spec.copyWith(speed: mode)),
            ),
            const SectionHeader(title: 'Hardware acceleration'),
            ChoiceChips<HardwareAcceleration>(
              values: HardwareAcceleration.values,
              selected: _spec.hardware,
              labelOf: (hardware) => switch (hardware) {
                HardwareAcceleration.auto => 'Auto',
                HardwareAcceleration.require => 'Require hardware',
              },
              onSelected: (hardware) =>
                  _update(_spec.copyWith(hardware: hardware)),
            ),
          ],
          const SectionHeader(title: 'Metadata'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                for (final policy in MetadataPolicy.values)
                  ChoiceChip(
                    label: Text(_metadataLabel(policy)),
                    selected: settings.metadataPolicy == policy,
                    onSelected: (_) => context
                        .read<SettingsController>()
                        .setMetadataPolicy(policy),
                  ),
              ],
            ),
          ),
          if (!_spec.remuxOnly)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: InfoBanner(
                title: 'About encoding',
                message:
                    'H.264 and HEVC are encoded by your device\'s hardware '
                    'encoder when available, which keeps processing fast and '
                    'efficient. Encoding is never guaranteed to succeed on every '
                    'device — the queue reports exactly what happened.',
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: FilledButton.icon(
              onPressed: _starting ? null : _start,
              icon: _starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text('Convert ${widget.items.length} video(s)'),
            ),
          ),
        ],
      ),
    );
  }

  void _applyCustomResolution() {
    final width = int.tryParse(_customWidthController.text);
    final height = int.tryParse(_customHeightController.text);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return;
    }
    _update(_spec.copyWith(customWidth: width, customHeight: height));
  }

  void _applyTrim() {
    final start = _parseDuration(_trimStartController.text);
    final end = _parseDuration(_trimEndController.text);
    _update(_spec.copyWith(trimStart: start, trimEnd: end));
  }

  static Duration? _parseDuration(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parts = trimmed.split(':').map(int.tryParse).toList();
    if (parts.any((part) => part == null) || parts.isEmpty) {
      return null;
    }
    final values = parts.cast<int?>().whereType<int>().toList();
    switch (values.length) {
      case 1:
        return Duration(seconds: values[0]);
      case 2:
        return Duration(minutes: values[0], seconds: values[1]);
      case 3:
        return Duration(
          hours: values[0],
          minutes: values[1],
          seconds: values[2],
        );
      default:
        return null;
    }
  }

  static String _secondsLabel(Duration duration) {
    final total = duration.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  static String _metadataLabel(MetadataPolicy policy) => switch (policy) {
    MetadataPolicy.preserve => 'Keep all',
    MetadataPolicy.stripLocation => 'Remove location',
    MetadataPolicy.stripAll => 'Remove all',
  };
}
