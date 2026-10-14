import 'package:path/path.dart' as p;

/// Controls how output files are named and how name collisions are resolved.
///
/// Pure Dart; no file system access. Callers pass an `isTaken` predicate so that the same
/// logic is unit-tested without touching disk.
class NamingPolicy {
  const NamingPolicy({
    this.template = '{name}_converted',
    this.keepOriginalOnCollision = true,
  });

  /// Template using `{name}`, `{format}`, `{date}`, `{time}`, `{index}`, `{width}`, `{height}`,
  /// `{preset}`. Unknown tokens are left untouched so users are not silently surprised.
  final String template;

  /// When true a colliding name gets a numeric suffix; the original file is never overwritten.
  final bool keepOriginalOnCollision;

  static const String defaultTemplate = '{name}_converted';

  static const List<String> tokens = <String>[
    '{name}',
    '{format}',
    '{date}',
    '{time}',
    '{index}',
    '{width}',
    '{height}',
    '{preset}',
  ];

  static final RegExp _illegalChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Windows reserved device names, which are invalid as file names on any platform we target
  /// for sharing (users copy converted files to Windows).
  static const Set<String> _reservedNames = <String>{
    'con',
    'prn',
    'aux',
    'nul',
    'com1',
    'com2',
    'com3',
    'com4',
    'com5',
    'com6',
    'com7',
    'com8',
    'com9',
    'lpt1',
    'lpt2',
    'lpt3',
    'lpt4',
    'lpt5',
    'lpt6',
    'lpt7',
    'lpt8',
    'lpt9',
  };

  /// Strips a file extension from a name (`.tar.gz` → `tar` is not attempted; media names are
  /// single-extension in practice).
  static String baseName(String fileName) {
    final name = p.basenameWithoutExtension(fileName);
    return name.isEmpty ? 'file' : name;
  }

  /// Makes an arbitrary string safe to use as a file name component.
  static String sanitise(String input, {int maxLength = 120}) {
    var value = input.replaceAll(_illegalChars, '_');
    value = value.replaceAll(_whitespaceRun, ' ').trim();
    // Collapse leading/trailing dots which are problematic or hidden on some platforms.
    value = value.replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (_reservedNames.contains(value.toLowerCase())) {
      value = '${value}_file';
    }
    if (value.length > maxLength) {
      value = value.substring(0, maxLength).trim();
    }
    if (value.isEmpty) {
      value = 'file';
    }
    return value;
  }

  /// Expands the template into a base name (without extension).
  String buildBaseName({
    required String sourceFileName,
    required String formatExtension,
    required DateTime timestamp,
    int index = 0,
    int? width,
    int? height,
    String? preset,
  }) {
    final raw = template
        .replaceAll('{name}', baseName(sourceFileName))
        .replaceAll('{format}', formatExtension)
        .replaceAll('{date}', _date(timestamp))
        .replaceAll('{time}', _time(timestamp))
        .replaceAll('{index}', (index + 1).toString().padLeft(2, '0'))
        .replaceAll('{width}', width?.toString() ?? '')
        .replaceAll('{height}', height?.toString() ?? '')
        .replaceAll('{preset}', preset ?? '');
    return sanitise(raw);
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}'
      '${d.second.toString().padLeft(2, '0')}';

  /// Returns `base.extension`, or `base (n).extension` until [isTaken] returns false.
  String uniqueFileName({
    required String baseName,
    required String extension,
    required bool Function(String fileName) isTaken,
    int maxAttempts = 999,
  }) {
    final safeBase = sanitise(baseName);
    final safeExt = extension.replaceFirst('.', '');
    var candidate = '$safeBase.$safeExt';
    if (!keepOriginalOnCollision || !isTaken(candidate)) {
      return candidate;
    }
    for (var i = 1; i <= maxAttempts; i++) {
      candidate = '$safeBase ($i).$safeExt';
      if (!isTaken(candidate)) {
        return candidate;
      }
    }
    // Extremely unlikely; fall back to a timestamp to guarantee uniqueness.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '$safeBase $stamp.$safeExt';
  }

  NamingPolicy copyWith({String? template, bool? keepOriginalOnCollision}) =>
      NamingPolicy(
        template: template ?? this.template,
        keepOriginalOnCollision:
            keepOriginalOnCollision ?? this.keepOriginalOnCollision,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'template': template,
    'keepOriginalOnCollision': keepOriginalOnCollision,
  };

  static NamingPolicy fromJson(Map<String, Object?> json) => NamingPolicy(
    template: json['template'] as String? ?? defaultTemplate,
    keepOriginalOnCollision: json['keepOriginalOnCollision'] as bool? ?? true,
  );
}
