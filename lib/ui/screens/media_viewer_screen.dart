import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/byte_format.dart';
import '../../domain/media/media_item.dart';
import '../../state/gallery_controller.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import 'convert_flow.dart';

/// Full-screen viewer for one or more images/videos.
///
/// Images support pinch-zoom, double-tap zoom and swipe. Videos play inline with basic
/// transport controls. No media is uploaded anywhere.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  final List<MediaItem> items;
  final int initialIndex;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _showDetails = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  MediaItem get _current => widget.items[_index];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.items.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Details',
            onPressed: () => setState(() => _showDetails = !_showDetails),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Convert',
            onPressed: () =>
                startConversionFlow(context, <MediaItem>[_current]),
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              if (item.isVideo) {
                return _VideoPane(item: item);
              }
              return _ImagePane(item: item);
            },
          ),
          if (_showDetails) _DetailsPanel(item: _current),
        ],
      ),
    );
  }
}

class _ImagePane extends StatelessWidget {
  const _ImagePane({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final preview = context.read<GalleryController>().previewOf(item);
    if (preview == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.white54,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'This image is not available on this device.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => openPath(context, item.path ?? ''),
              child: const Text('Try opening it externally'),
            ),
          ],
        ),
      );
    }
    return PhotoView(
      imageProvider: preview,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      errorBuilder: (context, error, stack) => const Center(
        child: Text(
          'This image could not be displayed.',
          style: TextStyle(color: Colors.white70),
        ),
      ),
      loadingBuilder: (context, event) =>
          const Center(child: CircularProgressIndicator()),
    );
  }
}

class _VideoPane extends StatefulWidget {
  const _VideoPane({required this.item});

  final MediaItem item;

  @override
  State<_VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<_VideoPane> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final path = await context.read<GalleryController>().localPathFor(
      widget.item,
    );
    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() => _error = 'This video is not available on this device.');
      }
      return;
    }
    try {
      final controller = VideoPlayerController.file(
        File(path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.play();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'This video could not be played on this device.',
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            VideoPlayer(controller),
            _VideoControls(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          final duration = value.duration;
          final position = value.position;
          return Row(
            children: <Widget>[
              IconButton(
                color: Colors.white,
                onPressed: () {
                  if (value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                },
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Text(
                ByteFormat.duration(position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: duration.inMilliseconds == 0
                      ? 0
                      : position.inMilliseconds
                            .clamp(0, duration.inMilliseconds)
                            .toDouble(),
                  max: duration.inMilliseconds.toDouble().clamp(
                    1,
                    double.infinity,
                  ),
                  onChanged: (milliseconds) => controller.seekTo(
                    Duration(milliseconds: milliseconds.round()),
                  ),
                ),
              ),
              Text(
                ByteFormat.duration(duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.displayName ?? item.id,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Format: ${item.formatLabel}'),
              if (item.resolutionLabel != null)
                Text('Dimensions: ${item.resolutionLabel}'),
              if (item.duration != null)
                Text('Duration: ${ByteFormat.duration(item.duration)}'),
              Text('Size: ${ByteFormat.binary(item.sizeBytes)}'),
              Text(
                'Availability: ${item.availability == MediaAvailability.remote
                    ? 'In iCloud'
                    : item.availability == MediaAvailability.missing
                    ? 'Missing'
                    : 'On this device'}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
