import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../services/gallery/gallery_service.dart';
import '../../state/gallery_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// A lightweight gallery picker used by the Convert tab and Tools.
///
/// It uses its own [GalleryController] so selections never leak into the Gallery tab.
class ConvertSourcePicker extends StatefulWidget {
  const ConvertSourcePicker({super.key});

  @override
  State<ConvertSourcePicker> createState() => _ConvertSourcePickerState();
}

class _ConvertSourcePickerState extends State<ConvertSourcePicker> {
  late final GalleryController _gallery = GalleryController(
    context.read<GalleryService>(),
  );
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _gallery.initialize());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _gallery.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _gallery.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _gallery,
      builder: (context, child) {
        final canBrowse = _gallery.canBrowse;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _gallery.isSelecting
                  ? '${_gallery.selectionCount} selected'
                  : 'Choose from gallery',
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Select all visible',
                onPressed: _gallery.selectAllVisible,
                icon: const Icon(Icons.select_all),
              ),
            ],
          ),
          body: !_gallery.isSupported
              ? const EmptyState(
                  icon: Icons.photo_library_outlined,
                  title: 'Gallery unavailable',
                  message: 'Use “Pick files” instead on this platform.',
                )
              : !canBrowse
              ? EmptyState(
                  icon: Icons.lock_outline,
                  title: 'Photos need your permission',
                  message:
                      'The gallery stays on this device. Nothing is uploaded.',
                  action: FilledButton(
                    onPressed: () => _gallery.requestPermission(),
                    child: const Text('Allow access'),
                  ),
                )
              : _gallery.loading && _gallery.allItems.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _grid(),
          bottomNavigationBar: _gallery.isSelecting
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(_gallery.selectedItems);
                      },
                      child: Text('Convert ${_gallery.selectionCount} item(s)'),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _grid() {
    final items = _gallery.visibleItems;
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.image_outlined,
        title: 'Nothing to choose',
        message: 'No photos or videos were found on this device.',
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: items.length + (_gallery.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final item = items[index];
        final selected = _gallery.isSelected(item);
        return GestureDetector(
          onTap: () => _gallery.toggleSelection(item),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ClipRRect(
                borderRadius: AppRadius.smallAll,
                child:
                    _gallery.thumbnail(item, extent: 300) ??
                    Container(
                      color: context.colors.surfaceContainerHighest,
                      child: Icon(
                        item.kind.isVideo
                            ? Icons.movie_outlined
                            : Icons.image_outlined,
                      ),
                    ),
              ),
              if (item.isVideo && item.duration != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      ByteFormat.duration(item.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              if (selected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.smallAll,
                      color: context.colors.primary.withValues(alpha: 0.4),
                      border: Border.all(
                        color: context.colors.primary,
                        width: 2.5,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.check_circle, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
