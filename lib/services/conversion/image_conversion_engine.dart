import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/conversion/conversion_error.dart';
import '../../domain/conversion/conversion_request.dart';
import '../../domain/conversion/image_spec.dart';
import '../../domain/format/format_detector.dart';
import '../../domain/media/image_format.dart';
import '../platform/media_codec_bridge.dart';
import 'conversion_engine.dart';

/// Converts images using the shared pure-Dart codec pipeline, with the native bridge used only
/// for formats Dart cannot decode (HEIC/HEIF/AVIF and platform RAW).
///
/// The heavy work runs in an isolate so the UI stays responsive on large photos.
class ImageConversionEngine
    implements ConversionEngine<ImageConversionRequest> {
  ImageConversionEngine({MediaCodecBridge? bridge, this.maxMegapixels = 80})
    : _bridge = bridge ?? MediaCodecBridge();

  final MediaCodecBridge _bridge;
  final int maxMegapixels;

  @override
  Future<bool> canHandle(ImageConversionRequest request) async {
    final source = request.source.imageFormat;
    final capability = source.capabilityFor(_bridge.platform);
    final target = request.spec.outputFormat.capabilityFor(_bridge.platform);
    if (!capability.canDecode || !target.canEncode) {
      return false;
    }
    if (_requiresNativeDecode(source)) {
      return _bridge.supportsHeic();
    }
    return request.source.path != null;
  }

  static bool _requiresNativeDecode(ImageFormat format) =>
      format == ImageFormat.heic ||
      format == ImageFormat.heif ||
      format == ImageFormat.avif ||
      format == ImageFormat.dng;

  @override
  Future<ConversionOutcome> convert(
    ImageConversionRequest request, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final sourcePath = request.source.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      return const ConversionFailure(
        ConversionError(
          code: ConversionErrorCode.sourceMissing,
          message: 'The original file is no longer available.',
          isRecoverable: false,
        ),
      );
    }

    try {
      onProgress?.call(0.02, message: 'Preparing');
      token?.throwIfCancelled();

      final sourceFile = File(sourcePath);
      if (!sourceFile.existsSync()) {
        return const ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.sourceMissing,
            message: 'The original file was moved or deleted.',
            isRecoverable: false,
          ),
        );
      }

      final bytes = await sourceFile.readAsBytes();
      token?.throwIfCancelled();
      onProgress?.call(0.12, message: 'Reading image');

      final detected = FormatDetector.detect(
        Uint8List.fromList(
          bytes.sublist(0, bytes.length < 64 ? bytes.length : 64),
        ),
      );
      final sourceFormat =
          detected.isImage && detected.imageFormat != ImageFormat.unknown
          ? detected.imageFormat
          : request.source.imageFormat;

      Uint8List? rgba;
      int? rgbaWidth;
      int? rgbaHeight;
      if (_requiresNativeDecode(sourceFormat)) {
        onProgress?.call(0.2, message: 'Decoding with the device image engine');
        final decoded = await _bridge.decodeToRgba(
          sourcePath,
          maxMegapixels: maxMegapixels,
        );
        if (decoded == null) {
          return ConversionFailure(
            ConversionError.unsupportedInput(sourceFormat.label),
          );
        }
        rgba = decoded.pixels;
        rgbaWidth = decoded.width;
        rgbaHeight = decoded.height;
      }

      token?.throwIfCancelled();
      onProgress?.call(0.35, message: 'Converting');

      final outputPath = await _resolveOutputPath(request);
      final payload = <String, Object?>{
        'sourceBytes': bytes,
        'rgba': rgba,
        'rgbaWidth': rgbaWidth,
        'rgbaHeight': rgbaHeight,
        'spec': request.spec.toJson(),
        'outputPath': outputPath,
        'keepMetadata': request.metadataPolicy.keepsMetadata,
        'stripLocation': request.metadataPolicy.stripsLocation,
        'maxMegapixels': maxMegapixels,
      };

      final result = await Isolate.run<Map<String, Object?>>(
        () => _pipeline(payload),
      );
      token?.throwIfCancelled();

      if (result['error'] != null) {
        return ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.decodeFailed,
            message: 'The image could not be converted.',
            detail: result['error'] as String?,
          ),
        );
      }

      onProgress?.call(0.85, message: 'Verifying output');

      final outPath = result['outputPath'] as String?;
      if (outPath == null) {
        return const ConversionFailure(
          ConversionError(
            code: ConversionErrorCode.outputMissing,
            message: 'The conversion produced no file.',
            isRecoverable: false,
          ),
        );
      }

      final outFile = File(outPath);
      final outBytes = await outFile.length();
      final headerBytes = await _readHeader(outFile);
      final detectedOut = FormatDetector.detect(headerBytes);

      final problems = <ConversionError>[];
      if (!detectedOut.isImage) {
        problems.add(
          const ConversionError(
            code: ConversionErrorCode.outputWrongFormat,
            message: 'The converted file is not a valid image.',
          ),
        );
      } else if (detectedOut.imageFormat != request.spec.outputFormat &&
          !_formatsEquivalent(
            detectedOut.imageFormat,
            request.spec.outputFormat,
          )) {
        problems.add(
          ConversionError(
            code: ConversionErrorCode.outputWrongFormat,
            message: 'The converted image is not the requested format.',
            detail:
                'expected=${request.spec.outputFormat.id} got=${detectedOut.imageFormat.id}',
          ),
        );
      }

      final expectedW = result['width'] as int?;
      final expectedH = result['height'] as int?;
      if (problems.isNotEmpty) {
        // Clean up a failed output; never leave a broken file behind.
        if (outFile.existsSync()) {
          await outFile.delete();
        }
        return ConversionFailure(problems.first);
      }

      onProgress?.call(1.0, message: 'Done');
      return ConversionSuccess(
        outputPath: outPath,
        outputBytes: outBytes,
        sourceBytes: bytes.length,
        width: expectedW,
        height: expectedH,
      );
    } on ConversionCancelledException {
      return const ConversionFailure(ConversionError.cancelled);
    } on OutOfMemoryError {
      return const ConversionFailure(
        ConversionError(
          code: ConversionErrorCode.outOfMemory,
          message: 'The image is too large to process on this device.',
        ),
      );
    } catch (error) {
      return ConversionFailure(
        ConversionError(
          code: ConversionErrorCode.internal,
          message: 'The image could not be converted.',
          detail: error.runtimeType.toString(),
        ),
      );
    }
  }

  Future<Uint8List> _readHeader(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final readLength = length < 64 ? length : 64;
      return await raf.read(readLength);
    } finally {
      await raf.close();
    }
  }

  static bool _formatsEquivalent(ImageFormat a, ImageFormat b) {
    if (a == b) {
      return true;
    }
    return (a == ImageFormat.heic && b == ImageFormat.heif) ||
        (a == ImageFormat.heif && b == ImageFormat.heic);
  }

  Future<String> _resolveOutputPath(ImageConversionRequest request) async {
    final directory = request.outputDirectory ?? Directory.systemTemp.path;
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final baseName = request.naming.buildBaseName(
      sourceFileName: request.source.displayName ?? request.source.id,
      formatExtension: request.outputExtension,
      timestamp: DateTime.now(),
    );
    final fileName = request.naming.uniqueFileName(
      baseName: baseName,
      extension: request.outputExtension,
      isTaken: (candidate) =>
          File('$directory${Platform.pathSeparator}$candidate').existsSync(),
    );
    return '$directory${Platform.pathSeparator}$fileName';
  }
}

/// Runs entirely inside a worker isolate: decode (or wrap native RGBA) → transform → encode →
/// write. Returns a plain map so nothing Flutter-specific crosses the isolate boundary.
Map<String, Object?> _pipeline(Map<String, Object?> payload) {
  try {
    final spec = ImageConversionSpecDecoder.decode(
      payload['spec'] as Map<String, Object?>,
    );
    final rawBytes = payload['sourceBytes'] as Uint8List?;
    final rgba = payload['rgba'] as Uint8List?;
    final rgbaWidth = payload['rgbaWidth'] as int?;
    final rgbaHeight = payload['rgbaHeight'] as int?;
    final keepMetadata = payload['keepMetadata'] as bool? ?? true;
    final stripLocation = payload['stripLocation'] as bool? ?? false;

    img.Image? image;
    if (rgba != null && rgbaWidth != null && rgbaHeight != null) {
      image = img.Image.fromBytes(
        width: rgbaWidth,
        height: rgbaHeight,
        bytes: rgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
    } else if (rawBytes != null) {
      image = img.decodeImage(rawBytes);
    }

    if (image == null) {
      return <String, Object?>{'error': 'decodeFailed'};
    }

    // Capture the source metadata before any transform, which produces new images that do not
    // carry EXIF/ICC forward.
    final sourceExif = image.hasExif ? image.exif.clone() : null;
    final sourceIcc = image.iccProfile;

    // --- transform -----------------------------------------------------------
    image = _applyOrientation(image, spec);
    image = _applyResize(image, spec);
    if (spec.watermark != null && spec.watermark!.text.trim().isNotEmpty) {
      _applyWatermark(image, spec.watermark!);
    }

    // --- metadata ------------------------------------------------------------
    // "Remove all" really strips it; "Remove location" drops the GPS block only; "Keep all"
    // carries the source EXIF/ICC through where the output format can hold it.
    if (keepMetadata) {
      if (sourceExif != null) {
        image.exif = stripLocation ? _withoutGps(sourceExif) : sourceExif;
      }
      image.iccProfile = sourceIcc;
    } else {
      image.exif = img.ExifData();
      image.iccProfile = null;
    }

    // --- encode --------------------------------------------------------------
    final encoded = _encode(image, spec);
    if (encoded == null) {
      return <String, Object?>{'error': 'encodeFailed:${spec.outputFormat.id}'};
    }

    final outputPath = payload['outputPath'] as String;
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(encoded, flush: true);

    return <String, Object?>{
      'outputPath': outputPath,
      'bytes': encoded.length,
      'width': image.width,
      'height': image.height,
    };
  } catch (error) {
    return <String, Object?>{'error': '${error.runtimeType}: $error'};
  }
}

img.Image _applyOrientation(img.Image image, ImageConversionSpec spec) {
  var result = image;
  switch (spec.rotation) {
    case Rotation.clockwise90:
      result = img.copyRotate(result, angle: 90);
    case Rotation.degrees180:
      result = img.copyRotate(result, angle: 180);
    case Rotation.clockwise270:
      result = img.copyRotate(result, angle: 270);
    case Rotation.none:
      break;
  }
  switch (spec.flip) {
    case FlipAxis.horizontal:
      result = img.flipHorizontal(result);
    case FlipAxis.vertical:
      result = img.flipVertical(result);
    case FlipAxis.both:
      result = img.flipVertical(img.flipHorizontal(result));
    case FlipAxis.none:
      break;
  }
  return result;
}

img.Image _applyResize(img.Image image, ImageConversionSpec spec) {
  if (spec.resize.isNone) {
    return image;
  }
  final (width, height) = spec.resize.resolve(image.width, image.height);
  if (width == image.width && height == image.height) {
    return image;
  }
  return img.copyResize(
    image,
    width: width,
    height: height,
    interpolation: img.Interpolation.cubic,
  );
}

void _applyWatermark(img.Image image, WatermarkSpec watermark) {
  final shortEdge = image.width < image.height ? image.width : image.height;
  final fontSize = (shortEdge * watermark.fontSizeFraction).round().clamp(
    10,
    400,
  );
  final font = fontSize > 32 ? img.arial48 : img.arial24;
  final text = watermark.text;
  final textWidth = text.length * (fontSize * 0.6);
  final padding = (shortEdge * watermark.paddingFraction).round();
  final color = img.ColorRgba8(
    (watermark.colorValue >> 16) & 0xFF,
    (watermark.colorValue >> 8) & 0xFF,
    watermark.colorValue & 0xFF,
    (255 * watermark.opacity).round(),
  );
  final x = switch (watermark.position) {
    WatermarkPosition.topLeft || WatermarkPosition.bottomLeft => padding,
    WatermarkPosition.center => ((image.width - textWidth) / 2).round(),
    WatermarkPosition.topRight || WatermarkPosition.bottomRight =>
      (image.width - textWidth - padding).round(),
  };
  final y = switch (watermark.position) {
    WatermarkPosition.topLeft || WatermarkPosition.topRight => padding,
    WatermarkPosition.center => (image.height / 2).round(),
    WatermarkPosition.bottomLeft || WatermarkPosition.bottomRight =>
      (image.height - fontSize - padding).round(),
  };
  img.drawString(
    image,
    text,
    font: font,
    x: x < 0 ? 0 : x,
    y: y < 0 ? 0 : y,
    color: color,
  );
}

Uint8List? _encode(img.Image image, ImageConversionSpec spec) {
  switch (spec.outputFormat) {
    case ImageFormat.jpeg:
      // Flatten transparency onto white: JPEG has no alpha channel.
      final flattened = image.numChannels == 4
          ? _flattenOntoWhite(image)
          : image;
      if (image.hasExif) {
        flattened.exif = image.exif;
      }
      flattened.iccProfile = image.iccProfile;
      return img.encodeJpg(flattened, quality: spec.effectiveQuality);
    case ImageFormat.png:
      return img.encodePng(image, level: spec.pngCompressionLevel.clamp(0, 9));
    case ImageFormat.gif:
      return img.encodeGif(image);
    case ImageFormat.bmp:
      return img.encodeBmp(image);
    case ImageFormat.tiff:
      return img.encodeTiff(image);
    case ImageFormat.ico:
      return img.encodeIco(image);
    case ImageFormat.webp:
      return img.encodeWebP(
        image,
        quality: spec.effectiveQuality,
        lossless: spec.lossless,
      );
    case ImageFormat.heic:
    case ImageFormat.heif:
    case ImageFormat.avif:
    case ImageFormat.svg:
    case ImageFormat.jp2:
    case ImageFormat.dng:
    case ImageFormat.wbmp:
    case ImageFormat.unknown:
      return null;
  }
}

img.Image _flattenOntoWhite(img.Image image) {
  final output = img.Image(
    width: image.width,
    height: image.height,
    numChannels: 3,
  );
  img.fill(output, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(output, image);
  return output;
}

/// Returns a copy of [exif] with the GPS block removed, for the "Remove location" policy.
img.ExifData _withoutGps(img.ExifData exif) {
  final copy = exif.clone();
  final ifd0 = copy.imageIfd;
  ifd0.sub.directories.remove('gps');
  ifd0.data.remove(0x8825); // GPSInfoIFDPointer
  return copy;
}

/// Decodes the JSON produced by [ImageConversionSpec.toJson] inside the worker isolate.
abstract final class ImageConversionSpecDecoder {
  static ImageConversionSpec decode(Map<String, Object?> json) {
    return ImageConversionSpec(
      outputFormat: ImageFormat.fromId(
        json['outputFormat'] as String? ?? 'jpeg',
      ),
      quality: json['quality'] as int?,
      pngCompressionLevel: (json['pngCompressionLevel'] as num?)?.toInt() ?? 6,
      resize: json['resize'] == null
          ? const ResizeSpec.none()
          : ResizeSpec.fromJson(json['resize']! as Map<String, Object?>),
      rotation: Rotation.values.firstWhere(
        (r) => r.name == json['rotation'],
        orElse: () => Rotation.none,
      ),
      flip: FlipAxis.values.firstWhere(
        (f) => f.name == json['flip'],
        orElse: () => FlipAxis.none,
      ),
      keepMetadata: json['keepMetadata'] as bool? ?? true,
      stripLocation: json['stripLocation'] as bool? ?? false,
      keepAnimation: json['keepAnimation'] as bool? ?? true,
      lossless: json['lossless'] as bool? ?? false,
    );
  }
}
