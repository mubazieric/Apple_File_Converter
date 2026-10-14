/// Storage mathematics used by the dashboard, batch summaries and history.
///
/// Pure functions with explicit handling of unknown values, so the tests can pin the exact
/// behaviour shown to users.
abstract final class StorageMath {
  /// Bytes saved by converting [sourceBytes] into [outputBytes].
  /// Positive = smaller output. Null when either value is unknown.
  static int? bytesSaved(int? sourceBytes, int? outputBytes) {
    if (sourceBytes == null || outputBytes == null) {
      return null;
    }
    return sourceBytes - outputBytes;
  }

  /// Fraction saved (0.0–1.0). Null when unknown; clamped to [-1, 1] so a doubled file shows
  /// as −100% rather than something nonsensical.
  static double? savedFraction(int? sourceBytes, int? outputBytes) {
    if (sourceBytes == null || outputBytes == null || sourceBytes <= 0) {
      return null;
    }
    return ((sourceBytes - outputBytes) / sourceBytes).clamp(-1.0, 1.0);
  }

  /// Total bytes saved across a list of (source, output) pairs, ignoring unknown entries.
  static int totalSaved(Iterable<(int?, int?)> pairs) {
    var total = 0;
    for (final (source, output) in pairs) {
      total += bytesSaved(source, output) ?? 0;
    }
    return total;
  }

  /// Aggregate saved fraction across several conversions (total-based, not an average of
  /// fractions, so one huge file cannot be drowned out by tiny ones).
  static double? aggregateFraction(Iterable<(int?, int?)> pairs) {
    var sourceTotal = 0;
    var outputTotal = 0;
    for (final (source, output) in pairs) {
      if (source == null || output == null) {
        continue;
      }
      sourceTotal += source;
      outputTotal += output;
    }
    if (sourceTotal <= 0) {
      return null;
    }
    return ((sourceTotal - outputTotal) / sourceTotal).clamp(-1.0, 1.0);
  }

  /// Whether a batch would plausibly fit in [freeBytes], allowing a safety margin.
  static bool fitsInStorage({
    required int estimatedBytes,
    required int freeBytes,
    double safetyMargin = 0.15,
  }) {
    if (freeBytes <= 0) {
      return false;
    }
    final budget = freeBytes * (1 - safetyMargin);
    return estimatedBytes <= budget;
  }

  /// Free-space warning level for the storage dashboard.
  static StoragePressure pressure({
    required int freeBytes,
    required int totalBytes,
  }) {
    if (totalBytes <= 0) {
      return StoragePressure.unknown;
    }
    final free = freeBytes / totalBytes;
    if (free < 0.05) {
      return StoragePressure.critical;
    }
    if (free < 0.12) {
      return StoragePressure.warning;
    }
    return StoragePressure.ok;
  }
}

enum StoragePressure { unknown, ok, warning, critical }
