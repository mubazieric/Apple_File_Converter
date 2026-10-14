/// Human-readable formatting helpers used across the UI.
///
/// Numbers are formatted with decimal (SI) units, which is what Android's storage settings and
/// most consumer tools use. We never throw on bad input — corrupted values render as `—`.
abstract final class ByteFormat {
  static const String unknown = '—';

  static const List<String> _units = <String>['B', 'KB', 'MB', 'GB', 'TB'];

  /// Formats [bytes] as e.g. `1.4 MB`. Returns [unknown] when null or negative.
  static String binary(int? bytes, {int decimals = 1}) {
    if (bytes == null || bytes < 0) {
      return unknown;
    }
    if (bytes < 1000) {
      return '$bytes B';
    }
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1000 && unit < _units.length - 1) {
      value /= 1000;
      unit++;
    }
    final formatted = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(decimals);
    return '$formatted ${_units[unit]}';
  }

  /// Formats a signed difference, e.g. `−2.1 MB` (saved) or `+340 KB` (larger).
  static String difference(int? bytes) {
    if (bytes == null) {
      return unknown;
    }
    if (bytes == 0) {
      return '0 B';
    }
    final magnitude = binary(bytes.abs());
    return bytes > 0 ? '−$magnitude' : '+$magnitude';
  }

  static String percent(double? fraction, {int decimals = 0}) {
    if (fraction == null || fraction.isNaN || fraction.isInfinite) {
      return unknown;
    }
    final value = fraction * 100;
    return '${value.toStringAsFixed(decimals)}%';
  }

  /// Compact duration, e.g. `0:42`, `3:07`, `1:02:03`.
  static String duration(Duration? duration) {
    if (duration == null || duration.isNegative) {
      return unknown;
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// `1:02:03.4` style, used for trim handles where sub-second precision matters.
  static String durationPrecise(Duration? value) {
    if (value == null || value.isNegative) {
      return unknown;
    }
    final tenths = (value.inMilliseconds.remainder(1000) / 100).floor();
    return '${ByteFormat.duration(value)}.$tenths';
  }

  /// Formats a large count, e.g. `1.2k`.
  static String count(int value) {
    if (value < 1000) {
      return '$value';
    }
    if (value < 1000000) {
      return '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}k';
    }
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
}
