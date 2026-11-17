import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Splits a PDF into multiple documents using selected page groups.
///
/// A group becomes one output PDF. Page numbers are 1-based in the UI.
class PdfSplitService {
  const PdfSplitService();

  Future<List<String>> split({
    required String inputPath,
    required List<List<int>> pageGroups,
    required List<String> outputPaths,
    bool overwriteExisting = false,
  }) async {
    if (pageGroups.length < 2) {
      throw ArgumentError(
        'Для разделения укажите не менее двух групп страниц.',
      );
    }
    if (pageGroups.length != outputPaths.length) {
      throw ArgumentError(
        'Количество групп страниц должно совпадать с количеством выходных файлов.',
      );
    }

    final normalizedInput = p.normalize(p.absolute(inputPath));
    if (p.extension(normalizedInput).toLowerCase() != '.pdf') {
      throw ArgumentError('Входной файл должен иметь расширение .pdf.');
    }

    final inputFile = File(normalizedInput);
    if (!await inputFile.exists()) {
      throw FileSystemException('Входной PDF не найден.', normalizedInput);
    }
    if (await inputFile.length() == 0) {
      throw FileSystemException('Входной PDF пуст.', normalizedInput);
    }

    final normalizedOutputs = outputPaths
        .map((path) => p.normalize(p.absolute(path)))
        .toList(growable: false);
    final outputKeys = <String>{};

    for (final outputPath in normalizedOutputs) {
      if (p.extension(outputPath).toLowerCase() != '.pdf') {
        throw ArgumentError(
          'Каждый выходной файл должен иметь расширение .pdf.',
        );
      }
      if (_samePath(normalizedInput, outputPath)) {
        throw ArgumentError(
          'Выходной файл не должен совпадать с исходным PDF.',
        );
      }
      if (!outputKeys.add(_pathKey(outputPath))) {
        throw ArgumentError('Пути выходных файлов должны быть уникальными.');
      }

      final outputFile = File(outputPath);
      if (await outputFile.exists() && !overwriteExisting) {
        throw FileSystemException(
          'Выходной файл уже существует. Подтвердите перезапись.',
          outputPath,
        );
      }
    }

    final usedPages = <int>{};
    for (final group in pageGroups) {
      if (group.isEmpty) {
        throw ArgumentError('Группа страниц не может быть пустой.');
      }
      for (final pageNumber in group) {
        if (pageNumber < 1) {
          throw ArgumentError('Номер страницы должен быть не меньше 1.');
        }
        if (!usedPages.add(pageNumber)) {
          throw ArgumentError(
            'Страница $pageNumber указана в нескольких группах.',
          );
        }
      }
    }

    final operationId = DateTime.now().microsecondsSinceEpoch;
    final temporaryPaths = <String>[];
    final backupPaths = <String, String>{};
    final committedPaths = <String>[];

    PdfDocument? sourceDocument;

    try {
      sourceDocument = await PdfDocument.openFile(normalizedInput);
      final sourcePages = sourceDocument.pages;
      if (sourcePages.isEmpty) {
        throw StateError('В исходном PDF нет страниц.');
      }

      for (final pageNumber in usedPages) {
        if (pageNumber > sourcePages.length) {
          throw RangeError(
            'Страница $pageNumber отсутствует. '
            'В документе всего ${sourcePages.length} страниц.',
          );
        }
      }

      for (var index = 0; index < pageGroups.length; index++) {
        final outputPath = normalizedOutputs[index];
        final outputDirectory = Directory(p.dirname(outputPath));
        if (!await outputDirectory.exists()) {
          await outputDirectory.create(recursive: true);
        }

        final temporaryPath = '$outputPath.$operationId.$index.tmp';
        temporaryPaths.add(temporaryPath);

        final outputDocument = await PdfDocument.createNew(
          sourceName: outputPath,
        );

        try {
          outputDocument.pages = [
            for (final pageNumber in pageGroups[index])
              sourcePages[pageNumber - 1],
          ];

          final bytes = await outputDocument.encodePdf();
          if (bytes.isEmpty) {
            throw StateError(
              'PDFium вернул пустой результат для файла $outputPath.',
            );
          }

          await File(temporaryPath).writeAsBytes(bytes, flush: true);
        } finally {
          await outputDocument.dispose();
        }
      }

      // Move existing files aside only after every new PDF was generated.
      for (var index = 0; index < normalizedOutputs.length; index++) {
        final outputPath = normalizedOutputs[index];
        final outputFile = File(outputPath);

        if (await outputFile.exists()) {
          if (!overwriteExisting) {
            throw FileSystemException(
              'Выходной файл уже существует. Подтвердите перезапись.',
              outputPath,
            );
          }

          final backupPath = '$outputPath.$operationId.$index.bak';
          await outputFile.rename(backupPath);
          backupPaths[outputPath] = backupPath;
        }
      }

      for (var index = 0; index < normalizedOutputs.length; index++) {
        final outputPath = normalizedOutputs[index];
        await File(temporaryPaths[index]).rename(outputPath);
        committedPaths.add(outputPath);
      }

      for (final backupPath in backupPaths.values) {
        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
      }

      return List.unmodifiable(normalizedOutputs);
    } on Object {
      for (final outputPath in committedPaths.reversed) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      }

      for (final entry in backupPaths.entries) {
        final backupFile = File(entry.value);
        if (await backupFile.exists()) {
          await backupFile.rename(entry.key);
        }
      }

      for (final temporaryPath in temporaryPaths) {
        final temporaryFile = File(temporaryPath);
        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      }

      rethrow;
    } finally {
      if (sourceDocument != null) {
        await sourceDocument.dispose();
      }
    }
  }

  String _pathKey(String path) {
    return Platform.isWindows ? path.toLowerCase() : path;
  }

  bool _samePath(String first, String second) {
    return _pathKey(first) == _pathKey(second);
  }
}

/// Parses semicolon-separated output groups.
///
/// Examples:
/// - `1-3; 4-6; 7-10` creates three output files.
/// - `1, 3, 5; 2, 4, 6` creates two files with alternating pages.
class PageRangeParser {
  const PageRangeParser._();

  static List<List<int>> parseGroups(
    String input, {
    required int pageCount,
  }) {
    if (pageCount < 1) {
      throw ArgumentError('В документе нет страниц.');
    }

    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Укажите диапазоны страниц.');
    }

    final rawGroups = normalized.split(';');
    if (rawGroups.length < 2) {
      throw const FormatException(
        'Для разделения укажите минимум две группы через точку с запятой.',
      );
    }

    final allPages = <int>{};
    final groups = <List<int>>[];

    for (var groupIndex = 0; groupIndex < rawGroups.length; groupIndex++) {
      final rawGroup = rawGroups[groupIndex].trim();
      if (rawGroup.isEmpty) {
        throw FormatException(
          'Группа ${groupIndex + 1} не содержит страниц.',
        );
      }

      final pages = <int>[];
      final parts = rawGroup.split(',');

      for (final rawPart in parts) {
        final part = rawPart.trim();
        if (part.isEmpty) {
          throw FormatException(
            'Пустой элемент в группе ${groupIndex + 1}.',
          );
        }

        final match = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$')
            .firstMatch(part);
        if (match == null) {
          throw FormatException(
            'Некорректный диапазон "$part". Используйте, например, 1-3, 5.',
          );
        }

        final first = int.parse(match.group(1)!);
        final last = int.parse(match.group(2) ?? match.group(1)!);

        if (first < 1 || last < 1 || first > pageCount || last > pageCount) {
          throw RangeError(
            'Диапазон "$part" выходит за пределы документа. '
            'Допустимые страницы: 1-$pageCount.',
          );
        }
        if (first > last) {
          throw FormatException(
            'Начало диапазона "$part" больше его конца.',
          );
        }

        for (var page = first; page <= last; page++) {
          if (!allPages.add(page)) {
            throw FormatException(
              'Страница $page указана более одного раза.',
            );
          }
          pages.add(page);
        }
      }

      groups.add(List.unmodifiable(pages));
    }

    return List.unmodifiable(groups);
  }
}
