import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

import 'pdf_crop_geometry.dart';

/// Reads page boxes and applies real PDF CropBox changes through PDFium.
class PdfCropService {
  const PdfCropService();

  Future<List<PdfCropBounds>> readVisibleBounds(
    PdfDocument document,
  ) async {
    for (final page in document.pages) {
      await page.ensureLoaded();
    }

    final pdfium = getPdfium();
    return document.useNativeDocumentHandle((nativeDocumentHandle) {
      final nativeDocument =
          ffi.Pointer<fpdf_document_t__>.fromAddress(nativeDocumentHandle);
      final result = <PdfCropBounds>[];

      for (var index = 0; index < document.pages.length; index++) {
        final nativePage = pdfium.FPDF_LoadPage(nativeDocument, index);
        if (nativePage.address == 0) {
          throw StateError('PDFium не смог открыть страницу ${index + 1}.');
        }

        final values = calloc<ffi.Float>(4);
        try {
          final hasMediaBox = pdfium.FPDFPage_GetMediaBox(
            nativePage,
            values,
            values.elementAt(1),
            values.elementAt(2),
            values.elementAt(3),
          );
          if (hasMediaBox == 0) {
            throw StateError(
              'Не удалось прочитать границы страницы ${index + 1}.',
            );
          }

          final mediaBox = PdfCropBounds(
            left: values[0],
            bottom: values[1],
            right: values[2],
            top: values[3],
          );

          final hasCropBox = pdfium.FPDFPage_GetCropBox(
            nativePage,
            values,
            values.elementAt(1),
            values.elementAt(2),
            values.elementAt(3),
          );
          final visibleBox = hasCropBox == 0
              ? mediaBox
              : PdfCropBounds(
                  left: values[0],
                  bottom: values[1],
                  right: values[2],
                  top: values[3],
                );
          visibleBox.validate();
          result.add(visibleBox);
        } finally {
          calloc.free(values);
          pdfium.FPDF_ClosePage(nativePage);
        }
      }
      return List.unmodifiable(result);
    });
  }

  /// Crops a separate in-memory copy and exports it without mutating the
  /// document currently displayed by the UI or the original file.
  Future<String> cropAndSave({
    required String sourcePath,
    required Map<int, NormalizedCropRect> selections,
    required String outputPath,
    bool overwriteExisting = false,
  }) async {
    if (selections.isEmpty) {
      throw ArgumentError('Не выбраны страницы для обрезки.');
    }

    final normalizedSource = p.normalize(p.absolute(sourcePath));
    final sourceFile = File(normalizedSource);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Исходный PDF не найден.', normalizedSource);
    }
    if (await sourceFile.length() == 0) {
      throw FileSystemException('Исходный PDF пуст.', normalizedSource);
    }

    final output = p.normalize(p.absolute(outputPath));
    if (p.extension(output).toLowerCase() != '.pdf') {
      throw ArgumentError('Выходной файл должен иметь расширение .pdf.');
    }

    final samePath = Platform.isWindows
        ? output.toLowerCase() == normalizedSource.toLowerCase()
        : output == normalizedSource;
    if (samePath) {
      throw ArgumentError('Нельзя сохранить результат поверх исходного PDF.');
    }

    final outputDirectory = Directory(p.dirname(output));
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final outputFile = File(output);
    if (await outputFile.exists() && !overwriteExisting) {
      throw FileSystemException(
        'Выходной файл уже существует. Подтвердите перезапись.',
        output,
      );
    }

    PdfDocument? sourceDocument;
    PdfDocument? resultDocument;
    final operationId = DateTime.now().microsecondsSinceEpoch;
    final temporaryFile = File('$output.$operationId.tmp');
    final backupFile = File('$output.$operationId.bak');
    var backedUp = false;
    var committed = false;

    try {
      sourceDocument = await PdfDocument.openFile(normalizedSource);
      final pageCount = sourceDocument.pages.length;
      if (pageCount < 1) {
        throw StateError('В документе нет страниц.');
      }
      for (final entry in selections.entries) {
        if (entry.key < 0 || entry.key >= pageCount) {
          throw RangeError('Страница ${entry.key + 1} не существует.');
        }
        entry.value.validate();
      }

      final bounds = await readVisibleBounds(sourceDocument);
      final pages = sourceDocument.pages;
      final pdfium = getPdfium();
      final changedPages = <int>[];

      await sourceDocument.useNativeDocumentHandle((nativeDocumentHandle) {
        final nativeDocument =
            ffi.Pointer<fpdf_document_t__>.fromAddress(nativeDocumentHandle);

        for (final entry in selections.entries) {
          final pageIndex = entry.key;
          final nativePage = pdfium.FPDF_LoadPage(nativeDocument, pageIndex);
          if (nativePage.address == 0) {
            throw StateError(
              'PDFium не смог открыть страницу ${pageIndex + 1}.',
            );
          }

          try {
            final cropBounds = PdfCropGeometry.toPdfBounds(
              selection: entry.value,
              visibleBounds: bounds[pageIndex],
              rotation: pages[pageIndex].rotation,
            );
            pdfium.FPDFPage_SetCropBox(
              nativePage,
              cropBounds.left,
              cropBounds.bottom,
              cropBounds.right,
              cropBounds.top,
            );
            changedPages.add(pageIndex + 1);
          } finally {
            pdfium.FPDF_ClosePage(nativePage);
          }
        }
      });

      await sourceDocument.reloadPages(
        pageNumbersToReload: changedPages,
      );

      resultDocument = await PdfDocument.createNew(sourceName: output);
      resultDocument.pages = List<PdfPage>.of(sourceDocument.pages);

      final bytes = await resultDocument.encodePdf();
      if (bytes.isEmpty) {
        throw StateError('PDFium вернул пустой результат обрезки.');
      }
      await temporaryFile.writeAsBytes(bytes, flush: true);

      if (await outputFile.exists()) {
        if (!overwriteExisting) {
          throw FileSystemException(
            'Выходной файл уже существует. Подтвердите перезапись.',
            output,
          );
        }
        await outputFile.rename(backupFile.path);
        backedUp = true;
      }

      await temporaryFile.rename(output);
      committed = true;

      if (await outputFile.length() == 0) {
        throw FileSystemException('Созданный PDF оказался пустым.', output);
      }

      if (backedUp && await backupFile.exists()) {
        try {
          await backupFile.delete();
          backedUp = false;
        } on FileSystemException {
          // Keep the backup rather than fail after a successful commit.
        }
      }
      return output;
    } on Object {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      if (committed && await outputFile.exists()) {
        await outputFile.delete();
      }
      if (backedUp && await backupFile.exists()) {
        await backupFile.rename(output);
      }
      rethrow;
    } finally {
      if (resultDocument != null) {
        await resultDocument.dispose();
      }
      if (sourceDocument != null) {
        await sourceDocument.dispose();
      }
    }
  }
}
