import 'dart:io';

import '../../domain/media/capability.dart';

/// Runtime platform classification used by the capability matrix and engines.
///
/// This is the only place in the app that reads `dart:io`'s `Platform`, so the rest of the
/// codebase can depend on the testable [PlatformKind] enum instead.
abstract final class PlatformInfo {
  static PlatformKind get kind {
    if (Platform.isAndroid) {
      return PlatformKind.android;
    }
    if (Platform.isIOS) {
      return PlatformKind.ios;
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return PlatformKind.desktop;
    }
    return PlatformKind.unknown;
  }

  static bool get isMobile => kind.isMobile;
  static bool get isAndroid => kind == PlatformKind.android;
  static bool get isIOS => kind == PlatformKind.ios;
}
