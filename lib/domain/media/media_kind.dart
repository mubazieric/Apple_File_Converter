/// The broad classification of a media asset.
///
/// Kept deliberately small: the *format* (`ImageFormat` / `VideoContainer`) carries the
/// detail, while the kind drives UI affordances and engine routing.
enum MediaKind {
  image,
  video,
  audio,
  unknown;

  bool get isImage => this == MediaKind.image;
  bool get isVideo => this == MediaKind.video;
  bool get isAudio => this == MediaKind.audio;

  /// Video and image assets can be processed by the conversion engine today.
  bool get isConvertible => isImage || isVideo;

  static MediaKind fromName(String? value) {
    return switch (value?.toLowerCase()) {
      'image' || 'photo' || 'picture' => MediaKind.image,
      'video' || 'movie' => MediaKind.video,
      'audio' || 'sound' || 'music' => MediaKind.audio,
      _ => MediaKind.unknown,
    };
  }
}
