import 'package:flutter/material.dart';

import '../../domain/media/media_item.dart';
import 'image_studio_screen.dart';
import 'video_studio_screen.dart';

/// Routes a selection to the right studio.
///
/// A mixed selection is split with an explicit choice so the user is never surprised by which
/// files were converted.
Future<void> startConversionFlow(
  BuildContext context,
  List<MediaItem> items, {
  bool quick = false,
}) async {
  final images = items
      .where((item) => item.kind.isImage)
      .toList(growable: false);
  final videos = items
      .where((item) => item.kind.isVideo)
      .toList(growable: false);
  if (images.isEmpty && videos.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Select a photo or video to convert.')),
    );
    return;
  }

  if (videos.isEmpty) {
    await _push(context, ImageStudioScreen(items: images));
    return;
  }
  if (images.isEmpty) {
    await _push(context, VideoStudioScreen(items: videos));
    return;
  }

  final choice = await showModalBottomSheet<_MixedChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text('Convert ${images.length} photo(s)'),
            onTap: () => Navigator.pop(context, _MixedChoice.images),
          ),
          ListTile(
            leading: const Icon(Icons.movie_outlined),
            title: Text('Convert ${videos.length} video(s)'),
            onTap: () => Navigator.pop(context, _MixedChoice.videos),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || choice == null) {
    return;
  }
  switch (choice) {
    case _MixedChoice.images:
      await _push(context, ImageStudioScreen(items: images));
    case _MixedChoice.videos:
      await _push(context, VideoStudioScreen(items: videos));
  }
}

enum _MixedChoice { images, videos }

Future<void> _push(BuildContext context, Widget screen) {
  return Navigator.of(context)
      .push<void>(MaterialPageRoute<void>(builder: (context) => screen));
}
