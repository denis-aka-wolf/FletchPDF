import 'dart:io';

import 'package:path/path.dart' as p;

import 'pdf_engine.dart';
import 'qpdf_locator.dart';

class QpdfEngine implements PdfEngine {
  QpdfEngine({required this.executablePath});

  final String executablePath;

  /// Creates an engine only when a usable QPDF executable can be located.
  static Future<QpdfEngine?> discover({String? configuredPath}) async {
    final executable = await const QpdfLocator().locate(
      configuredPath: configuredPath,
    );
    if (executable == null) return null;
    return QpdfEngine(executablePath: executable);
  }

  @override
  String get id => 'qpdf';

  @override
  String get displayName => 'QPDF';

  @override
  Future<EngineStatus> checkAvailability() async {
    final executable = File(executablePath);
    if (!await executable.exists()) {
      return const EngineStatus(
        available: false,
        message: 'QPDF не найден. Проверьте комплект поставки движка.',
      );
    }

    try {
      final result = await Process.run(
        executablePath,
        const ['--version'],
        runInShell: false,
      );

      if (result.exitCode != 0) {
        final details = _cleanOutput(result.stderr);
        return EngineStatus(
          available: false,
          message: details.isEmpty
              ? 'QPDF завершился с кодом ${result.exitCode}.'
              : details,
        );
      }

      return EngineStatus(
        available: true,
        version: _cleanOutput(result.stdout),
      );
    } on ProcessException catch (error) {
      return EngineStatus(available: false, message: error.message);
    }
  }

  Future<void> merge({
    required List<String> inputPaths,
    required String outputPath,
  }) async {
    if (inputPaths.length < 2) {
      throw ArgumentError('Для объединения необходимо выбрать минимум два PDF.');
    }

    if (inputPaths.any((path) => path.trim().isEmpty)) {
      throw ArgumentError('Путь входного файла не может быть пустым.');
    }

    final normalizedOutput = p.normalize(p.absolute(outputPath));
    for (final inputPath in inputPaths) {
      final normalizedInput = p.normalize(p.absolute(inputPath));
      final samePath = Platform.isWindows
          ? normalizedInput.toLowerCase() == normalizedOutput.toLowerCase()
          : normalizedInput == normalizedOutput;
      if (samePath) {
        throw ArgumentError(
          'Выходной файл не должен совпадать с исходным PDF.',
        );
      }
    }

    for (final inputPath in inputPaths) {
      if (!await File(inputPath).exists()) {
        throw FileSystemException('Входной PDF не найден.', inputPath);
      }
    }

    final output = File(normalizedOutput);
    final outputDirectory = Directory(p.dirname(normalizedOutput));
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final args = <String>['--empty', '--pages'];
    for (final inputPath in inputPaths) {
      args
        ..add(p.absolute(inputPath))
        ..add('1-z');
    }
    args
      ..add('--')
      ..add(normalizedOutput);

    final result = await Process.run(
      executablePath,
      args,
      runInShell: false,
    );

    if (result.exitCode != 0) {
      final stderr = _cleanOutput(result.stderr);
      final stdout = _cleanOutput(result.stdout);
      final details = stderr.isNotEmpty ? stderr : stdout;
      throw ProcessException(
        executablePath,
        args,
        details.isEmpty
            ? 'QPDF завершился с кодом ${result.exitCode}.'
            : details,
        result.exitCode,
      );
    }

    if (!await output.exists() || await output.length() == 0) {
      throw FileSystemException(
        'QPDF завершился без ошибки, но выходной файл не создан.',
        output.path,
      );
    }
  }

  String _cleanOutput(Object? value) {
    return value?.toString().trim() ?? '';
  }
}
