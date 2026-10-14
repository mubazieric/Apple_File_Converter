import 'image_format.dart';
import 'media_kind.dart';
import 'video_format.dart';

/// Whether the underlying bytes are available right now.
///
/// On iOS an asset may exist but live only in iCloud; on Android a MediaStore row may point at
/// a file the user deleted. The gallery must communicate this rather than silently failing.
enum MediaAvailability {
  /// Locally available and readable.
  local,

  /// Known to the library but not downloaded (e.g. iCloud-only). A fetch may be required.
  remote,

  /// The record exists but the bytes are gone (deleted outside the app).
  missing,
}

/// A single media asset, abstracted away from whether it comes from the device gallery
/// (`photo_manager` asset id) or from a file we produced (absolute path).
///
/// This is a domain entity: no Flutter, plugin or platform types leak in.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    this.displayName,
    this.path,
    this.mimeType,
    this.sizeBytes,
    this.width,
    this.height,
    this.duration,
    this.createdAt,
    this.modifiedAt,
    this.imageFormat = ImageFormat.unknown,
    this.videoContainer = VideoContainer.unknown,
    this.availability = MediaAvailability.local,
    this.isFavorite = false,
    this.isConversionOutput = false,
    this.sourceItemId,
    this.relativePath,
  });

  /// Stable identifier: the platform asset id, or the absolute file path for our own outputs.
  final String id;

  final MediaKind kind;
  final String? displayName;

  /// Absolute local path when the bytes are available locally.
  final String? path;

  final String? mimeType;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final Duration? duration;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  final ImageFormat imageFormat;
  final VideoContainer videoContainer;

  final MediaAvailability availability;

  /// App-managed favourite flag (we do not write this into the system gallery).
  final bool isFavorite;

  /// True when this item was produced by a conversion in this app.
  final bool isConversionOutput;

  /// For conversion outputs, the id of the source item, when known.
  final String? sourceItemId;

  /// Album/folder name for display, when known.
  final String? relativePath;

  bool get isImage => kind.isImage;
  bool get isVideo => kind.isVideo;

  bool get isAvailableLocally =>
      availability == MediaAvailability.local &&
      path != null &&
      path!.isNotEmpty;

  /// Human-readable resolution, e.g. `4032 × 3024`.
  String? get resolutionLabel =>
      (width != null && height != null && width! > 0 && height! > 0)
      ? '$width × $height'
      : null;

  /// Megapixels, used to bound memory in the image pipeline.
  double? get megapixels =>
      (width != null && height != null) ? (width! * height!) / 1000000.0 : null;

  String get formatLabel => switch (kind) {
    MediaKind.image => imageFormat.label,
    MediaKind.video => videoContainer.label,
    _ => 'Unknown',
  };

  MediaItem copyWith({
    String? id,
    MediaKind? kind,
    String? displayName,
    String? path,
    String? mimeType,
    int? sizeBytes,
    int? width,
    int? height,
    Duration? duration,
    DateTime? createdAt,
    DateTime? modifiedAt,
    ImageFormat? imageFormat,
    VideoContainer? videoContainer,
    MediaAvailability? availability,
    bool? isFavorite,
    bool? isConversionOutput,
    String? sourceItemId,
    String? relativePath,
  }) {
    return MediaItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      path: path ?? this.path,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      imageFormat: imageFormat ?? this.imageFormat,
      videoContainer: videoContainer ?? this.videoContainer,
      availability: availability ?? this.availability,
      isFavorite: isFavorite ?? this.isFavorite,
      isConversionOutput: isConversionOutput ?? this.isConversionOutput,
      sourceItemId: sourceItemId ?? this.sourceItemId,
      relativePath: relativePath ?? this.relativePath,
    );
  }

  /// Serialises to a JSON-safe map so a queued conversion can survive an app restart.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'displayName': displayName,
    'path': path,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'width': width,
    'height': height,
    'durationMs': duration?.inMilliseconds,
    'createdAtMs': createdAt?.millisecondsSinceEpoch,
    'modifiedAtMs': modifiedAt?.millisecondsSinceEpoch,
    'imageFormat': imageFormat.id,
    'videoContainer': videoContainer.id,
    'availability': availability.name,
    'isFavorite': isFavorite,
    'isConversionOutput': isConversionOutput,
    'sourceItemId': sourceItemId,
    'relativePath': relativePath,
  };

  static MediaItem fromJson(Map<String, Object?> json) {
    return MediaItem(
      id: json['id']! as String,
      kind: MediaKind.fromName(json['kind'] as String?),
      displayName: json['displayName'] as String?,
      path: json['path'] as String?,
      mimeType: json['mimeType'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      duration: _millis(json['durationMs']),
      createdAt: _dateTime(json['createdAtMs']),
      modifiedAt: _dateTime(json['modifiedAtMs']),
      imageFormat: ImageFormat.fromId(json['imageFormat'] as String? ?? ''),
      videoContainer: VideoContainer.fromId(
        json['videoContainer'] as String? ?? '',
      ),
      availability: _availability(json['availability'] as String?),
      isFavorite: json['isFavorite'] as bool? ?? false,
      isConversionOutput: json['isConversionOutput'] as bool? ?? false,
      sourceItemId: json['sourceItemId'] as String?,
      relativePath: json['relativePath'] as String?,
    );
  }

  static Duration? _millis(Object? value) =>
      value is num ? Duration(milliseconds: value.toInt()) : null;

  static DateTime? _dateTime(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

  static MediaAvailability _availability(String? name) => switch (name) {
    'remote' => MediaAvailability.remote,
    'missing' => MediaAvailability.missing,
    _ => MediaAvailability.local,
  };

  @override
  bool operator ==(Object other) =>
      other is MediaItem &&
      other.id == id &&
      other.kind == kind &&
      other.path == path &&
      other.sizeBytes == sizeBytes &&
      other.width == width &&
      other.height == height &&
      other.duration == duration &&
      other.isFavorite == isFavorite &&
      other.availability == availability;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    path,
    sizeBytes,
    width,
    height,
    duration,
    isFavorite,
    availability,
  );

  @override
  String toString() =>
      'MediaItem($id, $kind, $formatLabel, ${sizeBytes ?? 0}B)';
}
