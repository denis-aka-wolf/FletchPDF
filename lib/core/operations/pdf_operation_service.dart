import 'dart:io';

import '../engines/qpdf_engine.dart';
import 'operation_result.dart';

/// Application-level PDF workflows.
///
/// Widgets call this service rather than invoking native tools directly.
class PdfOperationService {
  const PdfOperationService(this._qpdfEngine);

  final QpdfEngine _qpdfEngine;

  Future<OperationResult> merge({
    required List<String> inputPaths,
    required String outputPath,
  }) async {
    try {
      if (inputPaths.length < 2) {
        throw ArgumentError('Для объединения выберите не менее двух PDF-файлов.');
      }

      final normalizedInputs = <String>[];
      for (final inputPath in inputPaths) {
        final file = File(inputPath);
        if (!await file.exists()) {
          throw FileSystemException('Входной файл не найден.', inputPath);
        }
        if (await file.length() == 0) {
          throw FileSystemException('Входной PDF пуст.', inputPath);
        }
        normalizedInputs.add(file.absolute.path);
      }

      final normalizedOutput = File(outputPath).absolute.path;
      if (normalizedInputs.any(
        (input) => _samePath(input, normalizedOutput),
      )) {
        throw ArgumentError(
          'Выходной файл не должен совпадать ни с одним исходным документом.',
        );
      }

      final status = await _qpdfEngine.checkAvailability();
      if (!status.available) {
        throw StateError(
          status.message ?? 'Движок QPDF недоступен.',
        );
      }

      await _qpdfEngine.merge(
        inputPaths: normalizedInputs,
        outputPath: normalizedOutput,
      );

      return OperationResult.success(
        message: 'PDF-файлы успешно объединены.',
        outputPaths: [normalizedOutput],
      );
    } on Object catch (error, stackTrace) {
      return OperationResult.failure(
        message: 'Не удалось объединить PDF-файлы.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _samePath(String first, String second) {
    final a = first.replaceAll('\\', '/');
    final b = second.replaceAll('\\', '/');
    return Platform.isWindows
        ? a.toLowerCase() == b.toLowerCase()
        : a == b;
  }
}
