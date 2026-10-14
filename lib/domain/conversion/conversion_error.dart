/// Typed conversion failures.
///
/// The UI maps these to honest, actionable messages; the engine uses `isRecoverable` to decide
/// whether a batch may continue after a failure.
enum ConversionErrorCode {
  sourceMissing,
  sourceUnreadable,
  unsupportedInput,
  unsupportedOutput,
  decoderUnavailable,
  encoderUnavailable,
  decodeFailed,
  encodeFailed,
  outputMissing,
  outputEmpty,
  outputWrongFormat,
  outputWrongDimensions,
  outputMissingStreams,
  outputDurationMismatch,
  outOfMemory,
  outOfStorage,
  cancelled,
  timeout,
  ffmpegFailed,
  unsupportedOperation,
  internal,
}

class ConversionError {
  const ConversionError({
    required this.code,
    required this.message,
    this.detail,
    this.isRecoverable = true,
  });

  final ConversionErrorCode code;

  /// Short, user-facing explanation (already localisable-friendly, no media paths).
  final String message;

  /// Developer detail for logs. Must not contain sensitive media paths or metadata.
  final String? detail;

  /// Whether the rest of a batch may proceed after this failure.
  final bool isRecoverable;

  static const ConversionError cancelled = ConversionError(
    code: ConversionErrorCode.cancelled,
    message: 'Conversion was cancelled.',
    isRecoverable: true,
  );

  factory ConversionError.unsupportedInput(String what) => ConversionError(
    code: ConversionErrorCode.unsupportedInput,
    message: '$what is not a supported input on this device.',
    isRecoverable: true,
  );

  factory ConversionError.decode(String detail) => ConversionError(
    code: ConversionErrorCode.decodeFailed,
    message: 'The file could not be decoded. It may be corrupted or use an unsupported codec.',
    detail: detail,
  );

  factory ConversionError.encode(String detail) => ConversionError(
    code: ConversionErrorCode.encodeFailed,
    message: 'The output could not be encoded.',
    detail: detail,
  );

  factory ConversionError.validation(
    ConversionErrorCode code,
    String message, {
    String? detail,
  }) => ConversionError(code: code, message: message, detail: detail);

  @override
  String toString() =>
      'ConversionError(${code.name}: $message${detail == null ? '' : ' — $detail'})';
}

/// The outcome of a single conversion attempt.
sealed class ConversionOutcome {
  const ConversionOutcome();
}

class ConversionSuccess extends ConversionOutcome {
  const ConversionSuccess({
    required this.outputPath,
    required this.outputBytes,
    required this.sourceBytes,
    this.width,
    this.height,
    this.duration,
    this.videoCodec,
    this.audioCodec,
    this.wasRemux = false,
  });

  final String outputPath;
  final int outputBytes;
  final int sourceBytes;
  final int? width;
  final int? height;
  final Duration? duration;
  final String? videoCodec;
  final String? audioCodec;

  /// True when streams were copied rather than re-encoded.
  final bool wasRemux;

  int get bytesSaved => sourceBytes - outputBytes;

  double get savedFraction => sourceBytes <= 0 ? 0 : bytesSaved / sourceBytes;

  bool get isSmaller => outputBytes < sourceBytes;
}

class ConversionFailure extends ConversionOutcome {
  const ConversionFailure(this.error);

  final ConversionError error;
}
