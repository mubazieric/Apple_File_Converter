import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';

/// Cross-cutting UI helpers shared by every screen.

/// Shows a floating message. Errors use the error colour.
void showMessage(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.colors.error : null,
      ),
    );
}

/// Opens the system share sheet for one or more local files.
Future<void> sharePaths(
  BuildContext context,
  List<String> paths, {
  String? subject,
}) async {
  final existing = paths
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  if (existing.isEmpty) {
    showMessage(context, 'There is nothing to share.', error: true);
    return;
  }
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: existing.map(XFile.new).toList(growable: false),
        subject: subject,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        'Sharing is not available on this device.',
        error: true,
      );
    }
  }
}

/// Hands a local file to the OS "open with" mechanism.
Future<void> openPath(BuildContext context, String path) async {
  if (path.isEmpty) {
    showMessage(context, 'This result has no local file to open.', error: true);
    return;
  }
  try {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && context.mounted) {
      showMessage(context, 'No app found to open this file.', error: true);
    }
  } catch (_) {
    if (context.mounted) {
      showMessage(context, 'The file could not be opened.', error: true);
    }
  }
}

/// The file name portion of a path, for display.
String fileNameOf(String path) => p.basename(path);
