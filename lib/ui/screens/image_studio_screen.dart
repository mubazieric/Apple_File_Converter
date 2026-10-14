import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../domain/conversion/image_spec.dart';
import '../../domain/conversion/metadata_policy.dart';
import '../../domain/conversion/presets.dart';
import '../../domain/media/image_format.dart';
import '../../domain/media/media_item.dart';
import '../../services/platform/platform_info.dart';
import '../../state/conversion_controller.dart';
import '../../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/common.dart';
import 'conversion_queue_screen.dart';

/// The image conversion studio: pick a format and quality, resize, rotate, watermark and
/// choose how metadata is handled, then hand a batch to the queue.
class ImageStudioScreen extends StatefulWidget {
  const ImageStudioScreen({super.key, required this.items});

  final List<MediaItem> items;

  @override
  State<ImageStudioScreen> createState() => _ImageStudioScreenState();
}

class _ImageStudioScreenState extends State<ImageStudioScreen> {
  late ImageConversionSpec _spec;
  bool _starting = false;
  final TextEditingController _watermarkController = TextEditingController();
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  late final List<ImageFormat> _targets = ImageFormat.encodableTargets(
    PlatformInfo.kind,
  );

  @override
  void initState() {
    super.initState();
    _spec = context.read<ConversionController>().imageSpec;
    final resize = _spec.resize;
    if (resize.mode == ResizeMode.absolute) {
      _widthController.text = (resize.width ?? 0).toString();
      _heightController.text = (resize.height ?? 0).toString();
    }
    _watermarkController.text = _spec.watermark?.text ?? '';
  }

  @override
  void dispose() {
    _watermarkController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  bool get _sourceHasAlpha =>
      widget.items.any((item) => item.imageFormat.hasAlpha);

  bool get _losesAlpha => _sourceHasAlpha && !_spec.outputFormat.hasAlpha;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final controller = context.read<ConversionController>();
      final result = await controller.convertImages(widget.items, spec: _spec);
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

  void _update(ImageConversionSpec next) => setState(() => _spec = next);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final maxMb = widget.items.fold<int>(
      0,
      (sum, item) => sum + (item.sizeBytes ?? 0),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Convert images')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppCard(
              child: Row(
                children: <Widget>[
                  Icon(Icons.image_outlined, color: context.colors.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${widget.items.length} image(s) selected',
                          style: context.text.titleSmall,
                        ),
                        Text(
                          'Up to ${ByteFormat.binary(maxMb)}',
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
          if (_losesAlpha)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: InfoBanner(
                tone: BannerTone.warning,
                title: 'Transparency will be lost',
                message:
                    'Some photos have transparent areas, but the chosen format does '
                    'not support transparency. Those areas will become solid. Choose '
                    'PNG or WebP to keep them.',
              ),
            ),
          const SectionHeader(title: 'Preset'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final preset in ImagePreset.values)
                  if (preset != ImagePreset.custom)
                    ChoiceChip(
                      label: Text(preset.label),
                      selected:
                          context.watch<ConversionController>().imagePreset ==
                          preset,
                      onSelected: (_) {
                        context.read<ConversionController>().applyImagePreset(
                          preset,
                        );
                        _update(preset.toSpec());
                      },
                    ),
              ],
            ),
          ),
          if (context.watch<ConversionController>().imagePreset !=
              ImagePreset.custom)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: Text(
                context.watch<ConversionController>().imagePreset.description,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          const SectionHeader(title: 'Output format'),
          ChoiceChips<ImageFormat>(
            values: _targets,
            selected: _spec.outputFormat,
            labelOf: (format) => format.label,
            onSelected: (format) => _update(
              _spec.copyWith(
                outputFormat: format,
                quality: format.defaultQuality,
              ),
            ),
          ),
          if (_spec.outputFormat.isLossy)
            SliderRow(
              label: 'Quality',
              value: (_spec.quality ?? _spec.outputFormat.defaultQuality)
                  .toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              valueLabel: (value) => '${value.round()}',
              onChanged: (value) =>
                  _update(_spec.copyWith(quality: value.round())),
            ),
          const SectionHeader(title: 'Size'),
          ChoiceChips<ResizeMode>(
            values: ResizeMode.values,
            selected: _spec.resize.mode,
            labelOf: _resizeLabel,
            onSelected: (mode) =>
                _update(_spec.copyWith(resize: _resizeFor(mode, _spec.resize))),
          ),
          ..._resizeControls(),
          const SectionHeader(title: 'Orientation'),
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
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final flip in FlipAxis.values)
                  ChoiceChip(
                    label: Text(_flipLabel(flip)),
                    selected: _spec.flip == flip,
                    onSelected: (_) => _update(_spec.copyWith(flip: flip)),
                  ),
              ],
            ),
          ),
          const SectionHeader(
            title: 'Watermark',
            subtitle: 'Optional text drawn onto each image',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              controller: _watermarkController,
              decoration: const InputDecoration(
                hintText: 'e.g. © Iwat Digital',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _update(
                value.trim().isEmpty
                    ? _spec.copyWith(clearWatermark: true)
                    : _spec.copyWith(
                        watermark: WatermarkSpec(
                          text: value,
                          position:
                              _spec.watermark?.position ??
                              WatermarkPosition.bottomRight,
                        ),
                      ),
              ),
            ),
          ),
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
              label: Text('Convert ${widget.items.length} image(s)'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _resizeControls() {
    final resize = _spec.resize;
    switch (resize.mode) {
      case ResizeMode.none:
        return const <Widget>[];
      case ResizeMode.percentage:
        return <Widget>[
          SliderRow(
            label: 'Scale',
            value: resize.percentage ?? 100,
            min: 10,
            max: 100,
            divisions: 18,
            valueLabel: (value) => '${value.round()}%',
            onChanged: (value) =>
                _update(_spec.copyWith(resize: ResizeSpec.percentage(value))),
          ),
        ];
      case ResizeMode.longestEdge:
        return <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                for (final edge in <int>[720, 1080, 1920, 2560, 3840])
                  ChoiceChip(
                    label: Text('$edge px'),
                    selected: resize.longestEdge == edge,
                    onSelected: (_) => _update(
                      _spec.copyWith(resize: ResizeSpec.longestEdge(edge)),
                    ),
                  ),
              ],
            ),
          ),
        ];
      case ResizeMode.absolute:
        return <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _applyAbsolute(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _applyAbsolute(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'Dimensions are exact; aspect ratio may change.',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ];
    }
  }

  void _applyAbsolute() {
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return;
    }
    _update(
      _spec.copyWith(
        resize: ResizeSpec.absolute(
          width: width,
          height: height,
          lockAspectRatio: false,
        ),
      ),
    );
  }

  ResizeSpec _resizeFor(ResizeMode mode, ResizeSpec current) => switch (mode) {
    ResizeMode.none => const ResizeSpec.none(),
    ResizeMode.percentage => ResizeSpec.percentage(current.percentage ?? 100),
    ResizeMode.longestEdge => ResizeSpec.longestEdge(
      current.longestEdge ?? 1920,
    ),
    ResizeMode.absolute => ResizeSpec.absolute(
      width: current.width ?? 1024,
      height: current.height ?? 1024,
      lockAspectRatio: false,
    ),
  };

  static String _resizeLabel(ResizeMode mode) => switch (mode) {
    ResizeMode.none => 'Original',
    ResizeMode.percentage => 'Percent',
    ResizeMode.longestEdge => 'Longest edge',
    ResizeMode.absolute => 'Exact size',
  };

  static String _flipLabel(FlipAxis flip) => switch (flip) {
    FlipAxis.none => 'No flip',
    FlipAxis.horizontal => 'Mirror',
    FlipAxis.vertical => 'Flip vertical',
    FlipAxis.both => 'Flip both',
  };

  static String _metadataLabel(MetadataPolicy policy) => switch (policy) {
    MetadataPolicy.preserve => 'Keep all',
    MetadataPolicy.stripLocation => 'Remove location',
    MetadataPolicy.stripAll => 'Remove all',
  };
}
