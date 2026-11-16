import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates QPDF without invoking a shell.
///
/// Search order:
/// 1. Explicit path supplied by the user.
/// 2. Application-local engines directory.
/// 3. Directories listed in PATH.
class QpdfLocator {
  const QpdfLocator();

  Future<String?> locate({String? configuredPath}) async {
    final candidates = <String>[];

    if (configuredPath != null && configuredPath.trim().isNotEmpty) {
      candidates.add(configuredPath.trim());
    }

    final executableName = Platform.isWindows ? 'qpdf.exe' : 'qpdf';

    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    candidates.add(p.join(executableDirectory, 'engines', 'qpdf', 'bin', executableName));
    candidates.add(p.join(executableDirectory, 'engines', 'qpdf', executableName));
    candidates.add(p.join(executableDirectory, 'data', 'engines', 'qpdf', executableName));

    final pathValue = Platform.environment['PATH'] ?? '';
    for (final directory in pathValue.split(Platform.isWindows ? ';' : ':')) {
      if (directory.trim().isNotEmpty) {
        candidates.add(p.join(directory.trim(), executableName));
      }
    }

    final seen = <String>{};
    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (!seen.add(Platform.isWindows ? normalized.toLowerCase() : normalized)) {
        continue;
      }
      if (await File(normalized).exists()) return normalized;
    }

    return null;
  }
}
