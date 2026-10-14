import '../../domain/conversion/conversion_error.dart';
import '../../domain/conversion/conversion_request.dart';

/// Reports progress in the range 0.0–1.0, with an optional human-readable step message.
typedef ProgressCallback = void Function(double progress, {String? message});

/// Cooperative cancellation.
///
/// The engines check this between stages. Nothing here claims to *resume* a partially written
/// file — cancellation discards the partial output, and a retry starts from the beginning.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const ConversionCancelledException();
    }
  }
}

class ConversionCancelledException implements Exception {
  const ConversionCancelledException();

  @override
  String toString() => 'ConversionCancelledException';
}

/// Common contract for the image and video engines.
abstract interface class ConversionEngine<T extends ConversionRequest> {
  /// Executes one conversion. Never throws for expected failures — returns
  /// [ConversionFailure] instead so the queue can continue. Programming errors may still throw.
  Future<ConversionOutcome> convert(
    T request, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  });

  /// Whether this engine can process [request] on the current device, without running it.
  ///
  /// Used to disable unsupported options in the UI before the user starts a batch.
  Future<bool> canHandle(T request);
}
