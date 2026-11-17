import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Creates one PDF containing the selected pages in the requested order.
class PdfExtractService {
  const PdfExtractService();

  Future<String> extract({
    required String inputPath,
    required String outputPath,
    required List<int> pageNumbers,
    bool overwriteExisting = false,
  }) async {
    if (pageNumbers.isEmpty) {
      throw ArgumentError('Выберите хотя бы одну страницу для извлечения.');
    }

    final input = p.normalize(p.absolute(inputPath));
    final output = p.normalize(p.absolute(outputPath));
    if (p.extension(input).toLowerCase() != '.pdf' ||
        p.extension(output).toLowerCase() != '.pdf') {
      throw ArgumentError('Входной и выходной файлы должны иметь расширение .pdf.');
    }
    if (_pathKey(input) == _pathKey(output)) {
      throw ArgumentError('Выходной файл не должен совпадать с исходным PDF.');
    }

    final inputFile = File(input);
    if (!await inputFile.exists()) {
      throw FileSystemException('Исходный PDF не найден.', input);
    }
    if (await inputFile.length() == 0) {
      throw FileSystemException('Исходный PDF пуст.', input);
    }

    final outputFile = File(output);
    if (await outputFile.exists() && !overwriteExisting) {
      throw FileSystemException(
        'Выходной файл уже существует. Подтвердите перезапись.',
        output,
      );
    }

    final uniquePages = <int>{};
    for (final number in pageNumbers) {
      if (number < 1) {
        throw ArgumentError('Номер страницы должен быть не меньше 1.');
      }
      if (!uniquePages.add(number)) {
        throw ArgumentError('Страница $number указана более одного раза.');
      }
    }

    final directory = Directory(p.dirname(output));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final operationId = DateTime.now().microsecondsSinceEpoch;
    final temporaryPath = '$output.$operationId.tmp';
    final backupPath = '$output.$operationId.bak';
    final temporaryFile = File(temporaryPath);
    final backupFile = File(backupPath);
    PdfDocument? sourceDocument;
    PdfDocument? outputDocument;
    var originalBackedUp = false;
    var newOutputCommitted = false;

    try {
      sourceDocument = await PdfDocument.openFile(input);
      final sourcePages = sourceDocument.pages;

      for (final number in pageNumbers) {
        if (number > sourcePages.length) {
          throw RangeError(
            'Страница $number отсутствует. В документе всего ${sourcePages.length} страниц.',
          );
        }
      }

      outputDocument = await PdfDocument.createNew(sourceName: output);
      outputDocument.pages = [
        for (final number in pageNumbers) sourcePages[number - 1],
      ];

      final bytes = await outputDocument.encodePdf();
      if (bytes.isEmpty) {
        throw StateError('PDFium вернул пустой результат извлечения страниц.');
      }
      await temporaryFile.writeAsBytes(bytes, flush: true);

      if (await outputFile.exists()) {
        if (!overwriteExisting) {
          throw FileSystemException(
            'Выходной файл уже существует. Подтвердите перезапись.',
            output,
          );
        }
        await outputFile.rename(backupPath);
        originalBackedUp = true;
      }

      await temporaryFile.rename(output);
      newOutputCommitted = true;

      if (await outputFile.length() == 0) {
        throw FileSystemException('Созданный PDF оказался пустым.', output);
      }

      if (originalBackedUp && await backupFile.exists()) {
        try {
          await backupFile.delete();
          originalBackedUp = false;
        } on FileSystemException {
          // Keep the backup rather than fail after committing the new file.
        }
      }
      return output;
    } on Object {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      if (newOutputCommitted && await outputFile.exists()) {
        await outputFile.delete();
      }
      if (originalBackedUp && await backupFile.exists()) {
        await backupFile.rename(output);
      }
      rethrow;
    } finally {
      if (outputDocument != null) {
        await outputDocument.dispose();
      }
      if (sourceDocument != null) {
        await sourceDocument.dispose();
      }
    }
  }

  String _pathKey(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;
}

/// Parses page selections such as `1-3, 5, 8-10`.
class PageSelectionParser {
  const PageSelectionParser._();

  static List<int> parse(String input, {required int pageCount}) {
    if (pageCount < 1) {
      throw ArgumentError('В документе нет страниц.');
    }
    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Укажите страницы для извлечения.');
    }

    final selected = <int>[];
    final seen = <int>{};
    for (final rawPart in normalized.split(',')) {
      final part = rawPart.trim();
      if (part.isEmpty) {
        throw const FormatException('Обнаружен пустой элемент списка страниц.');
      }
      final match = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(part);
      if (match == null) {
        throw FormatException(
          'Некорректный диапазон "$part". Используйте, например, 1-3, 5.',
        );
      }
      final first = int.parse(match.group(1)!);
      final last = int.parse(match.group(2) ?? match.group(1)!);
      if (first > last) {
        throw FormatException('Начало диапазона "$part" больше его конца.');
      }
      if (first < 1 || last > pageCount) {
        throw RangeError(
          'Диапазон "$part" выходит за пределы документа. Допустимые страницы: 1-$pageCount.',
        );
      }
      for (var page = first; page <= last; page++) {
        if (!seen.add(page)) {
          throw FormatException('Страница $page указана более одного раза.');
        }
        selected.add(page);
      }
    }
    return List.unmodifiable(selected);
  }
}
