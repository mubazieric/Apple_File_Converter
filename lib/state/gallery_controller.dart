import 'dart:io';

import 'package:flutter/widgets.dart';

import '../domain/media/media_item.dart';
import '../domain/settings/app_settings.dart';
import '../services/gallery/gallery_service.dart';

/// Drives the gallery: permissions, paging, filtering, sorting, selection and search.
///
/// Search and some sort orders are applied to the items loaded so far (the platform query
/// cannot sort by file name or size), which is documented as a known limitation.
class GalleryController extends ChangeNotifier {
  GalleryController(this._service, {int pageSize = 120})
    : _pageSize = pageSize.clamp(20, 400);

  final GalleryService _service;
  final int _pageSize;

  final List<MediaItem> _items = <MediaItem>[];
  final Set<String> _selectedIds = <String>{};

  GalleryPermission _permission = GalleryPermission.notDetermined;
  GalleryFilter _filter = const GalleryFilter();
  SortField _sort = SortField.dateModified;
  bool _ascending = false;
  String _query = '';

  bool _initialised = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  String? _error;

  bool get isSupported => _service.isSupported;
  GalleryPermission get permission => _permission;
  GalleryFilter get filter => _filter;
  SortField get sort => _sort;
  bool get ascending => _ascending;
  String get query => _query;
  bool get initialised => _initialised;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;

  bool get canBrowse => isSupported && _permission.isUsable;

  /// All loaded items, filtered by the current search query.
  List<MediaItem> get visibleItems {
    if (_query.trim().isEmpty) {
      return List<MediaItem>.unmodifiable(_items);
    }
    final needle = _query.trim().toLowerCase();
    return _items
        .where((item) {
          final name = (item.displayName ?? '').toLowerCase();
          final format = item.formatLabel.toLowerCase();
          final extension = item.kind.isVideo
              ? item.videoContainer.primaryExtension
              : item.imageFormat.primaryExtension;
          return name.contains(needle) ||
              format.contains(needle) ||
              extension.toLowerCase().contains(needle);
        })
        .toList(growable: false);
  }

  /// Every loaded item (unfiltered), used for "select all" semantics.
  List<MediaItem> get allItems => List<MediaItem>.unmodifiable(_items);

  Set<String> get selectedIds => Set<String>.unmodifiable(_selectedIds);
  bool get hasSelection => _selectedIds.isNotEmpty;
  int get selectionCount => _selectedIds.length;
  bool get isSelecting => _selectedIds.isNotEmpty;

  bool isSelected(MediaItem item) => _selectedIds.contains(item.id);

  List<MediaItem> get selectedItems => _items
      .where((item) => _selectedIds.contains(item.id))
      .toList(growable: false);

  /// Loads the first page, requesting permission if the user has not granted it yet.
  Future<void> initialize() async {
    if (!isSupported) {
      _initialised = true;
      notifyListeners();
      return;
    }
    _permission = await _service.permission();
    if (_permission == GalleryPermission.notDetermined) {
      _permission = await _service.requestPermission();
    }
    _initialised = true;
    notifyListeners();
    if (canBrowse) {
      await refresh();
    }
  }

  Future<void> requestPermission() async {
    if (!isSupported) {
      return;
    }
    _permission = await _service.requestPermission();
    notifyListeners();
    if (canBrowse) {
      await refresh();
    }
  }

  Future<void> presentLimitedPicker() async {
    await _service.presentLimited();
    await refresh();
  }

  Future<void> refresh() async {
    if (!canBrowse || _loading) {
      return;
    }
    _loading = true;
    _error = null;
    _page = 0;
    _hasMore = true;
    notifyListeners();

    try {
      final page = await _service.load(
        filter: _filter,
        sort: _sort,
        ascending: _ascending,
        page: 0,
        pageSize: _pageSize,
      );
      _items
        ..clear()
        ..addAll(page);
      _hasMore = page.length >= _pageSize;
      _pruneSelection();
    } catch (error) {
      _error = 'The gallery could not be loaded.';
      _items.clear();
      _hasMore = false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!canBrowse || _loading || _loadingMore || !_hasMore) {
      return;
    }
    _loadingMore = true;
    notifyListeners();

    try {
      final nextPage = _page + 1;
      final page = await _service.load(
        filter: _filter,
        sort: _sort,
        ascending: _ascending,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (page.isEmpty) {
        _hasMore = false;
      } else {
        _page = nextPage;
        final existing = _items.map((item) => item.id).toSet();
        _items.addAll(page.where((item) => !existing.contains(item.id)));
        _hasMore = page.length >= _pageSize;
      }
    } catch (_) {
      _hasMore = false;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> setFilter(GalleryFilter value) async {
    if (_filter == value) {
      return;
    }
    _filter = value;
    clearSelection();
    notifyListeners();
    await refresh();
  }

  Future<void> toggleMediaKinds({bool? images, bool? videos}) async {
    await setFilter(
      GalleryFilter(
        images: images ?? _filter.images,
        videos: videos ?? _filter.videos,
        favouritesOnly: _filter.favouritesOnly,
      ),
    );
  }

  Future<void> toggleFavouritesOnly() async {
    await setFilter(
      GalleryFilter(
        images: _filter.images,
        videos: _filter.videos,
        favouritesOnly: !_filter.favouritesOnly,
      ),
    );
  }

  Future<void> setSort(SortField value, {bool? ascending}) async {
    final nextAscending = ascending ?? _ascending;
    if (value == _sort && nextAscending == _ascending) {
      return;
    }
    _sort = value;
    _ascending = nextAscending;
    await refresh();
  }

  void setQuery(String value) {
    if (_query == value) {
      return;
    }
    _query = value;
    notifyListeners();
  }

  void toggleSelection(MediaItem item) {
    if (!_selectedIds.add(item.id)) {
      _selectedIds.remove(item.id);
    }
    notifyListeners();
  }

  void selectAllVisible() {
    for (final item in visibleItems) {
      if (item.kind.isConvertible) {
        _selectedIds.add(item.id);
      }
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedIds.isEmpty) {
      return;
    }
    _selectedIds.clear();
    notifyListeners();
  }

  /// Fills in details (file size, iCloud state) for one item, updating the list in place.
  Future<void> enrichItem(MediaItem item) async {
    final enriched = await _service.enrich(item);
    if (enriched == null) {
      return;
    }
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index >= 0) {
      _items[index] = enriched;
      notifyListeners();
    }
  }

  /// Resolves a local file path for every gallery item, so the conversion engines can read it.
  ///
  /// Returns the readable items plus the items that could not be materialised (for an honest
  /// "n items could not be read" message).
  Future<({List<MediaItem> ready, List<MediaItem> unavailable})>
  resolveForConversion(List<MediaItem> items) async {
    final ready = <MediaItem>[];
    final unavailable = <MediaItem>[];
    for (final item in items) {
      if (item.path != null && item.path!.isNotEmpty) {
        ready.add(item);
        continue;
      }
      final path = await _service.ensureLocalFile(item);
      if (path == null || path.isEmpty) {
        unavailable.add(item);
      } else {
        ready.add(item.copyWith(path: path));
      }
    }
    return (ready: ready, unavailable: unavailable);
  }

  Widget? thumbnail(
    MediaItem item, {
    required int extent,
    BoxFit fit = BoxFit.cover,
  }) => _service.thumbnail(item, extent: extent, fit: fit);

  /// A full-resolution provider for the viewer, or null when none can be produced.
  ImageProvider? previewOf(MediaItem item) {
    final fromLibrary = _service.preview(item);
    if (fromLibrary != null) {
      return fromLibrary;
    }
    final path = item.path;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return FileImage(File(path));
    }
    return null;
  }

  /// A local file path for playback/processing, downloading from iCloud if needed.
  Future<String?> localPathFor(MediaItem item) async {
    final existing = item.path;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    return _service.ensureLocalFile(item);
  }

  /// Deletes the given assets from the system library. Returns how many were deleted.
  Future<int> deleteItems(List<MediaItem> items) async {
    if (items.isEmpty) {
      return 0;
    }
    final ok = await _service.deleteMany(items);
    if (!ok) {
      return 0;
    }
    final ids = items.map((item) => item.id).toSet();
    _items.removeWhere((item) => ids.contains(item.id));
    _selectedIds.removeAll(ids);
    notifyListeners();
    return ids.length;
  }

  /// Sets the platform favourite flag where the OS supports it.
  Future<bool> toggleFavorite(MediaItem item) async {
    final updated = await _service.setFavorite(item, !item.isFavorite);
    if (!updated) {
      return false;
    }
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(isFavorite: !item.isFavorite);
      notifyListeners();
    }
    return true;
  }

  void clearCache() => _service.clearCache();

  void _pruneSelection() {
    final ids = _items.map((item) => item.id).toSet();
    _selectedIds.removeWhere((id) => !ids.contains(id));
  }
}
