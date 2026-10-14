import 'package:flutter/services.dart';

import '../../domain/media/capability.dart';
import '../../domain/media/image_format.dart';
import '../../domain/media/video_format.dart';
import 'platform_info.dart';

/// Raw pixels decoded by the native image stack.
class DecodedPixels {
  const DecodedPixels({
    required this.pixels,
    required this.width,
    required this.height,
    this.orientationDegrees = 0,
  });

  /// RGBA8888, tightly packed, length == width * height * 4.
  final Uint8List pixels;
  final int width;
  final int height;

  /// EXIF orientation already applied by the native decoder, for diagnostics only.
  final int orientationDegrees;

  int get megapixels => (width * height) ~/ 1000000;
}

/// Lightweight image metadata from the native stack (no full decode).
class NativeImageInfo {
  const NativeImageInfo({
    required this.width,
    required this.height,
    required this.format,
    this.hasAlpha = false,
    this.orientationDegrees = 0,
  });

  final int width;
  final int height;
  final ImageFormat format;
  final bool hasAlpha;
  final int orientationDegrees;
}

/// Total and free bytes of the device's primary storage.
///
/// Only reported when the OS actually exposes it; the UI must show "unavailable" otherwise
/// rather than inventing a number.
class DeviceStorageInfo {
  const DeviceStorageInfo({required this.totalBytes, required this.freeBytes});

  final int totalBytes;
  final int freeBytes;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);
}

/// Thrown when the native bridge reports a problem we should surface honestly.
class MediaCodecException implements Exception {
  const MediaCodecException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'MediaCodecException($code): $message';
}

/// Bridge to the platform image/video codec helpers (Kotlin on Android, Swift on iOS).
///
/// Only operations that genuinely need OS APIs live here:
/// * HEIC/HEIF (and platform AVIF) decoding, which pure Dart cannot do;
/// * writing finished files into the system photo library / MediaStore;
/// * asking the OS whether a hardware video encoder exists for a codec.
///
/// Everything else (resize, rotate, crop, standard encoders) is handled by the shared Dart
/// pipeline so behaviour stays identical on both platforms.
class MediaCodecBridge {
  MediaCodecBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName =
      'com.iwatdigital.apple_file_converter/codec';

  final MethodChannel _channel;

  /// Whether the OS can decode HEIC/HEIF images at all on this device.
  Future<bool> supportsHeic() async {
    try {
      final result = await _channel.invokeMethod<bool>('supportsHeic');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Decodes an image file to RGBA using the native stack.
  ///
  /// Returns null when the native stack cannot decode the file; callers must then report an
  /// honest "unsupported on this device" error rather than pretending success.
  Future<DecodedPixels?> decodeToRgba(
    String path, {
    int maxMegapixels = 80,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'decodeToRgba',
      <String, Object?>{'path': path, 'maxMegapixels': maxMegapixels},
    );
    if (result == null) {
      return null;
    }
    final pixels = result['pixels'];
    if (pixels is! Uint8List) {
      return null;
    }
    return DecodedPixels(
      pixels: pixels,
      width: (result['width'] as num?)?.toInt() ?? 0,
      height: (result['height'] as num?)?.toInt() ?? 0,
      orientationDegrees: (result['orientation'] as num?)?.toInt() ?? 0,
    );
  }

  /// Reads image dimensions/format without decoding all pixels.
  Future<NativeImageInfo?> probeImage(String path) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'probeImage',
      <String, Object?>{'path': path},
    );
    if (result == null) {
      return null;
    }
    final width = (result['width'] as num?)?.toInt() ?? 0;
    final height = (result['height'] as num?)?.toInt() ?? 0;
    if (width <= 0 || height <= 0) {
      return null;
    }
    return NativeImageInfo(
      width: width,
      height: height,
      format: ImageFormat.fromId(result['format'] as String? ?? 'unknown'),
      hasAlpha: result['hasAlpha'] as bool? ?? false,
      orientationDegrees: (result['orientation'] as num?)?.toInt() ?? 0,
    );
  }

  /// Writes a finished file into the system photo library (Photos / MediaStore).
  ///
  /// Returns a platform identifier on success, or null on failure. The original file is left
  /// untouched; we never move or delete sources.
  Future<String?> saveToPhotoLibrary(
    String path, {
    required bool isVideo,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'saveToPhotoLibrary',
      <String, Object?>{'path': path, 'isVideo': isVideo},
    );
    return result;
  }

  /// Asks the OS whether a hardware video encoder is available for [codec].
  Future<bool> hasHardwareEncoder(VideoCodec codec) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'hasHardwareEncoder',
        <String, Object?>{'codec': codec.id},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Exposes the platform kind so callers can pick the right encoder policy without importing
  /// `dart:io` themselves.
  PlatformKind get platform => PlatformInfo.kind;

  /// Total/free bytes of the device's primary storage, or null when unavailable.
  Future<DeviceStorageInfo?> deviceStorage() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'deviceStorage',
      );
      if (result == null) {
        return null;
      }
      final total = (result['totalBytes'] as num?)?.toInt() ?? 0;
      final free = (result['freeBytes'] as num?)?.toInt() ?? 0;
      if (total <= 0) {
        return null;
      }
      return DeviceStorageInfo(
        totalBytes: total,
        freeBytes: free.clamp(0, total),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
