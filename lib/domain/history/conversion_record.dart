import '../media/media_kind.dart';

/// A single completed (or failed) conversion, as shown in "Conversion history".
///
/// Deliberately stores only lightweight metadata and paths — never media bytes and never a
/// full copy of the source. This keeps the history database tiny and makes it safe to clear.
class ConversionRecord {
  const ConversionRecord({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.outputExtension,
    required this.finishedAt,
    this.sourcePath,
    this.outputPath,
    this.sourceBytes,
    this.outputBytes,
    this.wasRemux = false,
    this.success = true,
    this.errorMessage,
    this.exportedToGallery = false,
  });

  final String id;
  final String displayName;
  final MediaKind kind;
  final String outputExtension;
  final DateTime finishedAt;
  final String? sourcePath;
  final String? outputPath;
  final int? sourceBytes;
  final int? outputBytes;

  /// True when streams were copied rather than re-encoded.
  final bool wasRemux;

  final bool success;
  final String? errorMessage;

  /// True when the output was also written into the system photo library.
  final bool exportedToGallery;

  /// Positive when the output is smaller than the source.
  int? get bytesSaved {
    final source = sourceBytes;
    final output = outputBytes;
    if (source == null || output == null) {
      return null;
    }
    return source - output;
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'display_name': displayName,
    'kind': kind.name,
    'output_extension': outputExtension,
    'finished_at': finishedAt.millisecondsSinceEpoch,
    'source_path': sourcePath,
    'output_path': outputPath,
    'source_bytes': sourceBytes,
    'output_bytes': outputBytes,
    'was_remux': wasRemux ? 1 : 0,
    'success': success ? 1 : 0,
    'error_message': errorMessage,
    'exported_to_gallery': exportedToGallery ? 1 : 0,
  };

  static ConversionRecord fromMap(Map<String, Object?> map) {
    return ConversionRecord(
      id: map['id']! as String,
      displayName: (map['display_name'] as String?) ?? 'Converted file',
      kind: MediaKind.fromName(map['kind'] as String?),
      outputExtension: (map['output_extension'] as String?) ?? '',
      finishedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['finished_at'] as num?)?.toInt() ?? 0,
      ),
      sourcePath: map['source_path'] as String?,
      outputPath: map['output_path'] as String?,
      sourceBytes: (map['source_bytes'] as num?)?.toInt(),
      outputBytes: (map['output_bytes'] as num?)?.toInt(),
      wasRemux: ((map['was_remux'] as num?)?.toInt() ?? 0) == 1,
      success: ((map['success'] as num?)?.toInt() ?? 1) == 1,
      errorMessage: map['error_message'] as String?,
      exportedToGallery:
          ((map['exported_to_gallery'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}
