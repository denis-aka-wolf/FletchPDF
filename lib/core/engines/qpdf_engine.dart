import 'dart:io';

import 'package:path/path.dart' as p;

import 'pdf_engine.dart';

class QpdfEngine implements PdfEngine {
  QpdfEngine({required this.executablePath});

  final String executablePath;

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
        return EngineStatus(
          available: false,
          message: _cleanOutput(result.stderr),
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

    final output = File(outputPath);
    final outputDirectory = Directory(p.dirname(output.absolute.path));
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final args = <String>['--empty', '--pages'];
    for (final inputPath in inputPaths) {
      args
        ..add(inputPath)
        ..add('1-z');
    }
    args
      ..add('--')
      ..add(output.absolute.path);

    final result = await Process.run(
      executablePath,
      args,
      runInShell: false,
    );

    if (result.exitCode != 0) {
      final details = _cleanOutput(result.stderr);
      throw ProcessException(
        executablePath,
        args,
        details.isEmpty ? 'QPDF завершился с кодом ${result.exitCode}.' : details,
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
