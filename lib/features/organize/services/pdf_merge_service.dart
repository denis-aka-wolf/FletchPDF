import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Combines pages with the PDFium engine already used by the viewer.
///
/// No external executable, server, or network connection is required.
class PdfMergeService {
  const PdfMergeService();

  Future<void> merge({
    required List<String> inputPaths,
    required String outputPath,
    bool overwriteExisting = false,
  }) async {
    if (inputPaths.length < 2) {
      throw ArgumentError('Для объединения выберите не менее двух PDF-файлов.');
    }

    final normalizedInputs = inputPaths
        .map((value) => p.normalize(p.absolute(value)))
        .toList(growable: false);
    final normalizedOutput = p.normalize(p.absolute(outputPath));

    final uniqueInputs = <String>{};
    for (final input in normalizedInputs) {
      final key = Platform.isWindows ? input.toLowerCase() : input;
      if (!uniqueInputs.add(key)) {
        throw ArgumentError('Один и тот же PDF добавлен в список несколько раз.');
      }
      if (!_hasPdfExtension(input)) {
        throw ArgumentError('Файл не имеет расширения PDF: $input');
      }
      if (_samePath(input, normalizedOutput)) {
        throw ArgumentError('Выходной файл не должен совпадать с исходным PDF.');
      }

      final file = File(input);
      if (!await file.exists()) {
        throw FileSystemException('Входной PDF не найден.', input);
      }
      if (await file.length() == 0) {
        throw FileSystemException('Входной PDF пуст.', input);
      }
    }

    if (!_hasPdfExtension(normalizedOutput)) {
      throw ArgumentError('Имя выходного файла должно иметь расширение .pdf.');
    }

    final outputFile = File(normalizedOutput);
    if (await outputFile.exists() && !overwriteExisting) {
      throw FileSystemException(
        'Выходной файл уже существует. Подтвердите перезапись.',
        normalizedOutput,
      );
    }

    final outputDirectory = Directory(p.dirname(normalizedOutput));
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final operationId = DateTime.now().microsecondsSinceEpoch;
    final temporaryPath = '$normalizedOutput.$operationId.tmp';
    final backupPath = '$normalizedOutput.$operationId.bak';
    final temporaryFile = File(temporaryPath);
    final backupFile = File(backupPath);

    final sourceDocuments = <PdfDocument>[];
    PdfDocument? outputDocument;
    var originalMovedToBackup = false;

    try {
      for (final input in normalizedInputs) {
        sourceDocuments.add(await PdfDocument.openFile(input));
      }

      final pages = <PdfPage>[
        for (final document in sourceDocuments) ...document.pages,
      ];

      if (pages.isEmpty) {
        throw StateError('В выбранных документах нет страниц для объединения.');
      }

      outputDocument = await PdfDocument.createNew(
        sourceName: normalizedOutput,
      );
      outputDocument.pages = pages;

      final bytes = await outputDocument.encodePdf();
      if (bytes.isEmpty) {
        throw StateError('PDFium вернул пустой результат объединения.');
      }

      await temporaryFile.writeAsBytes(bytes, flush: true);

      if (await outputFile.exists()) {
        if (!overwriteExisting) {
          throw FileSystemException(
            'Выходной файл уже существует. Подтвердите перезапись.',
            normalizedOutput,
          );
        }
        await outputFile.rename(backupPath);
        originalMovedToBackup = true;
      }

      await temporaryFile.rename(normalizedOutput);

      if (originalMovedToBackup && await backupFile.exists()) {
        await backupFile.delete();
        originalMovedToBackup = false;
      }

      if (await outputFile.length() == 0) {
        throw FileSystemException(
          'Созданный PDF оказался пустым.',
          normalizedOutput,
        );
      }
    } on Object {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }

      if (originalMovedToBackup && await backupFile.exists()) {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
        await backupFile.rename(normalizedOutput);
      }
      rethrow;
    } finally {
      if (outputDocument != null) {
        await outputDocument.dispose();
      }
      for (final document in sourceDocuments.reversed) {
        await document.dispose();
      }
    }
  }

  bool _hasPdfExtension(String path) {
    return p.extension(path).toLowerCase() == '.pdf';
  }

  bool _samePath(String first, String second) {
    return Platform.isWindows
        ? first.toLowerCase() == second.toLowerCase()
        : first == second;
  }
}
