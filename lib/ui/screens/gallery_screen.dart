import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/utils/byte_format.dart';
import '../../domain/media/media_item.dart';
import '../../domain/settings/app_settings.dart';
import '../../services/ads/ad_service.dart';
import '../../services/gallery/gallery_service.dart';
import '../../state/gallery_controller.dart';
import '../../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/ad_slot.dart';
import '../widgets/common.dart';
import 'convert_flow.dart';
import 'media_viewer_screen.dart';

/// The photo/video library: paged grid or list, search, filter, sort, multi-select and the
/// entry points for viewing and converting.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GalleryController>().initialize();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      context.read<GalleryController>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gallery = context.watch<GalleryController>();

    return Scaffold(
      appBar: AppBar(
        title: gallery.isSelecting
            ? Text('${gallery.selectionCount} selected')
            : _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search name or format',
                  border: InputBorder.none,
                ),
                onChanged: (_) => context.read<GalleryController>().setQuery(
                  _searchController.text,
                ),
              )
            : const Text('Gallery'),
        actions: <Widget>[
          if (!gallery.isSelecting) ...<Widget>[
            if (gallery.canBrowse)
              IconButton(
                tooltip: 'Search',
                onPressed: () => setState(() => _searching = !_searching),
                icon: const Icon(Icons.search),
              ),
            if (gallery.canBrowse)
              IconButton(
                tooltip: 'Filter',
                onPressed: () => _showFilters(context),
                icon: const Icon(Icons.filter_list),
              ),
            if (gallery.canBrowse)
              PopupMenuButton<SortField>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                onSelected: (field) {
                  context.read<GalleryController>().setSort(
                    field,
                    ascending: field == gallery.sort
                        ? !gallery.ascending
                        : gallery.ascending,
                  );
                },
                itemBuilder: (context) => <PopupMenuEntry<SortField>>[
                  for (final field in SortField.values)
                    PopupMenuItem<SortField>(
                      value: field,
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(_sortLabel(field))),
                          if (field == gallery.sort)
                            Icon(
                              gallery.ascending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            IconButton(
              tooltip: 'Switch layout',
              onPressed: () {
                final settings = context.read<SettingsController>();
                final layout = settings.settings.galleryLayout;
                settings.setGalleryLayout(
                  layout == GalleryLayout.grid
                      ? GalleryLayout.list
                      : GalleryLayout.grid,
                );
              },
              icon: Icon(
                context.read<SettingsController>().settings.galleryLayout ==
                        GalleryLayout.grid
                    ? Icons.view_list
                    : Icons.grid_view,
              ),
            ),
          ] else ...<Widget>[
            IconButton(
              tooltip: 'Select all visible',
              onPressed: () =>
                  context.read<GalleryController>().selectAllVisible(),
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              tooltip: 'Clear selection',
              onPressed: () =>
                  context.read<GalleryController>().clearSelection(),
              icon: const Icon(Icons.close),
            ),
          ],
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildBody(gallery)),
          if (gallery.isSelecting) _SelectionBar(count: gallery.selectionCount),
          const AdBannerSlot(placement: AdPlacement.galleryBanner),
        ],
      ),
    );
  }

  Widget _buildBody(GalleryController gallery) {
    if (!gallery.isSupported) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'Gallery unavailable on this platform',
        message:
            'The media library needs Android or iOS. On other platforms use the '
            'Convert tab to pick files directly.',
      );
    }
    if (!gallery.canBrowse) {
      return _PermissionGate(gallery: gallery);
    }
    if (gallery.loading && gallery.allItems.isEmpty) {
      return _SkeletonGrid(
        columns: context
            .read<SettingsController>()
            .settings
            .galleryGridColumns
            .clamp(2, 6),
      );
    }
    final items = gallery.visibleItems;
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: gallery.query.trim().isEmpty
            ? 'Nothing here yet'
            : 'No matches for “${gallery.query.trim()}”',
        message: gallery.query.trim().isEmpty
            ? 'Photos and videos from this device will appear here.'
            : 'Try a different file name or format.',
        action: gallery.query.trim().isEmpty
            ? null
            : FilledButton.tonal(
                onPressed: () {
                  _searchController.clear();
                  context.read<GalleryController>().setQuery('');
                  setState(() => _searching = false);
                },
                child: const Text('Clear search'),
              ),
      );
    }
    final layout = context.read<SettingsController>().settings.galleryLayout;
    if (layout == GalleryLayout.list) {
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.sm),
        itemCount: items.length + (gallery.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const _LoadMoreFooter();
          }
          return _ListTileRow(
            item: items[index],
            onTap: () => _openItem(gallery, items, index),
          );
        },
      );
    }
    final columns = context
        .read<SettingsController>()
        .settings
        .galleryGridColumns
        .clamp(2, 6);
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: items.length + (gallery.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const _LoadMoreFooter();
        }
        return _GridTile(
          item: items[index],
          onTap: () => _openItem(gallery, items, index),
        );
      },
    );
  }

  void _openItem(GalleryController gallery, List<MediaItem> items, int index) {
    if (gallery.isSelecting) {
      gallery.toggleSelection(items[index]);
      return;
    }
    final item = items[index];
    if (item.kind.isConvertible) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              MediaViewerScreen(items: items, initialIndex: index),
        ),
      );
    }
  }

  Future<void> _showFilters(BuildContext context) async {
    final gallery = context.read<GalleryController>();
    var images = gallery.filter.images;
    var videos = gallery.filter.videos;
    var favourites = gallery.filter.favouritesOnly;

    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  'Filter media',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              CheckboxListTile(
                title: const Text('Photos'),
                value: images,
                onChanged: (value) =>
                    setSheetState(() => images = value ?? true),
              ),
              CheckboxListTile(
                title: const Text('Videos'),
                value: videos,
                onChanged: (value) =>
                    setSheetState(() => videos = value ?? true),
              ),
              CheckboxListTile(
                title: const Text('Favourites only'),
                value: favourites,
                onChanged: (value) =>
                    setSheetState(() => favourites = value ?? false),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _FilterResult(
                          images: images,
                          videos: videos,
                          favourites: favourites,
                        ),
                      ),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) {
      return;
    }
    await gallery.setFilter(
      GalleryFilter(
        images: result.images,
        videos: result.videos,
        favouritesOnly: result.favourites,
      ),
    );
  }

  static String _sortLabel(SortField field) => switch (field) {
    SortField.dateModified => 'Date modified',
    SortField.dateCreated => 'Date created',
    SortField.name => 'Name',
    SortField.size => 'Size',
    SortField.format => 'Format',
    SortField.duration => 'Duration',
  };
}

class _FilterResult {
  const _FilterResult({
    required this.images,
    required this.videos,
    required this.favourites,
  });

  final bool images;
  final bool videos;
  final bool favourites;
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gallery = context.watch<GalleryController>();
    final selected = gallery.isSelected(item);
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => gallery.toggleSelection(item),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipRRect(
            borderRadius: AppRadius.smallAll,
            child:
                gallery.thumbnail(item, extent: 512) ??
                Container(
                  color: context.colors.surfaceContainerHighest,
                  child: Icon(
                    item.kind.isVideo
                        ? Icons.movie_outlined
                        : Icons.image_outlined,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
          ),
          if (item.isVideo && item.duration != null)
            Positioned(
              right: 4,
              bottom: 4,
              child: _Badge(
                text: ByteFormat.duration(item.duration),
                icon: Icons.play_arrow,
              ),
            ),
          if (item.isFavorite)
            const Positioned(
              top: 4,
              left: 4,
              child: Icon(Icons.star, size: 16, color: Colors.amber),
            ),
          if (item.availability != MediaAvailability.local)
            Positioned(
              top: 4,
              right: 4,
              child: _Badge(
                text: item.availability == MediaAvailability.missing
                    ? 'Gone'
                    : 'iCloud',
                icon: Icons.cloud,
              ),
            ),
          if (selected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.smallAll,
                  color: context.colors.primary.withValues(alpha: 0.35),
                  border: Border.all(color: context.colors.primary, width: 2),
                ),
                child: const Center(
                  child: Icon(Icons.check_circle, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ListTileRow extends StatelessWidget {
  const _ListTileRow({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gallery = context.watch<GalleryController>();
    final selected = gallery.isSelected(item);
    return ListTile(
      leading: ClipRRect(
        borderRadius: AppRadius.smallAll,
        child: SizedBox(
          width: 52,
          height: 52,
          child:
              gallery.thumbnail(item, extent: 128) ??
              Container(
                color: context.colors.surfaceContainerHighest,
                child: Icon(
                  item.kind.isVideo
                      ? Icons.movie_outlined
                      : Icons.image_outlined,
                ),
              ),
        ),
      ),
      title: Text(
        item.displayName ?? item.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item.formatLabel} · ${ByteFormat.binary(item.sizeBytes)}'
        '${item.duration != null ? ' · ${ByteFormat.duration(item.duration)}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Colors.green)
          : item.isFavorite
          ? const Icon(Icons.star, color: Colors.amber)
          : null,
      selected: selected,
      onTap: onTap,
      onLongPress: () => gallery.toggleSelection(item),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 2),
          ],
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter();

  @override
  Widget build(BuildContext context) {
    final gallery = context.watch<GalleryController>();
    if (!gallery.hasMore) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: gallery.loadingMore
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: () => context.read<GalleryController>().loadMore(),
                child: const Text('Load more'),
              ),
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: columns * 4,
      itemBuilder: (context, index) =>
          const ShimmerBox(radius: AppRadius.smallAll),
    );
  }
}

class _PermissionGate extends StatelessWidget {
  const _PermissionGate({required this.gallery});

  final GalleryController gallery;

  @override
  Widget build(BuildContext context) {
    final status = gallery.permission;
    final limited = status == GalleryPermission.limited;
    return EmptyState(
      icon: limited ? Icons.photo_library_outlined : Icons.lock_outline,
      title: limited
          ? 'Limited access'
          : status == GalleryPermission.denied
          ? 'Access to photos is blocked'
          : 'Photos need your permission',
      message: limited
          ? 'You chose a limited set of photos. You can add more or grant full access.'
          : status == GalleryPermission.denied
          ? 'Open the system settings to allow access to your photos and videos.'
          : 'The gallery stays on this device. Nothing is uploaded.',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (limited)
            TextButton(
              onPressed: gallery.presentLimitedPicker,
              child: const Text('Choose more photos'),
            ),
          if (status == GalleryPermission.denied)
            FilledButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Open settings'),
            )
          else if (!status.isUsable)
            FilledButton.icon(
              onPressed: gallery.requestPermission,
              icon: const Icon(Icons.lock_open),
              label: const Text('Allow access'),
            ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final gallery = context.read<GalleryController>();
    final items = gallery.selectedItems;

    return Material(
      color: context.colors.primaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Convert',
                onPressed: () => startConversionFlow(context, items),
                icon: const Icon(Icons.swap_horiz),
              ),
              IconButton(
                tooltip: 'Share',
                onPressed: () async {
                  final resolved = await gallery.resolveForConversion(items);
                  final paths = resolved.ready
                      .map((item) => item.path ?? '')
                      .where((path) => path.isNotEmpty)
                      .toList();
                  if (!context.mounted) {
                    return;
                  }
                  await sharePaths(context, paths);
                },
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: 'Favourite',
                onPressed: () async {
                  for (final item in items) {
                    await gallery.toggleFavorite(item);
                  }
                },
                icon: const Icon(Icons.star_outline),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, items),
                icon: const Icon(Icons.delete_outline),
              ),
              const Spacer(),
              Text(
                '$count selected',
                style: context.text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    List<MediaItem> items,
  ) async {
    final settings = context.read<SettingsController>();
    final gallery = context.read<GalleryController>();
    if (!settings.settings.confirmBeforeDelete) {
      await gallery.deleteItems(items);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${items.length} item(s)?'),
        content: const Text(
          'This removes them from your photo library. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await gallery.deleteItems(items);
    }
  }
}
