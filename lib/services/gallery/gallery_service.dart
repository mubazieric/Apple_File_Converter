import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../domain/format/format_detector.dart';
import '../../domain/media/image_format.dart';
import '../../domain/media/media_item.dart';
import '../../domain/media/media_kind.dart';
import '../../domain/media/video_format.dart';
import '../../domain/settings/app_settings.dart';

/// The user's answer to the photo-library permission prompt.
enum GalleryPermission {
  granted,
  limited,
  denied,
  restricted,
  notDetermined;

  bool get isUsable => this == GalleryPermission.granted || this == limited;
}

/// What the gallery should contain.
class GalleryFilter {
  const GalleryFilter({
    this.images = true,
    this.videos = true,
    this.favouritesOnly = false,
  });

  final bool images;
  final bool videos;
  final bool favouritesOnly;

  bool get isEmpty => !images && !videos;
  bool get isEverything => images && videos && !favouritesOnly;

  RequestType get requestType {
    if (images && videos) {
      return RequestType.common;
    }
    if (images) {
      return RequestType.image;
    }
    if (videos) {
      return RequestType.video;
    }
    return RequestType.common;
  }

  @override
  bool operator ==(Object other) =>
      other is GalleryFilter &&
      other.images == images &&
      other.videos == videos &&
      other.favouritesOnly == favouritesOnly;

  @override
  int get hashCode => Object.hash(images, videos, favouritesOnly);

  @override
  String toString() =>
      'GalleryFilter(images: $images, videos: $videos, favourites: $favouritesOnly)';
}

/// Read/write access to the device photo library.
///
/// The interface keeps `photo_manager` types out of the controllers and UI, and lets the
/// gallery be exercised in tests with a fake.
abstract interface class GalleryService {
  /// False on platforms without a system photo library (desktop/tests).
  bool get isSupported;

  Future<GalleryPermission> permission();
  Future<GalleryPermission> requestPermission();

  /// Opens the iOS "limited library" picker. No-op elsewhere.
  Future<void> presentLimited();

  Future<int> count(GalleryFilter filter);

  /// Loads one page of assets, most-recent-first by default.
  ///
  /// [sort] is applied server-side where the platform supports it (dates) and client-side
  /// otherwise (name, size, format, duration) — see the known-limitations doc.
  Future<List<MediaItem>> load({
    required GalleryFilter filter,
    required SortField sort,
    required bool ascending,
    required int page,
    int pageSize,
  });

  /// Fills in details that are expensive to fetch for a whole page (file size, iCloud state).
  Future<MediaItem?> enrich(MediaItem item);

  /// Downloads/returns a local file path for a library item, or null when unavailable.
  Future<String?> ensureLocalFile(MediaItem item);

  Future<MediaItem?> saveImage(
    String path, {
    required String filename,
    String? albumName,
  });

  Future<MediaItem?> saveVideo(
    String path, {
    required String filename,
    String? albumName,
  });

  /// Deletes assets from the system library, where the platform allows it.
  Future<bool> deleteMany(List<MediaItem> items);

  Future<bool> setFavorite(MediaItem item, bool value);

  /// A thumbnail widget for grids and viewers.
  Widget thumbnail(MediaItem item, {required int extent, BoxFit fit});

  /// A full-resolution provider for the image viewer, or null when unavailable.
  ImageProvider? preview(MediaItem item);

  void clearCache();
}

/// The real implementation, backed by `photo_manager` (MediaStore / Photos).
class PhotoManagerGalleryService implements GalleryService {
  /// Asset ids are opaque; we keep the recently-loaded entities so thumbnail/viewer requests
  /// do not need an extra round trip.
  final Map<String, AssetEntity> _cache = <String, AssetEntity>{};

  @override
  bool get isSupported => true;

  @override
  Future<GalleryPermission> permission() async {
    try {
      return _mapPermission(
        await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption(),
        ),
      );
    } catch (_) {
      return GalleryPermission.notDetermined;
    }
  }

  @override
  Future<GalleryPermission> requestPermission() async {
    try {
      return _mapPermission(await PhotoManager.requestPermissionExtend());
    } catch (_) {
      return GalleryPermission.denied;
    }
  }

  @override
  Future<void> presentLimited() async {
    try {
      await PhotoManager.presentLimited();
    } catch (_) {
      // Not supported on this platform/OS version.
    }
  }

  @override
  Future<int> count(GalleryFilter filter) async {
    final path = await _allAlbum(filter);
    if (path == null) {
      return 0;
    }
    try {
      return await path.assetCountAsync;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<List<MediaItem>> load({
    required GalleryFilter filter,
    required SortField sort,
    required bool ascending,
    required int page,
    int pageSize = 120,
  }) async {
    if (filter.isEmpty) {
      return const <MediaItem>[];
    }
    final path = await _allAlbum(filter, sort: sort, ascending: ascending);
    if (path == null) {
      return const <MediaItem>[];
    }
    try {
      final assets = await path.getAssetListPaged(page: page, size: pageSize);
      for (final asset in assets) {
        _cache[asset.id] = asset;
      }
      var items = assets
          .map(_toMediaItem)
          .where((item) => !filter.favouritesOnly || item.isFavorite)
          .toList(growable: true);
      items = _applyClientSort(items, sort, ascending);
      return List<MediaItem>.unmodifiable(items);
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  @override
  Future<MediaItem?> enrich(MediaItem item) async {
    final asset = _cache[item.id];
    if (asset == null) {
      return null;
    }
    int? size;
    try {
      size = await asset.fileSize;
    } catch (_) {
      size = null;
    }
    var availability = item.availability;
    try {
      final local = await asset.isLocallyAvailable(isOrigin: true);
      availability = local ? MediaAvailability.local : MediaAvailability.remote;
    } catch (_) {
      availability = item.availability;
    }
    return item.copyWith(sizeBytes: size, availability: availability);
  }

  @override
  Future<String?> ensureLocalFile(MediaItem item) async {
    final asset = _cache[item.id] ?? await AssetEntity.fromId(item.id);
    if (asset == null) {
      return item.path;
    }
    _cache[item.id] = asset;
    try {
      final file = await asset.originFile;
      return file?.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<MediaItem?> saveImage(
    String path, {
    required String filename,
    String? albumName,
  }) async {
    try {
      final asset = await PhotoManager.editor.saveImageWithPath(
        path,
        title: _titleWithoutExtension(filename),
        relativePath: albumName,
      );
      _cache[asset.id] = asset;
      return _toMediaItem(asset).copyWith(path: path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<MediaItem?> saveVideo(
    String path, {
    required String filename,
    String? albumName,
  }) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      final asset = await PhotoManager.editor.saveVideo(
        file,
        title: _titleWithoutExtension(filename),
        relativePath: albumName,
      );
      _cache[asset.id] = asset;
      return _toMediaItem(asset).copyWith(path: path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> deleteMany(List<MediaItem> items) async {
    if (items.isEmpty) {
      return true;
    }
    try {
      await PhotoManager.editor.deleteWithIds(
        items.map((i) => i.id).toList(growable: false),
      );
      for (final item in items) {
        _cache.remove(item.id);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setFavorite(MediaItem item, bool value) async {
    final asset = _cache[item.id] ?? await AssetEntity.fromId(item.id);
    if (asset == null) {
      return false;
    }
    try {
      final updated = await PhotoManager.editor.darwin.favoriteAsset(
        entity: asset,
        favorite: value,
      );
      _cache[updated.id] = updated;
      return true;
    } catch (_) {
      // Not Darwin, or the platform rejected it. Try the Android editor.
      try {
        final updated = await PhotoManager.editor.android.favoriteAsset(
          entity: asset,
          favorite: value,
        );
        _cache[updated.id] = updated;
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  @override
  Widget thumbnail(
    MediaItem item, {
    required int extent,
    BoxFit fit = BoxFit.cover,
  }) {
    final asset = _cache[item.id];
    if (asset == null) {
      return const SizedBox.shrink();
    }
    return AssetEntityImage(
      asset,
      isOriginal: false,
      thumbnailSize: ThumbnailSize.square(extent),
      fit: fit,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
    );
  }

  @override
  ImageProvider? preview(MediaItem item) {
    final asset = _cache[item.id];
    if (asset == null) {
      return null;
    }
    return AssetEntityImageProvider(asset, isOriginal: true);
  }

  @override
  void clearCache() => _cache.clear();

  Future<AssetPathEntity?> _allAlbum(
    GalleryFilter filter, {
    SortField sort = SortField.dateModified,
    bool ascending = false,
  }) async {
    try {
      final albums = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: filter.requestType,
        filterOption: _optionGroup(sort, ascending),
      );
      if (albums.isEmpty) {
        return null;
      }
      return albums.first;
    } catch (_) {
      return null;
    }
  }

  static FilterOptionGroup _optionGroup(SortField sort, bool ascending) {
    final type = sort == SortField.dateCreated
        ? OrderOptionType.createDate
        : OrderOptionType.updateDate;
    return FilterOptionGroup(
      orders: <OrderOption>[OrderOption(type: type, asc: ascending)],
      createTimeCond: DateTimeCond.def(),
      updateTimeCond: DateTimeCond.def(),
    );
  }

  /// Name/size/format/duration cannot be sorted by the platform query, so the loaded page is
  /// re-ordered in Dart. Date sorting is handled by the query above and is left untouched here.
  static List<MediaItem> _applyClientSort(
    List<MediaItem> items,
    SortField sort,
    bool ascending,
  ) {
    int compare(MediaItem a, MediaItem b) {
      int result;
      switch (sort) {
        case SortField.name:
          result = (a.displayName ?? a.id).toLowerCase().compareTo(
            (b.displayName ?? b.id).toLowerCase(),
          );
        case SortField.size:
          result = (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0);
        case SortField.format:
          result = a.formatLabel.compareTo(b.formatLabel);
        case SortField.duration:
          result = (a.duration ?? Duration.zero).compareTo(
            b.duration ?? Duration.zero,
          );
        case SortField.dateCreated:
          result = (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          );
        case SortField.dateModified:
          result = (a.modifiedAt ?? DateTime(0)).compareTo(
            b.modifiedAt ?? DateTime(0),
          );
      }
      return ascending ? result : -result;
    }

    return List<MediaItem>.of(items)..sort(compare);
  }

  static String _titleWithoutExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }

  static GalleryPermission _mapPermission(PermissionState state) =>
      switch (state) {
        PermissionState.authorized => GalleryPermission.granted,
        PermissionState.limited => GalleryPermission.limited,
        PermissionState.denied => GalleryPermission.denied,
        PermissionState.restricted => GalleryPermission.restricted,
        PermissionState.notDetermined => GalleryPermission.notDetermined,
      };

  static MediaItem _toMediaItem(AssetEntity asset) {
    final kind = switch (asset.type) {
      AssetType.image => MediaKind.image,
      AssetType.video => MediaKind.video,
      AssetType.audio => MediaKind.audio,
      AssetType.other => MediaKind.unknown,
    };
    final title = asset.title;
    final displayName = (title != null && title.trim().isNotEmpty)
        ? title
        : _fallbackName(asset.id, kind);

    final extension = _extensionOf(displayName);
    var detected = FormatDetector.fromExtension(extension);
    if (!detected.isKnown) {
      final mime = asset.mimeType;
      if (mime != null) {
        final image = ImageFormat.fromMimeType(mime);
        if (image != ImageFormat.unknown) {
          detected = DetectedFormat(
            kind: MediaKind.image,
            imageFormat: image,
            confidence: DetectionConfidence.tentative,
          );
        } else {
          for (final container in VideoContainer.values) {
            if (container.mimeType == mime) {
              detected = DetectedFormat(
                kind: MediaKind.video,
                videoContainer: container,
              );
              break;
            }
          }
        }
      }
    }

    return MediaItem(
      id: asset.id,
      kind: kind,
      displayName: displayName,
      mimeType: asset.mimeType,
      width: asset.orientatedWidth > 0 ? asset.orientatedWidth : null,
      height: asset.orientatedHeight > 0 ? asset.orientatedHeight : null,
      duration: kind.isVideo ? asset.videoDuration : null,
      createdAt: asset.createDateTime,
      modifiedAt: asset.modifiedDateTime,
      imageFormat: detected.isImage
          ? detected.imageFormat
          : ImageFormat.unknown,
      videoContainer: detected.isVideo
          ? detected.videoContainer
          : VideoContainer.unknown,
      availability: MediaAvailability.local,
      isFavorite: asset.isFavorite,
      relativePath: asset.relativePath,
    );
  }

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1);
  }

  static String _fallbackName(String id, MediaKind kind) {
    final suffix = id.length > 8 ? id.substring(id.length - 8) : id;
    return switch (kind) {
      MediaKind.video => 'VID_$suffix.mp4',
      MediaKind.audio => 'AUD_$suffix.m4a',
      _ => 'IMG_$suffix.jpg',
    };
  }
}

/// Used on desktop and in tests where there is no system photo library.
class UnsupportedGalleryService implements GalleryService {
  const UnsupportedGalleryService();

  @override
  bool get isSupported => false;

  @override
  Future<GalleryPermission> permission() async =>
      GalleryPermission.notDetermined;

  @override
  Future<GalleryPermission> requestPermission() async =>
      GalleryPermission.denied;

  @override
  Future<void> presentLimited() async {}

  @override
  Future<int> count(GalleryFilter filter) async => 0;

  @override
  Future<List<MediaItem>> load({
    required GalleryFilter filter,
    required SortField sort,
    required bool ascending,
    required int page,
    int pageSize = 120,
  }) async => const <MediaItem>[];

  @override
  Future<MediaItem?> enrich(MediaItem item) async => item;

  @override
  Future<String?> ensureLocalFile(MediaItem item) async => item.path;

  @override
  Future<MediaItem?> saveImage(
    String path, {
    required String filename,
    String? albumName,
  }) async => null;

  @override
  Future<MediaItem?> saveVideo(
    String path, {
    required String filename,
    String? albumName,
  }) async => null;

  @override
  Future<bool> deleteMany(List<MediaItem> items) async => false;

  @override
  Future<bool> setFavorite(MediaItem item, bool value) async => false;

  @override
  Widget thumbnail(
    MediaItem item, {
    required int extent,
    BoxFit fit = BoxFit.cover,
  }) => const SizedBox.shrink();

  @override
  ImageProvider? preview(MediaItem item) => null;

  @override
  void clearCache() {}
}
