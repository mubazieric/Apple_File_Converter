import '../media/image_format.dart';
import '../media/media_item.dart';
import '../media/video_format.dart';
import 'image_spec.dart';
import 'metadata_policy.dart';
import 'naming_policy.dart';

import 'video_spec.dart';

/// A request to convert one media item.
sealed class ConversionRequest {
  const ConversionRequest({
    required this.source,
    this.metadataPolicy = MetadataPolicy.stripLocation,
    this.naming = const NamingPolicy(),
    this.outputDirectory,
  });

  final MediaItem source;

  /// How metadata is treated in the output.
  final MetadataPolicy metadataPolicy;

  final NamingPolicy naming;

  /// Absolute directory to write into. When null the caller's default is used.
  final String? outputDirectory;

  /// The extension the output file will use.
  String get outputExtension;

  /// The output format label for summaries.
  String get outputLabel;

  /// Whether this request will actually re-encode (vs. remux/copy).
  bool get requiresEncoding;

  ConversionRequest copyWithOutputDirectory(String? directory);

  /// Serialises the request (source + spec + policies) for queue persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': this is VideoConversionRequest ? 'video' : 'image',
    'source': source.toJson(),
    'metadataPolicy': metadataPolicy.name,
    'naming': naming.toJson(),
    'outputDirectory': outputDirectory,
    'spec': switch (this) {
      final ImageConversionRequest request => request.spec.toJson(),
      final VideoConversionRequest request => request.spec.toJson(),
    },
  };

  static ConversionRequest fromJson(Map<String, Object?> json) {
    final source = MediaItem.fromJson(
      (json['source']! as Map).cast<String, Object?>(),
    );
    final namingJson = json['naming'];
    final naming = namingJson is Map
        ? NamingPolicy.fromJson(namingJson.cast<String, Object?>())
        : const NamingPolicy();
    final specJson =
        (json['spec'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final policy = MetadataPolicy.fromName(json['metadataPolicy'] as String?);
    final outputDirectory = json['outputDirectory'] as String?;

    if (json['type'] == 'video') {
      return VideoConversionRequest(
        source: source,
        spec: VideoConversionSpec.fromJson(specJson),
        metadataPolicy: policy,
        naming: naming,
        outputDirectory: outputDirectory,
      );
    }
    return ImageConversionRequest(
      source: source,
      spec: ImageConversionSpec.fromJson(specJson),
      metadataPolicy: policy,
      naming: naming,
      outputDirectory: outputDirectory,
    );
  }
}

class ImageConversionRequest extends ConversionRequest {
  const ImageConversionRequest({
    required super.source,
    required this.spec,
    super.metadataPolicy,
    super.naming,
    super.outputDirectory,
  });

  final ImageConversionSpec spec;

  ImageFormat get outputFormat => spec.outputFormat;

  @override
  String get outputExtension => spec.outputFormat.primaryExtension;

  @override
  String get outputLabel => spec.outputFormat.label;

  @override
  bool get requiresEncoding => true;

  @override
  ImageConversionRequest copyWithOutputDirectory(String? directory) =>
      ImageConversionRequest(
        source: source,
        spec: spec,
        metadataPolicy: metadataPolicy,
        naming: naming,
        outputDirectory: directory,
      );
}

class VideoConversionRequest extends ConversionRequest {
  const VideoConversionRequest({
    required super.source,
    required this.spec,
    super.metadataPolicy,
    super.naming,
    super.outputDirectory,
  });

  final VideoConversionSpec spec;

  VideoContainer get outputContainer => spec.container;

  @override
  String get outputExtension => spec.container.primaryExtension;

  @override
  String get outputLabel => spec.container.label;

  /// A pure remux does not re-encode, which is the distinction the product must never blur.
  @override
  bool get requiresEncoding => !spec.remuxOnly;

  @override
  VideoConversionRequest copyWithOutputDirectory(String? directory) =>
      VideoConversionRequest(
        source: source,
        spec: spec,
        metadataPolicy: metadataPolicy,
        naming: naming,
        outputDirectory: directory,
      );
}
