import '../conversion/metadata_policy.dart';
import '../conversion/naming_policy.dart';
import '../conversion/presets.dart';
import '../conversion/video_spec.dart';
import '../media/image_format.dart';
import '../media/video_format.dart';

/// Appearance preference (kept platform-neutral in the domain layer).
enum ThemePreference {
  system,
  light,
  dark;

  static ThemePreference fromName(String? name) => switch (name) {
    'light' => ThemePreference.light,
    'dark' => ThemePreference.dark,
    _ => ThemePreference.system,
  };
}

enum GalleryLayout {
  grid,
  list;

  static GalleryLayout fromName(String? name) =>
      name == 'list' ? GalleryLayout.list : GalleryLayout.grid;
}

/// Where converted files are written by default.
enum ExportDestination {
  /// The system photo library (Photos / MediaStore).
  gallery,

  /// The app's own exports folder, visible through the Files app / SAF.
  appFolder,

  /// A user-picked directory recorded in [AppSettings.customExportPath].
  customFolder;

  static ExportDestination fromName(String? name) => switch (name) {
    'appFolder' => ExportDestination.appFolder,
    'customFolder' => ExportDestination.customFolder,
    _ => ExportDestination.gallery,
  };
}

enum SortField {
  dateModified,
  dateCreated,
  name,
  size,
  format,
  duration;

  static SortField fromName(String? name) => values.firstWhere(
    (f) => f.name == name,
    orElse: () => SortField.dateModified,
  );
}

/// All user preferences, with documented defaults.
///
/// This type is immutable and serialised to a flat `Map<String, Object?>`; the repository is
/// responsible for validating every value on read so that a corrupted store degrades to the
/// defaults rather than crashing.
class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.system,
    this.defaultImageFormat = ImageFormat.jpeg,
    this.defaultImageQuality = 90,
    this.defaultImagePreset = ImagePreset.jpegDefault,
    this.defaultVideoContainer = VideoContainer.mp4,
    this.defaultVideoPreset = VideoPreset.maximumCompatibility,
    this.defaultVideoQuality = VideoQuality.balanced,
    this.defaultResolution = ResolutionPreset.original,
    this.metadataPolicy = MetadataPolicy.stripLocation,
    this.namingTemplate = NamingPolicy.defaultTemplate,
    this.exportDestination = ExportDestination.gallery,
    this.customExportPath,
    this.batchConcurrency,
    this.confirmBeforeDelete = true,
    this.galleryLayout = GalleryLayout.grid,
    this.galleryGridColumns = 3,
    this.gallerySort = SortField.dateModified,
    this.gallerySortAscending = false,
    this.languageCode = 'en',
    this.adsConsentDecided = false,
  });

  final ThemePreference theme;

  final ImageFormat defaultImageFormat;
  final int defaultImageQuality;
  final ImagePreset defaultImagePreset;

  final VideoContainer defaultVideoContainer;
  final VideoPreset defaultVideoPreset;
  final VideoQuality defaultVideoQuality;
  final ResolutionPreset defaultResolution;

  final MetadataPolicy metadataPolicy;
  final String namingTemplate;

  final ExportDestination exportDestination;
  final String? customExportPath;

  /// null = derive from the device (see the coordinator).
  final int? batchConcurrency;

  final bool confirmBeforeDelete;

  final GalleryLayout galleryLayout;
  final int galleryGridColumns;
  final SortField gallerySort;
  final bool gallerySortAscending;

  final String languageCode;

  /// Whether the user has completed the consent flow at least once.
  final bool adsConsentDecided;

  /// Hardware-aware default concurrency when the user has not overridden it.
  int effectiveConcurrency(int suggested) =>
      (batchConcurrency ?? suggested).clamp(1, 8);

  AppSettings copyWith({
    ThemePreference? theme,
    ImageFormat? defaultImageFormat,
    int? defaultImageQuality,
    ImagePreset? defaultImagePreset,
    VideoContainer? defaultVideoContainer,
    VideoPreset? defaultVideoPreset,
    VideoQuality? defaultVideoQuality,
    ResolutionPreset? defaultResolution,
    MetadataPolicy? metadataPolicy,
    String? namingTemplate,
    ExportDestination? exportDestination,
    String? customExportPath,
    bool clearCustomExportPath = false,
    int? batchConcurrency,
    bool clearBatchConcurrency = false,
    bool? confirmBeforeDelete,
    GalleryLayout? galleryLayout,
    int? galleryGridColumns,
    SortField? gallerySort,
    bool? gallerySortAscending,
    String? languageCode,
    bool? adsConsentDecided,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      defaultImageFormat: defaultImageFormat ?? this.defaultImageFormat,
      defaultImageQuality: defaultImageQuality ?? this.defaultImageQuality,
      defaultImagePreset: defaultImagePreset ?? this.defaultImagePreset,
      defaultVideoContainer:
          defaultVideoContainer ?? this.defaultVideoContainer,
      defaultVideoPreset: defaultVideoPreset ?? this.defaultVideoPreset,
      defaultVideoQuality: defaultVideoQuality ?? this.defaultVideoQuality,
      defaultResolution: defaultResolution ?? this.defaultResolution,
      metadataPolicy: metadataPolicy ?? this.metadataPolicy,
      namingTemplate: namingTemplate ?? this.namingTemplate,
      exportDestination: exportDestination ?? this.exportDestination,
      customExportPath: clearCustomExportPath
          ? null
          : (customExportPath ?? this.customExportPath),
      batchConcurrency: clearBatchConcurrency
          ? null
          : (batchConcurrency ?? this.batchConcurrency),
      confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
      galleryLayout: galleryLayout ?? this.galleryLayout,
      galleryGridColumns: galleryGridColumns ?? this.galleryGridColumns,
      gallerySort: gallerySort ?? this.gallerySort,
      gallerySortAscending: gallerySortAscending ?? this.gallerySortAscending,
      languageCode: languageCode ?? this.languageCode,
      adsConsentDecided: adsConsentDecided ?? this.adsConsentDecided,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'theme': theme.name,
    'defaultImageFormat': defaultImageFormat.id,
    'defaultImageQuality': defaultImageQuality,
    'defaultImagePreset': defaultImagePreset.id,
    'defaultVideoContainer': defaultVideoContainer.id,
    'defaultVideoPreset': defaultVideoPreset.id,
    'defaultVideoQuality': defaultVideoQuality.name,
    'defaultResolution': defaultResolution.name,
    'metadataPolicy': metadataPolicy.name,
    'namingTemplate': namingTemplate,
    'exportDestination': exportDestination.name,
    'customExportPath': customExportPath,
    'batchConcurrency': batchConcurrency,
    'confirmBeforeDelete': confirmBeforeDelete,
    'galleryLayout': galleryLayout.name,
    'galleryGridColumns': galleryGridColumns,
    'gallerySort': gallerySort.name,
    'gallerySortAscending': gallerySortAscending,
    'languageCode': languageCode,
    'adsConsentDecided': adsConsentDecided,
  };

  /// Builds settings from a stored map, substituting defaults for anything missing or invalid.
  static AppSettings fromMap(Map<String, Object?> map) {
    const fallback = AppSettings();
    return AppSettings(
      theme: ThemePreference.fromName(map['theme'] as String?),
      defaultImageFormat: _safeImageFormat(
        map['defaultImageFormat'] as String?,
      ),
      defaultImageQuality: _clampInt(
        map['defaultImageQuality'],
        1,
        100,
        fallback.defaultImageQuality,
      ),
      defaultImagePreset: ImagePreset.fromId(
        map['defaultImagePreset'] as String? ?? '',
      ),
      defaultVideoContainer: _safeContainer(
        map['defaultVideoContainer'] as String?,
      ),
      defaultVideoPreset: VideoPreset.fromId(
        map['defaultVideoPreset'] as String? ?? '',
      ),
      defaultVideoQuality: VideoQuality.values.firstWhere(
        (q) => q.name == map['defaultVideoQuality'],
        orElse: () => fallback.defaultVideoQuality,
      ),
      defaultResolution: ResolutionPreset.values.firstWhere(
        (r) => r.name == map['defaultResolution'],
        orElse: () => fallback.defaultResolution,
      ),
      metadataPolicy: MetadataPolicy.fromName(map['metadataPolicy'] as String?),
      namingTemplate:
          (map['namingTemplate'] as String?)?.trim().isNotEmpty == true
          ? map['namingTemplate']! as String
          : fallback.namingTemplate,
      exportDestination: ExportDestination.fromName(
        map['exportDestination'] as String?,
      ),
      customExportPath: map['customExportPath'] as String?,
      batchConcurrency: _concurrencyOrNull(map['batchConcurrency']),
      confirmBeforeDelete:
          map['confirmBeforeDelete'] as bool? ?? fallback.confirmBeforeDelete,
      galleryLayout: GalleryLayout.fromName(map['galleryLayout'] as String?),
      galleryGridColumns: _clampInt(
        map['galleryGridColumns'],
        2,
        6,
        fallback.galleryGridColumns,
      ),
      gallerySort: SortField.fromName(map['gallerySort'] as String?),
      gallerySortAscending:
          map['gallerySortAscending'] as bool? ?? fallback.gallerySortAscending,
      languageCode: (map['languageCode'] as String?) ?? fallback.languageCode,
      adsConsentDecided:
          map['adsConsentDecided'] as bool? ?? fallback.adsConsentDecided,
    );
  }

  static ImageFormat _safeImageFormat(String? id) {
    final format = ImageFormat.fromId(id ?? 'jpeg');
    // Only offer formats we can actually encode as a default.
    return format == ImageFormat.unknown ? ImageFormat.jpeg : format;
  }

  static VideoContainer _safeContainer(String? id) {
    final container = VideoContainer.fromId(id ?? 'mp4');
    return container == VideoContainer.unknown ? VideoContainer.mp4 : container;
  }

  static int _clampInt(Object? value, int min, int max, int fallback) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value);
    }
    if (parsed == null) {
      return fallback;
    }
    return parsed.clamp(min, max);
  }

  /// Batch concurrency is optional: an absent or unparseable value means "use the device
  /// suggestion", which we represent as null rather than inventing a number.
  static int? _concurrencyOrNull(Object? value) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value);
    }
    return parsed?.clamp(1, 8);
  }

  /// A safe default naming policy derived from settings.
  NamingPolicy get namingPolicy => NamingPolicy(template: namingTemplate);
}
