/// What happens to metadata (EXIF/ICC/GPS/dates) during a conversion.
enum MetadataPolicy {
  /// Keep everything we can carry over.
  preserve,

  /// Keep metadata but remove GPS/location (the privacy-friendly default for sharing).
  stripLocation,

  /// Write no metadata at all.
  stripAll;

  bool get keepsMetadata => this != MetadataPolicy.stripAll;
  bool get stripsLocation => this != MetadataPolicy.preserve;
  bool get stripsAll => this == MetadataPolicy.stripAll;

  static MetadataPolicy fromName(String? name) => switch (name) {
    'preserve' => MetadataPolicy.preserve,
    'stripAll' => MetadataPolicy.stripAll,
    _ => MetadataPolicy.stripLocation,
  };
}
